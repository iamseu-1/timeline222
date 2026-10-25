import 'dart:typed_data';
import 'dart:ui' as ui;

import 'cleartype.dart';
import 'text_paragraph.dart';

// 글자 방식 (나): 글자를 흰색으로 작은 그림판에 한 번 그려 두고, 장면마다 글줄 전부를 drawRawAtlas 한 번(그림판 장마다)으로 찍는다.
//  · 색과 투명도는 찍을 때 입힌다 → 같은 글자를 색마다 다시 만들지 않고, 이름이 드나들 때의 옅어짐을 층 없이 한다.
//  · 새 글자는 장면마다 정해진 만큼만 준비한다(예산). 준비가 안 된 글줄은 그 장면에 그리지 않고 다음 장면에 이어 간다.
//  · 돋보기 배율이 바뀌면 옛 그림을 같은 비율로 키워 쓰면서, 뒤에서 새 배율의 글자를 준비해 하나씩 바꾼다
//    (글자가 가로로만 늘어나는 일은 구조상 없다 — 배치 px은 그대로이고 그림만 키운다).
// 글자 사이 다듬기(커닝) · 이음 글자는 하지 않는다 — 한글 · 한문 · 숫자에는 영향이 없고, 로마자에서 글줄 방식과 폭이 3% 안에서 다를 수 있다.
// ClearType(계획 한 벌 P2 과제 3): 허락된 장면(lcdAllowed)의 불투명한 글줄은 구운 3x1 덮임을 ClearType 장 두 장에 두고 곱하기 · 더하기로 두 번 섞어 찍는다.
//  · 자리(펜 · 너비 · 바탕선)는 회색 판의 셈을 그대로 쓴다 — 회색 ↔ ClearType이 바뀔 때 글자가 뛰지 않게.
//  · 글줄의 글자가 하나라도 덜 구워졌거나 글꼴에 없으면 그 글줄은 통째로 회색 — 글자가 빠지거나 섞이지 않게.

class _Glyph {
  _Glyph(this.page, this.left, this.top, this.width, this.height, this.advance, this.scale, this.baseline);

  /// 이 글자가 찍힌 그림판의 장. 번호가 아니라 장을 직접 든다 — 옛 배율의 장을 버려도 다른 글자가 밀리지 않는다.
  final _Page page;

  /// [baseline]: 글자 칸 위에서 바탕선까지(그 배율의 px).
  final double left, top, width, height, advance, scale, baseline;
}

class _Run {
  _Run(this.glyphs, this.width, this.sharpAt);
  final List<_Glyph> glyphs;
  final double width;

  /// 모든 글자가 이 배율로 준비돼 있다(-1이면 옛 배율의 글자가 섞여 있어 다음 장면에 다시 본다).
  final double sharpAt;
}

class _Page {
  _Page(this.size);
  final int size;
  ui.Image? image;
  double penX = 1, penY = 1, rowHeight = 0;

  /// 아직 그림에 넣지 않은 새 글자(이번 장면의 끝에 한꺼번에 넣는다).
  final pending = <(ui.Paragraph, double, double, double)>[];

  Float32List transforms = Float32List(4 * 1024), rects = Float32List(4 * 1024);
  Int32List colors = Int32List(1024);
  int n = 0;

  void add(_Glyph g, double x, double y, int argb) {
    if (n == colors.length) {
      transforms = Float32List(n * 8)..setRange(0, n * 4, transforms);
      rects = Float32List(n * 8)..setRange(0, n * 4, rects);
      colors = Int32List(n * 2)..setRange(0, n, colors);
    }
    final p = n * 4;
    transforms[p] = 1 / g.scale;
    transforms[p + 1] = 0;
    transforms[p + 2] = x;
    transforms[p + 3] = y;
    rects[p] = g.left;
    rects[p + 1] = g.top;
    rects[p + 2] = g.left + g.width;
    rects[p + 3] = g.top + g.height;
    colors[n] = argb;
    n++;
  }
}

/// ClearType 장 하나: 같은 자리에 두 그림 — 덮임(빨 · 초 · 파 = 덮임 · 불투명)과 뒤집은 것(1 − 덮임 · 불투명).
class _LcdPage {
  _LcdPage(this.size) : cov = Uint8List(size * size * 4), inv = Uint8List(size * size * 4) {
    for (var i = 0; i < size * size; i++) {
      cov[i * 4 + 3] = 255;
      inv[i * 4] = inv[i * 4 + 1] = inv[i * 4 + 2] = inv[i * 4 + 3] = 255;
    }
  }
  final int size;
  final Uint8List cov, inv;

  /// 지금 찍는 두 그림 — 늘 같은 세대(둘을 함께 바꾼다).
  ui.Image? covImage, invImage;

  /// 세대: 글자를 넣을 때마다 하나씩 는다. [shownGen]은 지금 두 그림이 담은 세대 — 그 세대까지 넣은 글자만 ClearType으로 찍는다.
  /// 새 글자로 그림을 다시 뜨는 동안에도 앞 세대의 글자는 지금 그림으로 찍힌다(회색으로 돌아갔다 바뀌며 번쩍이지 않게).
  int gen = 0, shownGen = 0;
  bool building = false;

  /// 배율이 바뀌어 버린 장 — 늦게 떠진 그림은 받지 않고 놓는다.
  bool gone = false;
  double penX = 1, penY = 1, rowHeight = 0;
  Float32List transforms = Float32List(4 * 256), rects = Float32List(4 * 256);
  Int32List colors = Int32List(256);

  /// 조각마다 화면 화소의 네모(왼 · 위 · 오 · 아래 — 정수)와 글줄 안 차례의 홀짝. 한 묶음 안에서 조각이 겹치지 않게 나누는 데 쓴다.
  Int32List boxes = Int32List(4 * 256);
  Uint8List odd = Uint8List(256);
  int n = 0;

  void add(_LcdGlyph g, double x, double y, double scale, int argb, int devX, int devY, bool isOdd) {
    if (n == colors.length) {
      transforms = Float32List(n * 8)..setRange(0, n * 4, transforms);
      rects = Float32List(n * 8)..setRange(0, n * 4, rects);
      colors = Int32List(n * 2)..setRange(0, n, colors);
      boxes = Int32List(n * 8)..setRange(0, n * 4, boxes);
      odd = Uint8List(n * 2)..setRange(0, n, odd);
    }
    final p = n * 4;
    boxes[p] = devX;
    boxes[p + 1] = devY;
    boxes[p + 2] = devX + g.width;
    boxes[p + 3] = devY + g.height;
    odd[n] = isOdd ? 1 : 0;
    transforms[p] = 1 / scale;
    transforms[p + 1] = 0;
    transforms[p + 2] = x;
    transforms[p + 3] = y;
    rects[p] = g.u.toDouble();
    rects[p + 1] = g.v.toDouble();
    rects[p + 2] = (g.u + g.width).toDouble();
    rects[p + 3] = (g.v + g.height).toDouble();
    colors[n] = argb;
    n++;
  }
}

/// 구운 글자의 자리: 장 · 넣은 세대 · 장 안의 (u, v) · 펜과 바탕선 기준의 (left, top) · 크기(모두 화면 px).
class _LcdGlyph {
  _LcdGlyph(this.page, this.gen, this.u, this.v, this.left, this.top, this.width, this.height);
  final _LcdPage page;
  final int gen, u, v, left, top, width, height;
}

class AtlasText extends SceneText {
  AtlasText({this.pageSize = 1024, int Function()? clock, this.baker, String? Function(TextLook look)? fontFileOf})
      : _now = clock ?? _stopwatch(),
        fontFileOf = fontFileOf ?? sceneFontFile;
  final int pageSize;

  /// ClearType 글자를 굽는 쪽. 없으면(Windows가 아니거나 자료 처리부에 archive_glyphs가 없을 때) 늘 회색.
  final GlyphBaker? baker;

  /// 글자 생김새의 글꼴 파일. null이면 그 생김새는 회색(프리텐다드가 아닌 화면 글꼴 · 기울인 글자).
  final String? Function(TextLook look) fontFileOf;

  /// 이번 장면에 ClearType으로 찍어도 되는가 — 그림판(painter)이 장면마다 정한다(설계 3-2의 회색으로 그리는 때가 아니면 참).
  bool lcdAllowed = false;

  /// 모니터의 칸 차례가 파초빨인가(Windows 설정 — 과제 4가 정함).
  bool bgr = false;

  // (글자, 크기, 굵기, 배율의 1/100) → 구운 글자. 없음(null) = 그 글꼴에 없는 글자(또는 굽지 못한 글자) — 그 글줄은 회색.
  final _lcd = <(int, double, int, int), _LcdGlyph?>{};

  /// 잉크 없는 글자(NBSP · 전각 빈칸 · 폭 없는 빈칸 — 구운 답이 ok이고 너비 0)의 표지. 0x20처럼 그 글자만 회색 조각(빈 그림)으로 지나가고
  /// 글줄은 ClearType이 된다 — 글꼴에 없음(null)으로 적으면 그 글줄이 그 배율에서 영영 회색이다.
  static final _blankLcd = _LcdGlyph(_LcdPage(0), 0, 0, 0, 0, 0, 0, 0);

  /// 엔진은 굽기 요청을 256KB(글자 하나 25~27바이트 → 약 1만 자)까지 받는다 — 한 묶음을 이만큼씩 나눠 청해 넘지 않게
  /// (넘으면 오류로 그 묶음의 글자가 모두 그 배율에서 회색으로 굳는다).
  static const bakeChunk = 4096;

  /// 굽기를 청했거나(굽는 중) 이번 장면에 청할 글자의 열쇠.
  final _lcdAsked = <(int, double, int, int)>{};

  /// 청할 굽기: (글꼴 파일, 화면 크기 px) → 글자 → 그 글자를 기다리는 열쇠들. 장면 동안 모아 다음 장면의 앞(beginFrame)에 묶음마다 한 번 청한다 —
  /// 글줄마다 청하면 멈춘 첫 장면에 굽기(isolate)가 글줄 수만큼 뜬다. 생김새가 달라도 글꼴 파일 · 크기가 같으면 한 묶음.
  final _lcdWant = <(String, double), Map<int, List<(int, double, int, int)>>>{};

  // 배율(1/100)마다 제 ClearType 장들 — 회색 장처럼 지금 · 직전 · 100% 밖 배율의 장은 통째로 버린다(장 하나 ≈ 바이트 8MB · 그림 8MB).
  final _lcdPagesOf = <int, List<_LcdPage>>{};
  List<_LcdPage>? _lcdFlat;
  List<_LcdPage> get _lcdPages => _lcdFlat ??= [for (final pages in _lcdPagesOf.values) ...pages];
  int _lcdSprites = 0;

  /// 검사용: 이번 장면에 ClearType으로 찍은 글자 수.
  int get lcdSprites => _lcdSprites;

  /// 굽는 중이거나 다음 장면의 앞에 굽기를 청할 글자 수.
  int get lcdPending => _lcdAsked.length;

  /// 검사용: ClearType 장의 수.
  int get lcdPageCount => _lcdPages.length;
  final _multiply = ui.Paint()
    ..blendMode = ui.BlendMode.multiply
    ..filterQuality = ui.FilterQuality.none;
  final _plus = ui.Paint()
    ..blendMode = ui.BlendMode.plus
    ..filterQuality = ui.FilterQuality.none;

  /// 지금 시각(µs). 검사는 가짜 시계를 넣는다.
  final int Function() _now;
  static int Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds;
  }

  // 배율(1/100 단위)마다 제 장들을 둔다 → 옛 배율을 버릴 때 그 장들을 통째로 버린다.
  final _pagesOf = <int, List<_Page>>{};

  /// 배율을 가로질러 편 장의 목록. 장이 늘거나 줄 때만 다시 편다 — 장면마다 층의 끝에서 열 번 넘게 도는 길이라
  /// 그때마다 `expand`로 새 훑개를 만들지 않는다.
  List<_Page>? _flat;
  List<_Page> get _pages => _flat ??= [for (final pages in _pagesOf.values) ...pages];
  static int _keyOf(double scale) => (scale * 100).round();
  // (글자, 크기, 굵기, 배율의 1/100) → 그림판의 자리
  final _glyphs = <(int, double, int, int), _Glyph>{};
  int _spent = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;
  double _scale = 1, _oldScale = 1;
  int _sharp = 0, _blurry = 0;

  @override
  int newThisFrame = 0;
  @override
  bool starved = false;
  int drawCalls = 0;

  double get scale => _scale;
  int get glyphCount => _glyphs.length;
  int get pageCount => _pagesOf.values.fold(0, (n, pages) => n + pages.length);
  int get pendingSprites => _pages.fold(0, (n, p) => n + p.n);

  /// 검사용: 아직 내보내지 않은 조각들의 자리(배치 px).
  Iterable<(double, double)> get pendingPositions sync* {
    for (final page in _pages) {
      for (int i = 0; i < page.n; i++) {
        yield (page.transforms[i * 4 + 2], page.transforms[i * 4 + 3]);
      }
    }
  }

  /// 검사용: 이번 장면에 찍은 글자마다 (펜 x · 바탕선 y — 둘 다 화면 px). 회색이든 ClearType이든 같은 셈.
  /// 장면마다 글자 수만큼 쌓이므로 assert가 켜진 때(검사 · 디버그)에만 적는다.
  final debugLastPens = <(double, double)>[];

  /// 이번 장면에 찍은 글자 가운데 지금 배율로 선명하게 준비된 것의 비율.
  double get sharpRatio => _sharp + _blurry == 0 ? 1 : _sharp / (_sharp + _blurry);
  @override
  double get spentMs => _spent / 1000;
  @override
  bool get canFade => true;

  @override
  void beginFrame() {
    // 목업 renderMock은 굽기를 앞당겨 청하려고 판 사이에 이 함수를 한 번 더 부름 — '한 장면에 한 번'을 전제로 일을 더하면 목업 판이 깨짐.
    _askWanted(); // 지난 장면에 모은 굽기를 묶음마다 한 번 — 한 장면에 한 번
    newThisFrame = 0;
    starved = false;
    drawCalls = 0;
    _sharp = _blurry = 0;
    _spent = 0;
    debugLastPens.clear();
    debugLcdBatches.clear();
    _lcdSprites = 0;
  }

  @override
  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _oldScale = _scale;
    _scale = next;
    // 지금 · 직전 · 100%의 글자만 남기고 나머지 배율의 글자와 장을 버린다 — 멎은 배율마다 글자 한 벌과 장(1024² ≈ 4MB)이 생기므로,
    // 버리지 않으면 돋보기를 만질 때마다 메모리가 늘어 앱을 끌 때까지 돌아오지 않는다.
    final keep = {_keyOf(_scale), _keyOf(_oldScale), 100};
    // ClearType 글자와 장도 같은 배율만 남긴다. 아직 청하지 않은 굽기는 옛 배율의 크기이니 버린다(새 배율에서 다시 모은다).
    _lcd.removeWhere((k, _) => !keep.contains(k.$4));
    for (final key in [for (final key in _lcdPagesOf.keys) if (!keep.contains(key)) key]) {
      for (final page in _lcdPagesOf.remove(key)!) {
        page.gone = true;
        page.covImage?.dispose();
        page.invImage?.dispose();
      }
      _lcdFlat = null;
    }
    for (final wanted in _lcdWant.values) {
      for (final keys in wanted.values) {
        _lcdAsked.removeAll(keys);
      }
    }
    _lcdWant.clear();
    final gone = [for (final key in _pagesOf.keys) if (!keep.contains(key)) key];
    if (gone.isEmpty) return;
    _flat = null;
    for (final key in gone) {
      for (final page in _pagesOf.remove(key)!) {
        page.image?.dispose();
        for (final (paragraph, _, _, _) in page.pending) {
          paragraph.dispose();
        }
      }
    }
    _glyphs.removeWhere((key, _) => !keep.contains(key.$4));
    _runs.clear(); // 버린 글자를 가리키는 글줄이 남지 않게 — 다시 짜는 것은 싸다
  }

  _Glyph? _find(int rune, TextLook look, double scale) => _glyphs[(rune, look.size, look.shapeKey, _keyOf(scale))];

  /// 지금 배율의 글자. 없으면 예산 안에서 만든다. 예산이 없으면 null.
  _Glyph? _make(int rune, TextLook look) {
    final hit = _find(rune, look, _scale);
    if (hit != null) return hit;
    // 예산을 넘으면 멈춘다. 다만 장면마다 하나는 준비한다 — 첫 글꼴 읽기처럼 하나가 예산보다 길어도 나아가게.
    if (newThisFrame >= maxNewPerFrame || (_spent > budgetMicros && newThisFrame > 0)) {
      starved = true;
      return null;
    }
    final began = _now();
    // 글자 사이는 찍을 때 더한다(그림판의 글자는 간격 없이 하나씩). 기울인 글자는 오른쪽 위가 제 폭을 넘으므로 자리를 조금 넓게 잡는다.
    final builder = ui.ParagraphBuilder(look.paragraphStyle(_scale))
      ..pushStyle(TextLook(look.size, look.weight, 0xffffffff, italic: look.italic, wght: look.wght).textStyle(0xffffffff, _scale))
      ..addText(String.fromCharCode(rune));
    final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
    final advance = paragraph.maxIntrinsicWidth / _scale;
    final width = paragraph.maxIntrinsicWidth.ceilToDouble() + 1 + (look.italic ? (look.size * _scale * .25).ceilToDouble() : 0), height = paragraph.height.ceilToDouble() + 1;
    final pages = _pagesOf.putIfAbsent(_keyOf(_scale), () => []);
    var page = pages.isEmpty ? null : pages.last;
    if (page != null && page.penX + width + 1 > page.size) {
      page.penX = 1;
      page.penY += page.rowHeight + 1;
      page.rowHeight = 0;
    }
    if (page == null || page.penY + height + 1 > page.size) {
      page = _Page(pageSize);
      pages.add(page);
      _flat = null;
    }
    final glyph = _Glyph(page, page.penX, page.penY, width, height, advance, _scale, paragraph.alphabeticBaseline);
    page.pending.add((paragraph, page.penX, page.penY, width));
    page.penX += width + 1;
    if (height > page.rowHeight) page.rowHeight = height;
    _glyphs[(rune, look.size, look.shapeKey, _keyOf(_scale))] = glyph;
    newThisFrame++;
    _spent += _now() - began;
    return glyph;
  }

  /// 새 글자를 그림판에 넣는다: 옛 그림 위에 새 글자만 덧그려 새 그림을 뜬다.
  void _commit() {
    for (final page in _pages) {
      if (page.pending.isEmpty) continue;
      final began = _now();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final old = page.image;
      if (old != null) canvas.drawImage(old, ui.Offset.zero, ui.Paint());
      for (final (paragraph, x, y, _) in page.pending) {
        canvas.drawParagraph(paragraph, ui.Offset(x, y));
        paragraph.dispose();
      }
      page.pending.clear();
      final picture = recorder.endRecording();
      page.image = picture.toImageSync(page.size, page.size);
      picture.dispose();
      old?.dispose();
      _spent += _now() - began;
    }
  }

  (int, double, int, int) _lcdKey(int rune, TextLook look) => (rune, look.size, look.shapeKey, _keyOf(_scale));

  /// 글줄의 글자가 모두 구워져 있으면 그 자리들, 아니면 null(없는 것은 굽기 묶음에 모은다 — 글꼴에 없는 글자가 있으면 늘 null).
  List<_LcdGlyph?>? _lcdRun(String text, TextLook look) {
    final out = <_LcdGlyph?>[];
    var absent = false;
    // 이 생김새의 굽기 묶음 — 새 글자가 있을 때만 한 번 찾는다(null: 굽개나 글꼴 파일이 없어 굽지 못함).
    Map<int, List<(int, double, int, int)>>? wanted;
    var looked = false;
    for (final rune in text.runes) {
      if (rune == 0x20) {
        out.add(null);
        continue;
      }
      final key = _lcdKey(rune, look);
      if (!_lcd.containsKey(key)) {
        if (!_lcdAsked.contains(key)) {
          if (!looked) {
            looked = true;
            final font = fontFileOf(look);
            if (font != null && baker != null) wanted = _lcdWant.putIfAbsent((font, look.size * _scale), () => {});
          }
          if (wanted == null) {
            _lcd[key] = null; // 굽지 못한다 — 회색
          } else {
            _lcdAsked.add(key); // 한 글줄 · 한 장면에 같은 글자가 거듭 나와도 한 번만 굽는다
            (wanted[rune] ??= []).add(key);
          }
        }
        absent = true;
        continue;
      }
      final g = _lcd[key];
      if (g == null) return null; // 그 글꼴에 없는 글자 — 이 글줄은 회색(검토 초점 3)
      out.add(identical(g, _blankLcd) ? null : g);
    }
    return absent ? null : out;
  }

  /// 지난 장면에 모은 굽기를 (글꼴 파일, 화면 크기)마다 한 번 청한다.
  void _askWanted() {
    final b = baker;
    if (_lcdWant.isEmpty || b == null) return;
    for (final MapEntry(key: (font, sizePx), value: wanted) in _lcdWant.entries) {
      final all = wanted.keys.toList();
      for (var from = 0; from < all.length; from += bakeChunk) {
        final runes = all.sublist(from, from + bakeChunk < all.length ? from + bakeChunk : all.length);
        final keys = [for (final r in runes) wanted[r]!];
        b.bake(font, sizePx, runes).then((baked) {
          for (var i = 0; i < runes.length; i++) {
            final got = i < baked.length ? baked[i] : null;
            final blank = got != null && got.ok && got.width == 0;
            // 글꼴에 없는 글자 · 장보다 큰 글자는 회색으로(null).
            final g = got != null && got.ok && got.width > 0 && got.width + 2 <= pageSize && got.height + 2 <= pageSize ? got : null;
            _LcdGlyph? placed;
            for (final k in keys[i]) {
              _lcdAsked.remove(k);
              if (k.$4 != _keyOf(_scale)) continue; // 그사이 배율이 바뀌었다 — 버린다
              if (g != null) placed ??= _place(g); // 생김새가 달라도 같은 글꼴 파일 · 크기면 장에 한 번만 넣는다
              _lcd[k] = blank ? _blankLcd : placed;
            }
          }
          _buildLcdImages();
        }, onError: (Object _) {
          for (final ks in keys) {
            for (final k in ks) {
              _lcdAsked.remove(k);
              _lcd[k] = null; // 굽지 못한 글자는 회색으로
            }
          }
        });
      }
    }
    _lcdWant.clear();
  }

  _LcdGlyph _place(LcdGlyph g) {
    final pages = _lcdPagesOf.putIfAbsent(_keyOf(_scale), () => []);
    var page = pages.isEmpty ? null : pages.last;
    if (page != null && page.penX + g.width + 1 > page.size) {
      page.penX = 1;
      page.penY += page.rowHeight + 1;
      page.rowHeight = 0;
    }
    if (page == null || page.penY + g.height + 1 > page.size) {
      page = _LcdPage(pageSize);
      pages.add(page);
      _lcdFlat = null;
    }
    final u = page.penX.toInt(), v = page.penY.toInt();
    for (var y = 0; y < g.height; y++) {
      for (var x = 0; x < g.width; x++) {
        final src = (y * g.width + x) * 3, dst = ((v + y) * page.size + (u + x)) * 4;
        for (var ch = 0; ch < 3; ch++) {
          final c = g.cov[src + (bgr ? 2 - ch : ch)];
          page.cov[dst + ch] = c;
          page.inv[dst + ch] = 255 - c;
        }
      }
    }
    page.penX += g.width + 1;
    if (g.height > page.rowHeight) page.rowHeight = g.height.toDouble();
    page.gen++;
    return _LcdGlyph(page, page.gen, u, v, g.left, g.top, g.width, g.height);
  }

  /// 새 글자가 든 ClearType 장의 두 그림을 다시 뜬다. 두 그림이 다 떠지면 함께 바꾸고 그 세대를 보인다.
  /// 뜨는 사이에 글자가 더 들어오면 다 뜬 뒤 한 번 더 뜬다 — 그러지 않으면 그 글자는 영영 그림에 들지 못한다.
  void _buildLcdImages() {
    for (final page in _lcdPages) {
      if (page.building || page.gen == page.shownGen) continue;
      final gen = page.gen;
      page.building = true;
      ui.Image? cov, inv;
      void done() {
        if (cov == null || inv == null) return;
        page.building = false;
        if (page.gone) {
          cov!.dispose();
          inv!.dispose();
          return;
        }
        page.covImage?.dispose();
        page.invImage?.dispose();
        page.covImage = cov;
        page.invImage = inv;
        page.shownGen = gen;
        if (page.gen > page.shownGen) _buildLcdImages();
      }

      // 바이트를 떠 넘긴다 — 그림을 뜨는 동안 _place가 같은 장에 다음 글자를 쓴다.
      ui.decodeImageFromPixels(Uint8List.fromList(page.cov), page.size, page.size, ui.PixelFormat.rgba8888, (img) {
        cov = img;
        done();
      });
      ui.decodeImageFromPixels(Uint8List.fromList(page.inv), page.size, page.size, ui.PixelFormat.rgba8888, (img) {
        inv = img;
        done();
      });
    }
  }

  /// ClearType 장 가운데 아직 그림을 뜨는 중이거나 그림에 들지 않은 글자가 남은 장이 있는가.
  bool get _lcdBuilding => _lcdPages.any((p) => p.building || p.gen > p.shownGen);

  /// 글줄 하나를 이루는 글자 조각들을 기억해 둔다 — 장면마다 글자를 다시 찾지 않는다.
  final _runs = <(String, double, int, double), _Run>{};

  /// 글줄을 이루는 글자가 모두(지금 배율이든 옛 배율이든) 있어야 돌려준다 — 반쯤 그린 이름을 보이지 않는다.
  _Run? _runOf(String text, TextLook look) {
    final key = (text, look.size, look.shapeKey, look.spacing);
    final known = _runs[key];
    if (known != null && known.sharpAt == _scale) return known;
    final glyphs = <_Glyph>[];
    double width = 0;
    bool complete = true, sharp = true;
    for (final rune in text.runes) {
      final g = _make(rune, look) ?? _find(rune, look, _oldScale) ?? _find(rune, look, 1);
      if (g == null) {
        complete = false;
        continue; // 나머지 글자도 예산이 남으면 마저 준비한다
      }
      if (g.scale != _scale) sharp = false;
      glyphs.add(rune == 0x20 ? _Glyph(g.page, 0, 0, 0, 0, g.advance, g.scale, g.baseline) : g);
      width += g.advance + look.spacing;
    }
    if (glyphs.isNotEmpty) width -= look.spacing; // 마지막 글자 뒤에는 간격이 없다
    if (!complete) return known;
    final run = _Run(glyphs, width, sharp ? _scale : -1);
    if (_runs.length >= 8192) _runs.remove(_runs.keys.first);
    _runs[key] = run;
    return run;
  }

  @override
  double? widthOf(String text, TextLook look) => _runOf(text, look)?.width;

  @override
  bool paint(ui.Canvas canvas, String text, TextLook look, double x, double y, {double alpha = 1}) {
    final run = _runOf(text, look);
    if (run == null) return false;
    if (run.glyphs.isEmpty) return true;
    SceneText.probe?.add(this, canvas, text, look, x, y, run.width, alpha);
    final argb = alpha >= 1 ? look.color : ((look.color >>> 24) * alpha).round() << 24 | (look.color & 0xffffff);
    // 흐려지지 않게 글자 하나하나를 화면 px(배치 px × 배율)에 맞춰 찍는다.
    final s = _scale;
    // 바탕선을 화면 화소 줄에 맞춘다(크롬처럼 — 시험에서 옛 셈은 글줄의 절반이 1px 아래였다). 첫 글자의 바탕선으로 글줄 전체를 맞춘다.
    final firstInk = run.glyphs.firstWhere((g) => g.width > 0, orElse: () => run.glyphs.first);
    final b = firstInk.baseline / firstInk.scale;
    final baseDev = ((y + b) * s).roundToDouble();
    // 그림판의 글자는 칸 위에서 바탕선까지를 정수 화소로 반올림해 그려져 있다(Skia가 가로쓰기의 바탕선을 화소 줄에 붙인다 — 9px 프리텐다드의 8.6px은 9px 줄에).
    // 그 반올림한 줄을 baseDev에 두어야 글자 칸의 윗변도 화면 화소에 맞고(흐림 없음) 잉크의 바탕선이 ClearType과 같은 줄에 온다.
    final top = baseDev / s - firstInk.baseline.roundToDouble() / firstInk.scale;
    // ClearType은 불투명한 글자만(옅어짐 · 반투명 색은 회색 — 검토 초점 4). 글줄의 글자가 하나라도 덜 준비됐으면 글줄 전체를 회색으로.
    final opaque = alpha >= 1 && (look.color >>> 24) == 0xff;
    final lcd = lcdAllowed && opaque ? _lcdRun(text, look) : null;
    final lcdReady = lcd != null &&
        lcd.length == run.glyphs.length && // lcd는 text.runes의 차례 — 덜 준비된 글줄(run.glyphs가 준 것)이면 차례가 어긋나니 회색
        lcd.every((g) => g == null || g.gen <= g.page.shownGen); // 지금 그림에 든 글자만(다음 세대를 뜨는 중이어도 그대로)
    var penX = x;
    var k = 0, inked = 0;
    for (final g in run.glyphs) {
      if (g.width > 0) {
        final penDev = (penX * s).roundToDouble();
        assert(() {
          debugLastPens.add((penDev, baseDev));
          return true;
        }());
        final lg = lcdReady ? lcd[k] : null;
        if (lg != null) {
          // 글줄 안 차례의 홀짝 — 이웃 글자의 조각은 서로 다른 묶음에 들게(flush의 나누기가 먼저 이 자리를 본다).
          lg.page.add(lg, (penDev + lg.left) / s, (baseDev + lg.top) / s, s, argb, penDev.toInt() + lg.left, baseDev.toInt() + lg.top, inked.isOdd);
          inked++;
          _lcdSprites++;
          _sharp++;
        } else {
          g.page.add(g, penDev / s, top, argb);
          if (g.scale == _scale) {
            _sharp++;
          } else {
            _blurry++;
          }
        }
      }
      k++;
      penX += g.advance + look.spacing;
    }
    if (run.sharpAt != _scale) starved = true; // 새 배율의 글자를 마저 준비하도록 다음 장면을 청한다
    // 다 구워지고 그림을 다 뜨면 한 장 더 그리게(그 사이의 장면은 회색).
    if (lcdAllowed && opaque && !lcdReady && (lcdPending > 0 || _lcdBuilding)) starved = true;
    return true;
  }

  @override
  void flush(ui.Canvas canvas) {
    _commit();
    for (final page in _pages) {
      if (page.n == 0 || page.image == null) continue;
      canvas.drawRawAtlas(page.image!, Float32List.sublistView(page.transforms, 0, page.n * 4), Float32List.sublistView(page.rects, 0, page.n * 4),
          Int32List.sublistView(page.colors, 0, page.n), ui.BlendMode.modulate, null, _paint);
      page.n = 0;
      drawCalls++;
    }
    // ClearType: 곱하기(바탕 × (1 − 덮임)) → 더하기(글자 색 × 덮임). 바탕이 불투명해야 맞다 — 반투명 층 · 움직임은 lcdAllowed가 거짓이라 오지 않는다.
    // 조각을 화면 자리가 서로 겹치지 않는 묶음으로 나눠 묶음마다 찍는다(곱하기를 모두 · 그다음 더하기를 모두 — CPU에서는 나누기 전과 같은 값):
    // Impeller는 고급 섞기(곱하기)를 drawRawAtlas 한 번의 조각들을 한 층에 먼저 겹쳐 그린 뒤 섞어서, 겹친 자리에서 뒤 조각의 흰 여백이
    // 앞 글자의 덮임을 지운다(실제 앱에서 '반포'가 '빈포'로 — 과제 6 보고 걱정 1). 묶음끼리는 차례로 섞이니 겹쳐도 맞다.
    for (final page in _lcdPages) {
      if (page.n == 0 || page.covImage == null || page.invImage == null) {
        page.n = 0;
        continue;
      }
      final batches = _splitLcd(page);
      for (final pass in const [0, 1]) {
        for (var b = 0; b < batches; b++) {
          final from = _lcdStart[b], to = _lcdStart[b + 1];
          if (from == to) continue;
          final t = Float32List.sublistView(_lcdT, from * 4, to * 4), r = Float32List.sublistView(_lcdR, from * 4, to * 4);
          if (pass == 0) {
            canvas.drawRawAtlas(page.invImage!, t, r, null, null, null, _multiply);
          } else {
            canvas.drawRawAtlas(page.covImage!, t, r, Int32List.sublistView(_lcdC, from, to), ui.BlendMode.modulate, null, _plus);
          }
          drawCalls++;
        }
      }
      page.n = 0;
    }
  }

  /// 검사용: 이번 장면에 ClearType으로 찍은 묶음마다 조각들의 화면 네모(왼 · 위 · 오 · 아래). assert가 켜진 때만 적는다.
  final debugLcdBatches = <List<(int, int, int, int)>>[];

  // 나누기의 일감 — 장면마다 다시 만들지 않는다.
  final _cellHead = <int, int>{};
  Int32List _nodeSprite = Int32List(1024), _nodeNext = Int32List(1024), _batchOf = Int32List(256);
  final _lcdStart = <int>[];
  Float32List _lcdT = Float32List(4 * 256), _lcdR = Float32List(4 * 256);
  Int32List _lcdC = Int32List(256);

  /// 장의 조각을 묶음으로 나눈다: 글줄 안 차례의 홀짝이 먼저(짝 → 묶음 0 · 홀 → 1), 그 묶음의 조각과 화면 자리가 겹치면 다른 묶음으로
  /// (홀짝의 다른 쪽 → 2 → 3 …, 겹치지 않을 때까지 늘린다 — 다른 글줄끼리 · 아주 좁은 글자). 겹침은 32px 칸으로 나눈 이웃만 본다.
  /// 묶음 차례로 늘어놓은 조각을 [_lcdT] · [_lcdR] · [_lcdC]에, 묶음 b의 범위를 [_lcdStart]의 b ~ b + 1에 둔다. 묶음 수를 돌려준다.
  int _splitLcd(_LcdPage page) {
    final n = page.n, box = page.boxes;
    if (_batchOf.length < n) _batchOf = Int32List(n * 2);
    _cellHead.clear();
    var nodes = 0, batches = 0;
    int key(int b, int cx, int cy) => (b << 42) | ((cy & 0x1fffff) << 21) | (cx & 0x1fffff);
    for (var i = 0; i < n; i++) {
      final x0 = box[i * 4], y0 = box[i * 4 + 1], x1 = box[i * 4 + 2], y1 = box[i * 4 + 3];
      final cx0 = x0 >> 5, cx1 = (x1 - 1) >> 5, cy0 = y0 >> 5, cy1 = (y1 - 1) >> 5;
      final first = page.odd[i];
      var b = first;
      for (var tries = 0;; tries++) {
        b = tries == 0 ? first : (tries == 1 ? 1 - first : tries);
        var clash = false;
        for (var cy = cy0; cy <= cy1 && !clash; cy++) {
          for (var cx = cx0; cx <= cx1 && !clash; cx++) {
            for (var node = _cellHead[key(b, cx, cy)] ?? -1; node >= 0; node = _nodeNext[node]) {
              final j = _nodeSprite[node] * 4;
              if (x0 < box[j + 2] && box[j] < x1 && y0 < box[j + 3] && box[j + 1] < y1) {
                clash = true;
                break;
              }
            }
          }
        }
        if (!clash) break;
      }
      _batchOf[i] = b;
      if (b + 1 > batches) batches = b + 1;
      for (var cy = cy0; cy <= cy1; cy++) {
        for (var cx = cx0; cx <= cx1; cx++) {
          if (nodes == _nodeSprite.length) {
            _nodeSprite = Int32List(nodes * 2)..setRange(0, nodes, _nodeSprite);
            _nodeNext = Int32List(nodes * 2)..setRange(0, nodes, _nodeNext);
          }
          final k = key(b, cx, cy);
          _nodeSprite[nodes] = i;
          _nodeNext[nodes] = _cellHead[k] ?? -1;
          _cellHead[k] = nodes++;
        }
      }
    }
    // 묶음 차례로 늘어놓기(셈 차례 그대로 — 같은 묶음 안의 차례는 바꾸지 않는다)
    _lcdStart
      ..clear()
      ..addAll(List.filled(batches + 1, 0));
    for (var i = 0; i < n; i++) {
      _lcdStart[_batchOf[i] + 1]++;
    }
    for (var b = 0; b < batches; b++) {
      _lcdStart[b + 1] += _lcdStart[b];
    }
    if (_lcdC.length < n) {
      _lcdT = Float32List(n * 8);
      _lcdR = Float32List(n * 8);
      _lcdC = Int32List(n * 2);
    }
    final fill = List.of(_lcdStart);
    for (var i = 0; i < n; i++) {
      final at = fill[_batchOf[i]]++;
      _lcdT.setRange(at * 4, at * 4 + 4, page.transforms, i * 4);
      _lcdR.setRange(at * 4, at * 4 + 4, page.rects, i * 4);
      _lcdC[at] = page.colors[i];
    }
    assert(() {
      for (var b = 0; b < batches; b++) {
        debugLcdBatches.add([
          for (var i = 0; i < n; i++)
            if (_batchOf[i] == b) (box[i * 4], box[i * 4 + 1], box[i * 4 + 2], box[i * 4 + 3]),
        ]);
      }
      return true;
    }());
    return batches;
  }

  @override
  void dispose() {
    for (final page in _pages) {
      page.image?.dispose();
      for (final (paragraph, _, _, _) in page.pending) {
        paragraph.dispose();
      }
    }
    _pagesOf.clear();
    _flat = null;
    _glyphs.clear();
    _runs.clear();
    for (final page in _lcdPages) {
      page.gone = true; // 뜨던 그림이 닫은 뒤에 와도 붙이지 않고 놓는다
      page.covImage?.dispose();
      page.invImage?.dispose();
    }
    _lcdPagesOf.clear();
    _lcdFlat = null;
    _lcd.clear();
    _lcdAsked.clear();
    _lcdWant.clear();
  }
}

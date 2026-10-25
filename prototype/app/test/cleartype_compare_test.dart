import 'load_app_fonts.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/scene/cleartype.dart';
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:flutter_test/flutter_test.dart';

// 기준 낱말 8배 견줌(계획 한 벌 P2 과제 6 · 설계 6절 P2): 크롬 1배 조각(test/fixtures/cleartype — scripts/cleartype-fixtures.mjs가 만듦)과
// 같은 자리 · 같은 바탕색에 회색 판과 ClearType 판(진짜 자료 처리부의 DirectWrite)을 찍어 견준다.
//  · 글줄을 위아래 · 좌우 −1~1px로 밀어 크롬과의 화소 차 평균이 가장 작은 자리가 (0, 0)이어야 한다(시험 1의 '밀기').
//  · 견줌 그림은 ../results/cleartype/8배-<낱말>.png(줄마다 크롬 · 회색 · ClearType, 8배) — 또렷함 · 색 테두리는 그림으로 판단한다.
// Windows · 자료 처리부 DLL이 있을 때만 돈다.

class _Word {
  _Word(Map j)
      : n = j['n'] as int,
        text = j['text'] as String,
        size = (j['size'] as num).toDouble(),
        weight = j['weight'] as int,
        x = (j['x'] as num).toDouble(),
        baseline = (j['baseline'] as num).toDouble(),
        color = 0xff000000 | int.parse((j['color'] as String).substring(1), radix: 16),
        bg = 0xff000000 | int.parse((j['bg'] as String).substring(1), radix: 16),
        crop = [for (final v in j['crop'] as List) v as int],
        chars = [for (final v in j['chars'] as List) (v as num).toDouble()],
        mask = (j['mask'] as List?)?.cast<String>();
  final int n, weight, color, bg;
  final String text;
  final double size, x, baseline;
  final List<int> crop;
  final List<double> chars;

  /// 글자를 숨긴 크롬 조각이 바탕색인 화소만 '1'(띠의 선 같은 것은 세지 않는다). 없으면 모두 셈.
  final List<String>? mask;
  int get w => crop[2];
  int get h => crop[3];
  int get ink => text.runes.where((r) => r != 0x20).length;
  TextLook get look => TextLook(size, ui.FontWeight.values.firstWhere((f) => f.value == weight), color);
  bool counts(int x, int y) => mask == null || mask![y][x] == '1';
}

class _Shot {
  _Shot(this.image, this.rgba, this.pens, this.lcd);
  final ui.Image image;
  final Uint8List rgba;
  final List<(double, double)> pens;
  final int lcd;
}

Future<(ui.Image, Uint8List)> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return (image, data!.buffer.asUint8List());
}

/// 앱 그림판과 같은 셈의 바탕선(글자 칸 위에서): 첫 글자 하나의 글줄.
double _baselineOf(TextLook look, String text) {
  final first = String.fromCharCode(text.runes.firstWhere((r) => r != 0x20));
  final p = (ui.ParagraphBuilder(look.paragraphStyle(1))
        ..pushStyle(TextLook(look.size, look.weight, 0xffffffff).textStyle(0xffffffff, 1))
        ..addText(first))
      .build()
    ..layout(const ui.ParagraphConstraints(width: double.infinity));
  final b = p.alphabeticBaseline;
  p.dispose();
  return b;
}

/// 조각 크기의 바탕(바탕색)에 글줄을 크롬과 같은 자리(시작 x · 바탕선 y)에 찍는다. ClearType이면 모든 글자가 ClearType으로 찍힐 때까지 장면을 되풀이한다.
Future<_Shot> _render(AtlasText t, _Word w, {required bool lcd}) async {
  final look = w.look;
  final top = w.baseline - _baselineOf(look, w.text);
  ui.Image? shot;
  var pens = <(double, double)>[];
  var sprites = 0;
  for (var i = 0; i < 300; i++) {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec)
      ..drawRect(ui.Rect.fromLTWH(0, 0, w.w.toDouble(), w.h.toDouble()), ui.Paint()..color = ui.Color(w.bg))
      ..translate(-w.crop[0].toDouble(), -w.crop[1].toDouble());
    t.beginFrame();
    final painted = t.paint(c, w.text, look, w.x, top);
    t.flush(c);
    pens = List.of(t.debugLastPens);
    sprites = t.lcdSprites;
    final picture = rec.endRecording();
    shot?.dispose();
    shot = picture.toImageSync(w.w, w.h);
    picture.dispose();
    if (painted && pens.length == w.ink && (!lcd || sprites == w.ink) && i >= 2) break;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  final data = await shot!.toByteData(format: ui.ImageByteFormat.rawRgba);
  return _Shot(shot, data!.buffer.asUint8List(), pens, sprites);
}

/// 우리 그림을 (dx, dy)만큼 민 것과 크롬의 화소 차 평균(빨 · 초 · 파, 0~255). 가장자리 1px은 밀면 비므로 세지 않는다.
double _diff(_Word w, Uint8List chrome, Uint8List ours, int dx, int dy) {
  var sum = 0, count = 0;
  for (var y = 1; y < w.h - 1; y++) {
    for (var x = 1; x < w.w - 1; x++) {
      if (!w.counts(x, y)) continue;
      final a = (y * w.w + x) * 4, b = ((y - dy) * w.w + (x - dx)) * 4;
      for (var ch = 0; ch < 3; ch++) {
        sum += (chrome[a + ch] - ours[b + ch]).abs();
      }
      count += 3;
    }
  }
  return sum / count;
}

/// 글자 자리(크롬이나 우리 그림이 바탕색에서 8 넘게 벗어난 화소)만의 화소 차 평균 — 설계 1-4의 수와 견주는 값.
double _inkDiff(_Word w, Uint8List chrome, Uint8List ours) {
  final bg = [(w.bg >> 16) & 255, (w.bg >> 8) & 255, w.bg & 255];
  var sum = 0, count = 0;
  for (var i = 0; i < w.w * w.h; i++) {
    if (!w.counts(i % w.w, i ~/ w.w)) continue;
    var off = false;
    for (var ch = 0; ch < 3; ch++) {
      if ((chrome[i * 4 + ch] - bg[ch]).abs() > 8 || (ours[i * 4 + ch] - bg[ch]).abs() > 8) off = true;
    }
    if (!off) continue;
    for (var ch = 0; ch < 3; ch++) {
      sum += (chrome[i * 4 + ch] - ours[i * 4 + ch]).abs();
    }
    count += 3;
  }
  return count == 0 ? 0 : sum / count;
}

/// 가장 잘 맞는 밀기. 같은 값이면 (0, 0)을 앞에 둔다.
((int, int), double, double) _bestShift(_Word w, Uint8List chrome, Uint8List ours) {
  final zero = _diff(w, chrome, ours, 0, 0);
  var best = (0, 0);
  var min = zero;
  for (final dy in const [-1, 0, 1]) {
    for (final dx in const [-1, 0, 1]) {
      final d = _diff(w, chrome, ours, dx, dy);
      if (d < min - 1e-9) {
        min = d;
        best = (dx, dy);
      }
    }
  }
  return (best, zero, min);
}

/// 8배 견줌 그림: 낱말의 줄마다 크롬 · 회색 · ClearType.
Future<void> _writeZoom(String path, List<(_Word, ui.Image, ui.Image, ui.Image)> rows) async {
  const s = 8.0, gap = 16.0;
  final width = rows.map((r) => r.$1.w).reduce((a, b) => a > b ? a : b) * s * 3 + gap * 4;
  final height = rows.fold<double>(gap, (h, r) => h + r.$1.h * s + gap);
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec)..drawRect(ui.Rect.fromLTWH(0, 0, width, height), ui.Paint()..color = const ui.Color(0xff8a8a8a));
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  var y = gap;
  final colW = (width - gap * 4) / 3;
  for (final (w, chrome, gray, lcd) in rows) {
    var x = gap;
    for (final img in [chrome, gray, lcd]) {
      c.drawImageRect(img, ui.Rect.fromLTWH(0, 0, w.w.toDouble(), w.h.toDouble()), ui.Rect.fromLTWH(x, y, w.w * s, w.h * s), paint);
      x += colW + gap;
    }
    y += w.h * s + gap;
  }
  final picture = rec.endRecording();
  final image = picture.toImageSync(width.ceil(), height.ceil());
  picture.dispose();
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  final dll = File('../engine/target/release/archive_engine.dll');
  final skip = !(Platform.isWindows && dll.existsSync()); // Windows · 자료 처리부 DLL이 있어야 한다

  testWidgets('기준 낱말: 회색 · ClearType 모두 크롬과 글줄 자리가 같다(밀기 0) · 8배 견줌 그림', (tester) async {
    await tester.runAsync(() async {
      await loadAppFonts();
      final baker = ClearTypeBaker.open(dll.absolute.path);
      expect(baker, isNotNull, reason: 'archive_glyphs가 있는 자료 처리부');
      AtlasText atlas() => AtlasText(baker: baker, fontFileOf: (l) => sceneFontFile(l, root: 'assets/fonts'))
        ..budgetMicros = 1 << 40
        ..maxNewPerFrame = 1000;
      final gray = atlas(), lcd = atlas()..lcdAllowed = true;
      final words = [for (final j in (jsonDecode(File('test/fixtures/cleartype/words.json').readAsStringSync()) as Map)['words'] as List) _Word(j as Map)];
      final out = Directory('../results/cleartype')..createSync(recursive: true);
      final groups = <String, List<(_Word, ui.Image, ui.Image, ui.Image)>>{};
      final report = StringBuffer('번호 낱말 크기 | 회색: 0,0 차 · 가장 잘 맞는 밀기 · 글자 자리 차 | ClearType: 0,0 차 · 밀기 · 글자 자리 차 | 펜 − 크롬 글자 x 최대\n');
      final wrong = <String>[];
      for (final w in words) {
        final (chromeImage, chrome) = await _decode(File('test/fixtures/cleartype/chrome-${w.n}.png').readAsBytesSync());
        expect((chromeImage.width, chromeImage.height), (w.w, w.h), reason: '${w.n} 조각 크기');
        final g = await _render(gray, w, lcd: false);
        final l = await _render(lcd, w, lcd: true);
        expect(g.pens.length, w.ink, reason: '${w.n} ${w.text}: 회색 글자가 모두 찍혔다');
        expect(l.lcd, w.ink, reason: '${w.n} ${w.text}: 모든 글자가 ClearType으로 찍혔다');
        expect(l.pens, g.pens, reason: '${w.n} ${w.text}: 회색 · ClearType의 펜 · 바탕선이 같다');
        final (gBest, g0, _) = _bestShift(w, chrome, g.rgba);
        final (lBest, l0, _) = _bestShift(w, chrome, l.rgba);
        final inkX = [for (var i = 0; i < w.chars.length; i++) if (w.text.runes.elementAt(i) != 0x20) w.chars[i]];
        var penOff = 0.0;
        for (var i = 0; i < g.pens.length && i < inkX.length; i++) {
          final d = g.pens[i].$1 - inkX[i];
          if (d.abs() > penOff.abs()) penOff = d;
        }
        report.writeln('${w.n} ${w.text} ${w.size}px | ${g0.toStringAsFixed(2)} · $gBest · ${_inkDiff(w, chrome, g.rgba).toStringAsFixed(1)} '
            '| ${l0.toStringAsFixed(2)} · $lBest · ${_inkDiff(w, chrome, l.rgba).toStringAsFixed(1)} | ${penOff.toStringAsFixed(2)}');
        if (gBest != (0, 0)) wrong.add('${w.n} ${w.text} 회색 $gBest');
        if (lBest != (0, 0)) wrong.add('${w.n} ${w.text} ClearType $lBest');
        (groups[w.text] ??= []).add((w, chromeImage, g.image, l.image));
      }
      for (final MapEntry(key: text, value: rows) in groups.entries) {
        await _writeZoom('${out.path}/8배-$text.png', rows);
        for (final (_, a, b, c) in rows) {
          a.dispose();
          b.dispose();
          c.dispose();
        }
      }
      File('${out.path}/견줌.txt').writeAsStringSync(report.toString());
      printOnFailure(report.toString()); // 앱 전체 검사의 출력은 조용히 — 표는 견줌.txt에 늘 남는다
      expect(wrong, isEmpty, reason: '가장 잘 맞는 밀기가 (0, 0)이 아닌 글줄');
      gray.dispose();
      lcd.dispose();
    });
  }, skip: skip);
}

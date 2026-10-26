import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/mock/render.dart';
import 'package:archive_prototype/mock/svg_lite.dart';
import 'package:flutter_test/flutter_test.dart';

// 옮긴 틀로 기준 방향을 끝까지 그려 본다 — svg_lite가 모르는 장치를 쓰면 여기서 실패한다.
// 그림은 ../results/mock/(git이 무시함)에 남긴다: 겹침 · 글자 자리는 그림을 열어 눈으로 보고, 여기서는 빈 화면이 아닌지만 본다.

/// 흰색이 아닌 화소의 몫.
Future<double> inked(ui.Image img) async {
  final p = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  var n = 0;
  for (var i = 0; i < p.length; i += 4) {
    if (p[i] != 255 || p[i + 1] != 255 || p[i + 2] != 255) n++;
  }
  return n / (p.length / 4);
}

Future<void> save(ui.Image img, String name) async {
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  final out = Directory('../results/mock')..createSync(recursive: true);
  File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  setUpAll(() => loadMockFonts('assets/fonts'));

  test('기준 방향 한 화면을 그린다(base.png)', () async {
    final img = await renderMock(renderScreen(BaseTheme()).p.svg);
    await save(img, 'base');
    expect([img.width, img.height], [1920, 1080]);
    expect(await inked(img), greaterThan(.05));
  });

  test('기준 방향 부품 판을 그린다(base-parts.png)', () async {
    final img = await renderMock(renderParts(BaseTheme()), width: 1800, height: 300);
    await save(img, 'base-parts');
    expect(await inked(img), greaterThan(.05));
  });
}

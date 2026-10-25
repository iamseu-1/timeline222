import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/mock/boards.dart';
import 'package:archive_prototype/mock/render.dart';
import 'package:archive_prototype/mock/svg_lite.dart';
import 'package:flutter_test/flutter_test.dart';

// 판 s4(조각 ④)의 갈래 열넷을 끝까지 그려 본다 — 갈래가 던지거나 svg_lite가 모르는 장치를 쓰면 여기서 실패한다.
// 원본과 같은지는 나무 대조(tree_dump_test.dart + prototype/scripts/mock-tree.mjs)가 본다. 여기서는 빈 화면이 아닌지만.
// 그림은 ../results/mock/s4/(git이 무시함)에 남긴다 — 겹침 · 글자 자리는 그림을 열어 눈으로 본다.

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
  final out = Directory('../results/mock/s4')..createSync(recursive: true);
  File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  setUpAll(() => loadMockFonts('assets/fonts'));

  for (final th in boards['s4']!) {
    test('${th.id} — 한 화면 · 부품 판을 그린다', () async {
      final img = await renderMock(renderScreen(th).p.svg);
      await save(img, th.id);
      expect([img.width, img.height], [1920, 1080]);
      expect(await inked(img), greaterThan(.05));
      // 판(board-s4)은 갈래마다 부품 판도 그린다 — 갈래의 object · lanes가 부품 판의 작은 장면에서도 그려지는지.
      final parts = await renderMock(renderParts(th), width: 1800, height: 300);
      await save(parts, '${th.id}-parts');
      expect(await inked(parts), greaterThan(.05));
    });
  }
}

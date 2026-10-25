import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/scene/paint/soft_shadow.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _render(void Function(ui.Canvas) draw, int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xffffffff));
  draw(canvas);
  final image = await recorder.endRecording().toImage(w, h);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  image.dispose();
  return bytes;
}

void main() {
  test('부드러운 그늘: 상자 밑으로 번지고 멀어질수록 옅어지며, 제 상자 안은 비운다', () async {
    final shadow = SoftShadow(16);
    const w = 300, h = 200;
    final px = await _render((canvas) {
      // 띠 [50,20]~[250,100] · css `0 22px 32px -18px rgba(45,38,26,.66)`
      shadow.paint(
        canvas, const ui.Rect.fromLTRB(50 + 18, 20 + 18 + 22, 250 - 18, 100 - 18 + 22), 0xa82d261a,
        clip: const ui.Rect.fromLTRB(0, 20, 300, 200), hole: const ui.Rect.fromLTRB(50, 20, 250, 100),
      );
    }, w, h);
    int red(int x, int y) => px[(y * w + x) * 4];
    expect(red(150, 60), 255, reason: '제 상자 안에는 그리지 않는다');
    final near = red(150, 102), mid = red(150, 118), far = red(150, 160);
    expect(near, lessThan(225), reason: '아랫변 바로 밑이 가장 짙다');
    expect(mid, greaterThan(near));
    expect(far, greaterThan(250), reason: '멀어지면 사라진다');
    expect(red(40, 110), greaterThan(red(100, 110)), reason: '옆으로도 부드럽게 옅어진다(네모나게 끊기지 않는다)');
  });
}

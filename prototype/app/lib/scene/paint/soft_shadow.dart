import 'dart:ui' as ui;

// css의 box-shadow(가우스 번짐)를 그대로 옮긴 부드러운 그늘. 번진 네모를 한 번만 그림으로 떠 두고 아홉 조각으로 늘려 찍는다 —
// 그늘마다 번짐을 다시 셈하지 않는다(번짐은 값이 크다). 고른 띠 · 손을 올린 띠처럼 한 장면에 몇 개뿐인 것에만 쓴다.
class SoftShadow {
  SoftShadow(this.sigma);

  /// css의 blur-radius는 가우스 표준편차의 두 배다(32px → σ 16).
  final double sigma;
  ui.Image? _image;
  double _scale = 0;

  /// 번짐이 닿는 거리(σ의 세 배면 짙기가 0.3% 아래다).
  double get reach => sigma * 3;

  static const _core = 4.0; // 가운데의 고른 부분(늘어나는 조각)

  void _ensure(double scale) {
    if (_image != null && _scale == scale) return;
    _image?.dispose();
    _scale = scale;
    // 번진 네모의 가운데가 온전히 짙으려면 네모가 번짐보다 넉넉히 커야 한다: 바깥으로 reach · 안쪽으로 reach를 두고 그 사이의 고른 부분만 늘린다.
    final side = (reach * 4 + _core) * scale;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    canvas.drawRect(
      ui.Rect.fromLTWH(reach, reach, reach * 2 + _core, reach * 2 + _core),
      ui.Paint()
        ..color = const ui.Color(0xffffffff)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma),
    );
    final picture = recorder.endRecording();
    _image = picture.toImageSync(side.ceil(), side.ceil());
    picture.dispose();
  }

  /// [box]는 그늘 상자(css의 offset · spread를 먹인 뒤의 네모), [argb]는 그늘의 색과 짙기. [clip]을 주면 그 안에만 그린다.
  /// [hole]을 주면 그 네모 안은 비운다(css의 그늘은 제 상자 안에는 그려지지 않는다 — 반투명한 띠에 그늘이 비치지 않게).
  void paint(ui.Canvas canvas, ui.Rect box, int argb, {double scale = 1, ui.Rect? clip, ui.Rect? hole}) {
    if (box.width <= 0 || box.height <= 0) return;
    _ensure(scale <= 0 ? 1 : scale);
    final image = _image!;
    final edge = reach * 2 * _scale;
    final center = ui.Rect.fromLTWH(edge, edge, _core * _scale, _core * _scale);
    // 상자가 번짐보다 작으면 조각이 겹친다 — 그만큼 작은 그늘은 그리지 않는다(css에서도 거의 보이지 않는다).
    if (box.width < 1 || box.height < 1) return;
    canvas.save();
    if (clip != null) canvas.clipRect(clip);
    if (hole != null) canvas.clipRect(hole, clipOp: ui.ClipOp.difference);
    canvas.drawImageNine(
      image,
      center,
      box.inflate(reach),
      ui.Paint()
        ..colorFilter = ui.ColorFilter.mode(ui.Color(argb), ui.BlendMode.srcIn)
        ..filterQuality = ui.FilterQuality.low,
    );
    canvas.restore();
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }
}

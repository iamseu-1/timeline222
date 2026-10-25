import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../motion.dart';
import '../../motion_spring.dart';
import '../aux_calendar.dart';
import '../axis_model.dart';
import '../color_mix.dart';
import '../emphasis.dart' show Emphasis, Spot;
import '../layout.dart';
import '../ruler.dart';
import '../scene.dart';
import '../text_paragraph.dart';
import 'context.dart';
import 'look.dart';
import 'paint_pick.dart';

// 맨 위 날짜 칸: 연도 눈금 · 시대 구분 · 간지(해마다 · 일진) · 보조 달력 · 연호 묶음 · 도읍 묶음.
// 줄 구성은 scene/axis_model.dart가 셈하고 여기서는 그리기만 한다. 값은 지금 연표의 css(`.tl-axis*` · `.tl-corner`
// · `.tl-tick` · `.tl-epoch` · `.tl-acell` · `.tl-atick` · `.tl-gbar` · `.tl-group-btn` · `.tl-spot-brk` · `.tl-calt`)와
// 기준 덤프의 숫자 그대로다.
//
// 그리기는 모두 묶음에 모은다: 네모 · 선은 `c.quads`, 둥근 모서리와 테두리 조각은 이 층의 그림판([AxisSprites]),
// 글자는 `c.later`. 칸마다 drawRRect를 부르지 않는다(설계 4.5절).

/// 한 해의 분(365.25일) — 보조 달력의 문턱을 재는 데 쓴다(scene/ruler.dart의 같은 값).
const _yearMinutes = 525960.0;

/// 문턱 둘의 되돌아오는 폭 — 한 번 켜지면 문턱의 92%까지 버틴다(지금 연표의 `_past`).
const _thresholdGap = .08;

/// 보조 달력의 날 눈금을 한 화면에 몇 칸까지 만드는가(지금 연표와 같은 안전장치).
const _maxCalDays = 500;

/// 날짜 칸의 색과 글꼴 — css에서 옮긴 값.
abstract final class AxisLook {
  /// 줄 사이 구분선 · 모서리 칸 오른쪽 선(목업 서고 — 먹 8)과 날짜 칸 아래의 선(먹 20) — 리메이크 2부.
  static const rowLine = 0xffebebeb, edge = 0xffebebeb, bottom = 0xffcccccc;

  /// 목업 날짜 칸(서고 dateHeader — 리메이크 2부): 연도 11 굵게 · 먹 80(눈금 오른쪽 4 · 가운데 12.5) · 모서리 글 10(먹 60 · 칸 오른쪽 12 앞) ·
  /// 시대 = 흰 이름 종이(높이 15 · 왼쪽 모따기 3 · 테 먹 40 · 글 9.5 굵게 먹 80 · 왼쪽 6).
  static const mockTick = TextLook(11, ui.FontWeight.w700, 0xff333333), mockSpan = TextLook(10, ui.FontWeight.w400, 0xff999999);
  static const mockCorner = TextLook(10, ui.FontWeight.w700, 0xff999999), mockEpoch = TextLook(9.5, ui.FontWeight.w700, 0xff333333);
  static const mockTickX = 4.0, mockMid = 12.5, mockRight = 12.0, epochTag = 15.0, epochCham = 3, epochText = 6.0, epochEdge = 0xff999999;

  /// 모서리 칸의 글(10.5px 500) · 시대 줄의 모서리(600) · 묶음 단추의 이름과 표시.
  static const corner = TextLook(10.5, ui.FontWeight.w500, Look.muted, spacing: -.14);
  static const cornerBold = TextLook(10.5, ui.FontWeight.w600, Look.muted, spacing: -.14, wght: 600);

  /// 해보다 작은 눈금일 때 모서리의 굵은 자리 글(`.tl-corner b`)과 그 뒤의 작은 글(`.tl-corner small`).
  static const cornerStrong = TextLook(11, ui.FontWeight.w600, Look.ink, spacing: -.14, wght: 650);
  static const cornerSmall = TextLook(10, ui.FontWeight.w500, Look.muted, spacing: -.14);
  static const groupName = TextLook(11, ui.FontWeight.w600, Look.ink, spacing: -.14, wght: 650);
  static const groupMark = TextLook(10, ui.FontWeight.w500, Look.accent, spacing: -.14);

  /// 연도 눈금(11px 500 · 자간 .22px)과 윗단위가 바뀌는 눈금.
  static const tick = TextLook(11, ui.FontWeight.w500, Look.muted, spacing: .22);
  static const tickMajor = TextLook(11, ui.FontWeight.w600, Look.ink, spacing: .22, wght: 650);

  /// 간지 눈금(`.tl-atick`)과 곁들이는 연도, 안내 글.
  static const ganjiTick = TextLook(10, ui.FontWeight.w400, Look.muted, spacing: -.14);
  static const ganjiGapja = TextLook(10, ui.FontWeight.w700, Look.accent, spacing: -.14);
  static const ganjiYear = TextLook(9, ui.FontWeight.w400, 0xcc666666, spacing: -.14);
  static const hint = TextLook(10, ui.FontWeight.w400, 0xcc666666, spacing: -.14);

  /// 모서리 칸의 안 여백 · 시대 줄 왼쪽의 색 줄 · 소속 줄의 들임.
  static const cornerPad = 10.0, trackBar = 3.0, subPad = 18.0;

  /// 여닫음 표시가 차지하는 자리 — 기준 덤프의 `.tl-group-btn i`에서 잰 값이다.
  /// '▸' · '▾' 글자 하나가 10px에서 8.22px을 쓰고, 딱지가 앞에 있으면 사이 빈칸 2.6px이 더 든다.
  /// 단추의 `<b>`와 `<i>` 사이 틈은 묶음 6px · 연호 접기 4px(css의 `gap`).
  static const arrowAdvance = 8.22, arrowSpace = 2.6, arrowInset = 2.5, arrowDrop = 1.0;

  /// 간지 눈금(`.tl-atick`)의 왼쪽 선 1px + 안 여백 4px.
  static const tickTextPad = 5.0;

  /// 보조 달력의 달 · 날 칸(`.tl-calmon` · `.tl-calday`). 글은 10.5px이고, **들어가는지 재는 자**는 [calFit]이다 —
  /// 지금 연표는 `textWidth(text, 10.5)`로 재는데 그 자는 굵기 500에 **자간이 없다**(그림판의 `measureText`는
  /// css의 `letter-spacing: -.14px`를 모른다 — js/timeline.js 110). 그려 놓고 보면 두 자릿수 달('10월')이
  /// 들어가느냐 마느냐가 여기서 갈린다. 그리는 데에는 아래 셋을 쓴다.
  static const calFit = TextLook(10.5, ui.FontWeight.w500, Look.muted);
  static const calFirst = TextLook(10.5, ui.FontWeight.w700, Look.ink, spacing: -.14);
  static const calFull = TextLook(10.5, ui.FontWeight.w600, Look.accent, spacing: -.14);

  /// 칸이 css에서 가질 수 있는 가장 좁은 폭(box-sizing: border-box라 안 여백 + 테두리 아래로는 줄지 않는다).
  /// 달 칸은 안 여백 3 + 3에 테두리 1 + 1, 날 칸은 안 여백이 없어 테두리 1 + 1뿐이다.
  static const calMonthMin = 8.0, calDayMin = 2.0;

  /// 날 눈금으로 바뀌는 문턱 — 하루가 20px 넘게 보일 때(지금 연표의 `_past('calDay', dayW, 20)`).
  static const calDayPx = 20.0;

  /// 보조 달력 고르기 단추(`.tl-cal-pick`)의 자리 — 오른쪽 끝이 모서리 칸의 오른쪽에서 11px 안,
  /// 안 여백은 왼쪽 2 · 오른쪽 12, 높이 18, 모서리 5(기준 덤프 `보조달력-열림`의 x 129~229 · y 136.5).
  static const calPickRight = 11.0, calPickPadLeft = 2.0, calPickPadRight = 12.0, calPickHeight = 18.0, calPickRadius = 5.0;

  /// 내림 세모는 단추의 오른쪽 끝에서 1px 안이다(css `… right 1px center / 4px 4px`).
  static const calCaretRight = 1.0;

  /// 커서가 올라간 고르기 단추의 글(`.tl-cal-pick:hover { color: var(--paper-ink) }`).
  static const calPickHot = TextLook(10.5, ui.FontWeight.w500, Look.ink, spacing: -.14);

  /// 칸의 둥근 정도.
  static const epochRadius = 6.0, cellRadius = 5.0, secRadius = 4.0, barRadius = 3.0;

  /// 끊어 그리는 테두리의 길이(기준 그림의 픽셀에서 쟀다): css `1px dashed`는 3 켜고 2 끔, `1px dotted`는 1 켜고 1 끔.
  static const dashOn = 3.0, dashOff = 2.0, dotOn = 1.0, dotOff = 1.0;

  /// 미정인 끝이 칸 안에서 옅어지는 길이의 최대(지금 연표의 `HT.UNKNOWN_FADE`).
  static const unknownFade = 44.0;

  /// 조명 메아리 괄호(`.tl-spot-brk`) — 연도 줄 아래쪽에 붙는 5px 높이의 가는 괄호, 위 모서리만 3px 둥글다.
  static const brkHeight = 5.0, brkRadius = 3.0;

  /// 강조에 든 칸(`.is-match`)의 테두리 색 `--warn`.
  static const warn = 0xff000000;

  /// 이설 표식(`.tl-calt`) — 1px 점 · 1 켜고 2 끔, 위아래 2px 들임. '이설 있음'은 이름 밑의 가로 점선.
  static const variantDash = 1.0, variantGap = 2.0, variantInset = 2.0;

  /// 같은 도시를 비출 때(`\.tl-axis.has-city`) 다른 도읍 칸의 밝기.
  static const cityDim = .32;
}

/// 날짜 칸의 작은 그림판: 둥근 모서리의 채움 조각과 1px 테두리 조각을 반지름마다 흰색으로 그려 두고,
/// 장면마다 `drawRawAtlas` 한 번으로 찍는다(색은 찍을 때 입힌다). 공용 `scene/sprites.dart`는 고치지 않는다.
class AxisSprites {
  AxisSprites() : _image = _render(1);
  ui.Image _image;
  double _scale = 1;

  /// 그려 둔 반지름들과 한 조각이 차지하는 칸.
  static const radii = [3.0, 4.0, 5.0, 6.0];
  static const _cell = 8.0, _sheetWidth = 64.0, _sheetHeight = 40.0;

  /// 조각의 자리: 0~3 채움(왼위 · 오른위 · 왼아래 · 오른아래), 4~7 테두리.
  static const cornerTopLeft = 0, cornerTopRight = 1, cornerBottomLeft = 2, cornerBottomRight = 3;

  /// 여닫음 표시의 작은 세모(지금 연표의 '▸' · '▾'). 글꼴의 그 글자는 10px에서 잉크가 3.5 × 3.5px이다
  /// (기준 그림의 픽셀로 쟀다 — `.tl-group-btn i`의 x 224~227.5 · y 435~438).
  static const arrowWidth = 3.5, arrowHeight = 3.5;
  static const _arrowRow = 4 * _cell;

  /// 보조 달력 고르기 단추의 내림 세모 — `.tl-cal-pick`이 css 그라데이션 둘로 그리는 8 × 4px 세모다.
  static const caretWidth = 8.0, caretHeight = 4.0;
  static const _caretX = 2 * _cell;

  static int _indexOf(double radius) {
    for (int i = 0; i < radii.length; i++) {
      if (radii[i] >= radius - .01) return i;
    }
    return radii.length - 1;
  }

  /// 반지름을 그려 둔 것 가운데 가장 가까운 것으로 맞춘다.
  static double snap(double radius) => radii[_indexOf(radius)];

  static ui.Image _render(double scale) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    final white = ui.Paint()..color = const ui.Color(0xffffffff);
    final line = ui.Paint()
      ..color = const ui.Color(0xffffffff)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    for (int ri = 0; ri < radii.length; ri++) {
      final r = radii[ri], y = ri * _cell;
      for (int corner = 0; corner < 4; corner++) {
        final x = corner * _cell;
        // 네 모서리는 돌릴 수 없으니(그림판은 크기만 바꾼다) 하나씩 그려 둔다.
        final cx = corner == cornerTopLeft || corner == cornerBottomLeft ? x + r : x;
        final cy = corner == cornerTopLeft || corner == cornerTopRight ? y + r : y;
        canvas.save();
        canvas.clipRect(ui.Rect.fromLTWH(x, y, r, r));
        canvas.drawCircle(ui.Offset(cx, cy), r, white);
        canvas.restore();
        canvas.save();
        canvas.clipRect(ui.Rect.fromLTWH(x + 4 * _cell, y, r, r));
        canvas.drawCircle(ui.Offset(cx + 4 * _cell, cy), r - .5, line);
        canvas.restore();
      }
    }
    // 오른쪽 세모(접힘)와 아래쪽 세모(펼침).
    canvas.drawPath(
      ui.Path()
        ..moveTo(0, _arrowRow)
        ..lineTo(arrowWidth, _arrowRow + arrowHeight / 2)
        ..lineTo(0, _arrowRow + arrowHeight)
        ..close(),
      white,
    );
    canvas.drawPath(
      ui.Path()
        ..moveTo(_cell, _arrowRow)
        ..lineTo(_cell + arrowHeight, _arrowRow)
        ..lineTo(_cell + arrowHeight / 2, _arrowRow + arrowWidth)
        ..close(),
      white,
    );
    // 보조 달력 고르기 단추의 내림 세모(8 × 4).
    canvas.drawPath(
      ui.Path()
        ..moveTo(_caretX, _arrowRow)
        ..lineTo(_caretX + caretWidth, _arrowRow)
        ..lineTo(_caretX + caretWidth / 2, _arrowRow + caretHeight)
        ..close(),
      white,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync((_sheetWidth * scale).ceil(), (_sheetHeight * scale).ceil());
    picture.dispose();
    return image;
  }

  /// 멎은 돋보기 배율로 다시 뜬다(조각이 작아 싸다).
  void setScale(double scale) {
    final next = (scale * 100).round() / 100;
    if (next == _scale || next <= 0) return;
    _image.dispose();
    _image = _render(next);
    _scale = next;
  }

  Float32List _transforms = Float32List(4 * 256), _rects = Float32List(4 * 256);
  Int32List _colors = Int32List(256);
  int _n = 0;
  final _paint = ui.Paint()..filterQuality = ui.FilterQuality.low;

  int get count => _n;

  /// 모서리 조각 하나를 왼쪽 위 자리에 찍는다. [corner]는 0~3, [border]면 1px 테두리 조각.
  void add(int corner, double left, double top, double radius, int argb, {bool border = false}) {
    final ri = _indexOf(radius), r = radii[ri];
    _put((corner + (border ? 4 : 0)) * _cell, ri * _cell, r, r, left, top, argb);
  }

  /// 여닫음 표시의 세모. 오른쪽 · 아래쪽 모두 3.5 × 3.5px이다.
  void arrow(bool down, double left, double top, int argb) => down
      ? _put(_cell, _arrowRow, arrowHeight, arrowWidth, left, top, argb)
      : _put(0, _arrowRow, arrowWidth, arrowHeight, left, top, argb);

  /// 보조 달력 고르기 단추의 내림 세모.
  void caret(double left, double top, int argb) => _put(_caretX, _arrowRow, caretWidth, caretHeight, left, top, argb);

  void _put(double sx, double sy, double sw, double sh, double left, double top, int argb) {
    if (_n == _colors.length) {
      _transforms = Float32List(_n * 8)..setRange(0, _n * 4, _transforms);
      _rects = Float32List(_n * 8)..setRange(0, _n * 4, _rects);
      _colors = Int32List(_n * 2)..setRange(0, _n, _colors);
    }
    final p = _n * 4, s = _scale;
    _transforms[p] = 1 / s;
    _transforms[p + 1] = 0;
    _transforms[p + 2] = left;
    _transforms[p + 3] = top;
    _rects[p] = sx * s;
    _rects[p + 1] = sy * s;
    _rects[p + 2] = (sx + sw) * s;
    _rects[p + 3] = (sy + sh) * s;
    _colors[_n] = argb;
    _n++;
  }

  void flush(ui.Canvas canvas) {
    if (_n == 0) return;
    canvas.drawRawAtlas(_image, Float32List.sublistView(_transforms, 0, _n * 4), Float32List.sublistView(_rects, 0, _n * 4), Int32List.sublistView(_colors, 0, _n), ui.BlendMode.modulate, null, _paint);
    _n = 0;
  }

  void dispose() => _image.dispose();
}

/// 이어 붙는 칸 무리의 배치(지금 연표의 `layoutStrip` · `joins`) — 같은 무리에서 맞닿은 칸은 틈 없이 잇는다.
class StripCell {
  StripCell(this.cell, this.index, this.l, this.r, this.atL, this.atR);
  final AxisCell cell;
  final int index;
  double l, r;
  bool jl = false, jr = false;

  /// 화면에서 잘린 쪽.
  final bool atL, atR;
  double get width => r - l;
}

/// [items]를 [lo]~[hi] 안에 놓는다. 너무 좁아 그리지 않는 칸이 있어도 무리가 끊기지 않게 앞 칸을 늘려 메운다.
List<StripCell> layoutStrip(List<AxisCell> items, double Function(AxisCell) a, double Function(AxisCell) b, double lo, double hi, {double minW = 1, int Function(AxisCell)? keyOf}) {
  final key = keyOf ?? (c) => c.strip;
  final vis = <(AxisCell, double, double)>[];
  for (final it in items) {
    final x0 = a(it), x1 = b(it);
    if (x1 > lo && x0 < hi) vis.add((it, x0, x1));
  }
  final joinRight = List<bool>.filled(vis.length, false);
  for (int i = 0; i + 1 < vis.length; i++) {
    joinRight[i] = key(vis[i].$1) == key(vis[i + 1].$1) && key(vis[i].$1) != 0 && (vis[i].$3 - vis[i + 1].$2).abs() < 1.5;
  }
  final cells = <StripCell>[];
  for (int n = 0; n < vis.length; n++) {
    final joinL = n > 0 && joinRight[n - 1], joinR = joinRight[n];
    cells.add(StripCell(
      vis[n].$1, n,
      vis[n].$2 > lo ? vis[n].$2 + (joinL ? 0 : .5) : lo,
      vis[n].$3 < hi ? vis[n].$3 - (joinR ? 0 : .5) : hi,
      vis[n].$2 <= lo, vis[n].$3 >= hi,
    ));
  }
  final drawn = [for (final c in cells) if (c.width >= minW) c];
  for (int k = 1; k < drawn.length; k++) {
    final p = drawn[k - 1], c = drawn[k];
    bool linked = true;
    for (int i = p.index; i < c.index; i++) {
      if (!joinRight[i]) linked = false;
    }
    if (!linked) continue;
    c.jl = p.jr = true;
    if (p.r < c.l) p.r = c.l;
  }
  return drawn;
}

/// 날짜 칸의 칸 하나를 가리키는 열쇠 — `'<트랙>:<종류>:<순번>'`(공통 줄의 시대 구분은 트랙 0).
/// 고른 칸 · 강조에 든 칸을 층에 알릴 때 쓴다(총괄이 채운다).
String axisCellKey(AxisCell cell) => '${cell.track}:${cell.kind}:${cell.seq}';

class AxisLayer {
  AxisModel? model;
  TimelineScene? _scene;
  final _sprites = AxisSprites();
  final _cellFill = <int, int>{}, _cellAlt = <int, int>{}, _cellEdge = <int, int>{}, _cellInk = <int, TextLook>{};
  final _barColor = <int, int>{}, _spotFill = <int, int>{};
  final _ganjiEdge = <int, int>{}, _ganjiInk = <int, TextLook>{};
  final _calFill = <int, int>{};
  TextLook? _calInkMemo;

  /// 보조 달력 칸의 기본 글(`.tl-acell` — 10.5px 400 · `color-mix(in srgb, --paper-muted 30%, --paper-ink)`).
  TextLook get _calInk =>
      _calInkMemo ??= TextLook(10.5, ui.FontWeight.w400, mixSrgb(0xff000000 | Look.muted, 0xff000000 | Look.ink, .30), spacing: -.14);

  /// 보조 달력이 날 눈금인가(문턱 둘 — 지금 연표의 `_past('calDay', dayW, 20)`). 한 번 켜지면 문턱의 92%까지 버틴다.
  bool _calDay = false;

  /// 섞은 색을 보관하는 열쇠. 칸 색은 늘 불투명(맨 앞 바이트가 0xff)이라 `색 | 갈래`로는 갈래가 묻힌다 —
  /// 색의 아래 세 바이트만 쓰고 맨 앞 바이트에 갈래 번호를 싣는다.
  static int _key(int color, int variant) => (color & 0xffffff) | (variant << 24);

  // ---- 총괄이 채우는 장면 상태(아직 장면에 밭이 없을 수 있어 층이 들고 있는다) ----

  /// 고르기 · 강조 · 기간 조명의 밝기. 없으면 중립(모두 1)으로 본다.
  Emphasis? emphasis;

  /// 기간 조명의 합친 구간(분) — 연도 줄 아래의 가는 괄호. 비어 있으면 [emphasis]의 조명에서 셈한다.
  /// 여기에 넣은 구간은 늘 다 켜진 것으로 본다(흐름 없음 — 검사와 그림 뜨기가 쓴다).
  /// (기준선 `.tl-marker`과 기간 재기 띠 `.tl-band-measure`는 몸통의 격자에 들어 있어 [GridLayer]가 그린다.)
  List<(double, double)> spotSpans = const [];

  /// 고른 칸(`.is-spot`)과 강조에 든 칸(`.is-match`) — 열쇠는 [axisCellKey].
  String? pickedCell;
  Set<String> matchCells = const {};

  /// 도읍 노선도가 비추는 도시(`.tl-axis.has-city`) — 그 이름의 도읍 칸만 밝고 나머지는 .32.
  String? hotCity;

  /// 커서가 올라간 자리(`:hover`) — 총괄이 [hitTest]의 답을 넣어 준다.
  AxisHit hover = AxisHit.none;

  /// 동작 줄이기: 날짜 칸의 높이가 흐르지 않고 곧바로 바뀐다(보기의 설정도 함께 본다).
  bool reduceMotion = false;
  bool get _still => reduceMotion || (_scene?.controller.reduceMotion ?? false);

  /// 그리는 쪽이 만들어질 때 한 번: 날짜 칸의 줄 구성을 셈해 높이를 장면에 알린다.
  void attach(TimelineScene scene) {
    _scene = scene;
    model = AxisModel(scene.layout);
    // 보조 달력의 '달의 시작 표'를 받아 두는 곳은 앱에 하나다(상세 창 · 검색의 음력 곁들임도 같은 표를 읽는다).
    // 총괄이 앱을 세우며 이미 채웠으면 그것을 쓰고, 비어 있으면 여기서 세운다.
    AuxCalendarStore.shared ??= AuxCalendarStore(scene.ask);
    shownHeight = targetHeight;
    _tellView(scene);
  }

  /// 날짜 칸의 목표 높이(줄 구성이 셈한 값)와 지금 흐르는 중인 높이.
  /// move/snap 스프링으로 높이가 흐른다. 또 바뀌면 지금 자리와 속도를 이어받고 공통 시계로 느려진다.
  double get targetHeight => model?.height ?? 0;
  double shownHeight = 0;

  final _flow = MotionSpring(0, epsilon: .05, maxOvershoot: 0);
  double _flowAt = 0;
  bool _telling = false;

  /// 높이가 흐르는 중인가.
  bool get flowing => _flow.active;

  /// 높이가 바뀌었다 — 지금 값에서 새 값으로 흐르기 시작한다.
  void _startFlow() {
    if (_still) {
      shownHeight = targetHeight;
      _flow.jump(targetHeight);
      return;
    }
    if (!_flow.active) _flow.jump(shownHeight);
    _flowAt = Motion.now();
    _flow.retarget(targetHeight, token: targetHeight < shownHeight ? MotionToken.snap : MotionToken.move);
  }

  /// 흐름을 한 칸 나아가게 한다. 아직 흐르는 중이면 참(다음 장면이 필요하다).
  bool _advance() {
    if (!_flow.active) return false;
    final now = Motion.now();
    _flow.step(now - _flowAt);
    _flowAt = now;
    shownHeight = _flow.value;
    return _flow.active;
  }

  /// 지금 높이를 보기에 알린다. **그리는 도중에는 부르지 않는다** — 그리는 도중에 다시 그리라는 알림이 가면
  /// 화면 틀이 막는다(줄 쌓기 작업자의 지적). 그릴 때는 [_tellViewLater]로 마이크로태스크에 미룬다.
  void _tellView(TimelineScene scene) {
    scene.axisHeight = shownHeight;
    scene.applyLayoutToView();
  }

  /// 그리기 밖(다음 마이크로태스크)에서 보기에 알린다.
  void _tellViewLater(TimelineScene scene) {
    scene.axisHeight = shownHeight;
    if (_telling) return;
    _telling = true;
    scheduleMicrotask(() {
      _telling = false;
      final s = _scene;
      if (s != null) s.applyLayoutToView();
    });
  }

  void setScale(double scale) => _sprites.setScale(scale);

  /// 누른 자리가 무엇인가(입력 연결은 총괄이 한다). [x] · [y]는 배치 px.
  /// 답에는 도움말 글([AxisHit.tip])과 그 칸 · 단추의 왼쪽 끝([AxisHit.x])이 실려 온다.
  AxisHit hitTest(double x, double y) {
    final scene = _scene, m = model;
    if (scene == null || m == null) return AxisHit.none;
    final v = scene.controller.view;
    if (y < 0 || y >= v.head) return AxisHit.none;
    return m.hitTest(x, y, v.left, v.minuteAt, xOf: v.xOf);
  }

  /// 묶음을 여닫고 날짜 칸의 높이를 다시 알린다(보기가 바뀌면 controller가 다시 그리라고 알린다).
  void toggleGroup(String key) => _toggle(() => model!.toggleGroup(key));

  /// 한 나라의 연호 줄을 한 줄로 접거나 편다.
  void toggleEraFold(int track) => _toggle(() => model!.toggleEraFold(track));

  /// 한 나라의 배도 갈래를 여닫는다.
  void toggleCapSec(int track) => _toggle(() => model!.toggleCapSec(track));

  /// 보조 달력을 바꾸거나 끈다('' = 끔).
  void setAltCal(String id) => _toggle(() => model!.setAltCal(id));

  /// 필터 시트의 '날짜 칸' 표시 체크 넷(간지 · 연호 · 도읍 · 시대 구분). 끄면 그 줄이 통째로 빠지고
  /// 날짜 칸의 높이가 그만큼 줄어든다 — 묶음 여닫기와 같은 360ms 흐름을 탄다.
  /// 총괄이 필터가 바뀔 때 `_painter.axis.setShown(...)`으로 부른다 — **그리는 도중에 장면마다 불러도 괜찮다**
  /// (바뀌지 않았으면 아무 일도 하지 않으므로 다시 그리라는 알림이 돌지 않는다).
  void setShown({bool? ganji, bool? eras, bool? capitals, bool? epochs}) =>
      _toggle(() => model!.setShown(ganji: ganji, eras: eras, capitals: capitals, epochs: epochs), defer: true);

  void setYearCycle(YearCycle? cycle) => _toggle(() => model!.setYearCycle(cycle), defer: true);

  double cycleNeed(PaintContext c) {
    final cycle = model?.yearCycle;
    if (cycle?.custom != true) return 26;
    var width = 20.0;
    // 웹 textWidth(이름, 10.5)는 굵기 500 · 자간 0으로 잰다(보조 달력과 같은 자).
    const look = AxisLook.calFit;
    for (final name in cycle!.names) {
      width = math.max(width, c.text.widthOf(name, look) ?? name.runes.length * 10.5);
    }
    return math.max(26, width.ceilToDouble() + 6);
  }

  /// 기억(`AppMemory.parts['axis']`)에 적을 것 — 열어 둔 묶음 · 접은 연호 · 펼친 배도 · 보조 달력 · 표시 넷.
  Map<String, dynamic> stateJson() => model?.stateJson() ?? const {};

  /// 기억을 되돌린다(열 때 한 번). 바뀌었으면 흐름 없이 곧바로 그 높이에서 선다.
  bool restoreState(Map<dynamic, dynamic> json) {
    final m = model;
    if (m == null || !m.restoreState(json)) return false;
    shownHeight = targetHeight;
    _flow.stop();
    final scene = _scene;
    if (scene != null) {
      _tellView(scene);
      scene.requestFrame();
    }
    return true;
  }

  /// 사람이 정한 날짜 칸 상태가 바뀔 때마다 오른다 — 총괄이 이 값을 보고 기억에 적는다.
  int get stateVersion => model?.stateVersion ?? 0;

  /// [change]가 거짓(바뀐 것 없음)이면 아무 일도 하지 않는다 — 장면마다 불려도 다시 그리라는 알림이 돌지 않게.
  /// [defer]면 보기에 알리는 일을 마이크로태스크로 미룬다 — 총괄이 표시 상태를 층에 옮겨 적는 자리는
  /// **그리는 도중**이라(그리개의 `_emphasize`) 바로 알리면 화면 틀이 막는다.
  void _toggle(bool Function() change, {bool defer = false}) {
    final scene = _scene;
    if (scene == null || !change()) return;
    _startFlow();
    if (defer) {
      _tellViewLater(scene);
    } else {
      _tellView(scene);
    }
    scene.requestFrame();
  }

  void paint(PaintContext c, RulerModel marks) {
    final m = model;
    if (m == null) return;
    // 자료집이 바뀌었거나 보조 달력 줄이 여닫혀 줄 구성이 달라졌으면 지금 높이에서 새 높이로 흐른다.
    // 보기에 알리는 일은 **그리기 밖**(마이크로태스크)에서 한다 — 그리는 도중의 알림은 화면 틀이 막는다.
    final rebuilt = m.sync() | m.setCalOpen(marks.calOpen);
    // 보조 달력 표는 한 번만 받는다(받는 중이면 다시 묻지 않는다). 받고 나면 그 장면을 다시 그린다.
    if (AuxCalendar.of(m.altCal) != null) {
      AuxCalendarStore.shared?.ensure(m.altCal, onReady: (_, _) => _scene?.requestFrame());
    }
    if (rebuilt) _startFlow();
    if (_advance() || rebuilt) c.scene.requestFrame();
    if (c.scene.axisHeight != shownHeight) _tellViewLater(c.scene);
    final w = c.w, left = c.left, head = c.head;
    final canvas = c.canvas;
    // 바탕: 날짜 칸 전체는 종이, 왼쪽 모서리 칸은 종이-2. 줄 사이 구분선과 아래 선까지 한 묶음으로.
    c.quads
      ..add(0, 0, w, head, 0xff000000 | Look.paper)
      ..add(0, 0, left, head, 0xff000000 | Look.paper); // 날짜 칸의 왼쪽 모서리 칸도 바탕과 같은 면(css의 `.tl-corner`)
    for (final row in m.rows) {
      // 접힌 보조 달력 줄의 구분선은 투명하다(css `.tl-axis-row.is-cal { border-top-color: transparent }`) —
      // 자리는 1px 차지하고 선은 보이지 않는다.
      if (row.border && !(row.kind == AxisRowKind.cal && !m.calOpen)) c.quads.add(left, row.top, w, row.top + 1, AxisLook.rowLine); // 목업: 구분선은 그림 영역만
    }
    _cornerEdges(c, m, left);
    c.quads.add(0, head - 1, w, head, AxisLook.bottom);
    c.flushShapes();

    // 왼쪽 모서리 칸
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTRB(0, 0, left, head));
    for (final row in m.rows) {
      if (row.contentHeight > 0) _corner(c, row, marks);
    }
    c.flushShapes();
    _sprites.flush(canvas);
    c.flushText();
    canvas.restore();

    // 그림 영역
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTRB(left, 0, w, head));
    for (final row in m.rows) {
      if (row.contentHeight <= 0) continue;
      switch (row.kind) {
        case AxisRowKind.years:
          _ticks(c, row, marks);
          _spotBrackets(c, row);
        case AxisRowKind.epoch:
          _epochs(c, row);
        case AxisRowKind.ganji:
          _ganji(c, row, marks);
        case AxisRowKind.cal:
          _cal(c, row);
        case AxisRowKind.group:
          if (row.groupKey == AxisModel.epochFold || !m.open.contains(row.groupKey)) _groupBars(c, row);
        case AxisRowKind.era:
          _cells(c, row, row.data!.cells, AxisModel.eraHeight, era: true);
        case AxisRowKind.cap:
          _cells(c, row, row.data!.cells, AxisModel.capHeight, era: false);
          if (row.secOpen) _secondary(c, row);
      }
    }
    c.flushShapes();
    _sprites.flush(canvas);
    c.flushText();
    canvas.restore();
  }

  /// 모서리 칸의 오른쪽 선이 없는 줄(css `.tl-group-btn` · `.tl-era-fold`는 `border-right: none`).
  /// 보조 달력 줄은 단추이지만 모서리는 그냥 `.tl-corner`라 선이 있다(기준 덤프 `보조달력-열림`의 모서리 style).
  static bool _isButton(AxisRow row) =>
      row.kind == AxisRowKind.group ||
      (row.kind == AxisRowKind.era && row.data!.lanes > 1) ||
      (row.kind == AxisRowKind.cap && row.data!.secLanes > 0);

  /// 모서리 칸의 오른쪽 선(x = [left] − 1 · 먹 8) — 단추인 줄([_isButton])에는 없다.
  /// 맞닿음(감독 결정 2026-10-25 "모든 가로세로 구분선은 맞닿게" · 꼴 off가 아니면 — paint_pick.dart [PaintPick.rows]): 줄마다 알맹이만 긋던 것을
  /// 그 줄의 구분선 줄(row.top)부터 다음 줄 앞까지로 — 구분선([left]부터)과 T자로 맞닿고 날짜 칸 밑줄(head − 1) 바로 위까지 끊김 없이 선다(예전에는
  /// 구분선 줄마다 1px 구멍 · 접힌 보조 달력 줄(투명한 구분선 1px)이 끼면 2px). 단추인 줄은 위 줄에 선이 있을 때만 제 구분선 줄 한 칸(ㄱ자 귀).
  /// 같은 열을 두 번 칠하지 않는다(줄마다 겹치지 않는 [top, 다음 top)).
  static void _cornerEdges(PaintContext c, AxisModel m, double left) {
    if (PaintPick.rows == FloorRule.off) {
      for (final row in m.rows) {
        if (row.contentHeight > 0 && !_isButton(row)) c.quads.add(left - 1, row.contentTop, left, row.contentTop + row.contentHeight, AxisLook.edge);
      }
      return;
    }
    var above = false; // 위 줄에 선이 있는가
    for (final row in m.rows) {
      final edge = !_isButton(row);
      if (edge && row.height > 0) {
        c.quads.add(left - 1, row.top, left, row.top + row.height, AxisLook.edge);
      } else if (above && row.border) {
        c.quads.add(left - 1, row.top, left, row.top + 1, AxisLook.edge);
      }
      above = edge;
    }
  }

  // ---- 조명 괄호 · 기준선 · 기간 재기 ----

  /// 조명이 걸렸던 띠의 번호. [Emphasis]는 흐르는 조명을 띠마다 내주므로(`spotsOf`), 물러나며 옅어지는 조명이
  /// 지금 목표(`look.spots`)에 없는 띠에 있을 수 있다 — 한 번 본 띠는 그 띠의 조명이 다 꺼질 때까지 들고 있는다.
  final _spotBands = <int>{};

  /// 괄호가 서 있는가. 지금 연표는 '같은 시기를 타국에도'(`show.spotEcho` · 기본 **끔**)가 꺼져 있으면 괄호를
  /// 아예 그리지 않는다(`_echoSpans` — js/timeline.js 2181, 그 괄호를 세우는 곳은 5742). 그 스위치가 곧
  /// [em.Look.lit]이다. 스위치를 끄거나 조명을 거두는 순간 괄호가 뚝 사라지지 않게, 조명이 물러나는 동안
  /// ([Emphasis.litMoving])에는 서 있던 것을 들고 있는다 — 반대로 꺼진 채 조명만 켜질 때는 서지 않는다.
  bool _litOn = false;

  /// 기간 조명의 합친 구간(분)과 그 짙기(0~1). 층에 넣어 준 [spotSpans]가 있으면 그것(짙기 1),
  /// 없으면 [emphasis]의 **흐르는** 조명(`spotsOf`의 [Spot.glow])에서 셈한다 — 조명이 켜지고 꺼지는 동안
  /// 괄호도 200ms · 160ms에 걸쳐 함께 짙어지고 옅어진다(명세 06의 3-3절). 괄호 자체는 '같은 시기를 타국에도'를
  /// 켰을 때만 선다([_litOn]) — 끈 채 칸을 고르면 조명만 걸리고 괄호는 없다. 가문 · 성씨 조명(`Look.houses`)은 스위치와 상관없이 선다.
  /// 겹치는 구간은 하나로 합치고, 합친 구간의 짙기는 든 것 가운데 가장 짙은 값이다(가장 밝은 값을 쓰는 띠 층과 같은 규칙).
  List<(double, double, double)> get litSpans {
    if (spotSpans.isNotEmpty) return [for (final (a, b) in spotSpans) (a, b, 1.0)];
    final em = emphasis;
    if (em == null) return const [];
    // 가문 · 성씨 조명(확정 설계 1-2 5-3 · `Look.houses`)은 메아리 스위치와 상관없이 괄호를 세운다 — 가문이 다스린 기간을 맨 위에서도 읽게.
    final standing = em.look.lit || em.look.housed;
    if (standing) {
      _litOn = true;
    } else if (!em.litMoving) {
      _litOn = false;
    }
    if (!_litOn) return const [];
    for (final s in em.look.spots) {
      _spotBands.add(s.band);
    }
    if (_spotBands.isEmpty) return const [];
    final raw = <(double, double, double)>[];
    _spotBands.removeWhere((band) {
      var any = false;
      for (final s in em.spotsOf(band)) {
        any = true;
        // 괄호가 서지 않는 조명(스위치를 끈 칸 조명)이 물러나는 조명과 함께 흐르는 동안에는, 새로 켜지는 그 조명의 괄호는 세우지 않는다
        // (물러나는 것만 옅어지며 남는다 — 띠 층의 `_wanted`와 같은 가림).
        if (!standing && _wanted(em, s)) continue;
        if (s.glow > .004) raw.add((s.start, s.end, s.glow));
      }
      return !any;
    });
    if (raw.isEmpty) return const [];
    raw.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(double, double, double)>[];
    for (final s in raw) {
      if (merged.isNotEmpty && s.$1 <= merged.last.$2) {
        final last = merged.last;
        merged[merged.length - 1] = (last.$1, s.$2 > last.$2 ? s.$2 : last.$2, s.$3 > last.$3 ? s.$3 : last.$3);
      } else {
        merged.add(s);
      }
    }
    return merged;
  }

  /// 이 구간이 지금 [Emphasis.look]의 조명이 바라는 것인가(= 물러나는 중이 아니다). 구간은 한 줌뿐이라 그냥 훑는다.
  static bool _wanted(Emphasis em, Spot s) {
    for (final w in em.look.spots) {
      if (w.key == s.key) return true;
    }
    return false;
  }

  /// 조명 메아리 괄호(`.tl-spot-brk`): 연도 줄의 아래쪽에 기간마다 위 모서리만 둥근 가는 괄호.
  /// 괄호의 짙기는 그 구간의 조명이 얼마나 켜졌는가([Spot.glow])다.
  void _spotBrackets(PaintContext c, AxisRow row) {
    final spans = litSpans;
    if (spans.isEmpty) return;
    final v = c.v, w = c.w, left = c.left;
    final bottom = row.contentTop + row.contentHeight, top = bottom - AxisLook.brkHeight;
    for (final (a, b, glow) in spans) {
      final l = v.xOf(a).clamp(left, w), r = v.xOf(b).clamp(left, w);
      if (r - l <= .5) continue;
      final color = withAlpha(0xff000000 | Look.ink, .55 * glow);
      final cutL = v.xOf(a) < left, cutR = v.xOf(b) > w;
      final rad = AxisSprites.snap(math.min(AxisLook.brkRadius, (r - l) / 2));
      // 위 가로선 + 좌우 세로선(아래는 없다) + 위 모서리 조각.
      final hl = cutL ? l : l + rad, hr = cutR ? r : r - rad;
      if (hr > hl) c.quads.add(hl, top, hr, top + 1, color);
      if (!cutL) {
        c.quads.add(l, top + rad, l + 1, bottom, color);
        _sprites.add(AxisSprites.cornerTopLeft, l, top, rad, color, border: true);
      }
      if (!cutR) {
        c.quads.add(r - 1, top + rad, r, bottom, color);
        _sprites.add(AxisSprites.cornerTopRight, r - rad, top, rad, color, border: true);
      }
      c.stats.shapes++;
    }
  }


  // ---- 왼쪽 모서리 칸 ----

  void _corner(PaintContext c, AxisRow row, RulerModel marks) {
    final left = c.left;
    final top = row.contentTop, height = row.contentHeight;
    final center = top + height / 2;
    if ((row.kind == AxisRowKind.years && marks.context.isEmpty) || row.kind == AxisRowKind.epoch) {
      _mockCorner(c, row, marks);
      return;
    }
    if (row.kind == AxisRowKind.cal) {
      _calCorner(c, row, center);
      return;
    }
    // 시대 · 연호 · 도읍 줄은 왼쪽에 3px 색 줄.
    if (row.kind == AxisRowKind.epoch || row.kind == AxisRowKind.era || row.kind == AxisRowKind.cap) {
      c.quads.add(0, top, AxisLook.trackBar, top + height, 0xff000000 | (row.track?.color ?? Look.accent));
    }
    final sub = row.kind == AxisRowKind.era || row.kind == AxisRowKind.cap;
    if (sub) _elbow(c, center);
    final right = left - AxisLook.cornerPad;
    // 여닫음 표시의 세모는 글꼴에 없어 조각으로 찍는다 — 지금 연표에서 그 글자가 차지하던 폭을 먼저 빼 둔다.
    final group = row.kind == AxisRowKind.group;
    // 여닫음 표시는 지금 연표에서 딱지와 같은 글줄(`<i>`) 안에 있다 — 딱지가 있으면 사이 빈칸만큼,
    // 없으면 단추의 틈(`gap`)만큼 앞에 자리를 비운다.
    final gap = group ? 6.0 : 4.0;
    final arrow = row.arrow == AxisArrow.none ? 0.0 : AxisLook.arrowAdvance + (row.mark.isEmpty ? gap : AxisLook.arrowSpace);
    // 단추인 줄에 커서가 올라가면 바탕이 짙어진다(css `.tl-group-btn:hover` · `.tl-era-fold:hover`).
    if (row.kind != AxisRowKind.epoch && _hovered(row)) {
      final tint = group || row.kind == AxisRowKind.cal
          ? mixSrgb(0xff000000 | Look.accent, 0xff000000 | Look.paper2, group ? .10 : .06)
          : mixSrgb(0xff000000 | (row.track?.color ?? Look.accent), 0xff000000 | Look.paper2, .14);
      c.quads.add(AxisLook.trackBar, top, left, top + height, tint);
    }
    final look = group ? AxisLook.groupName : (row.kind == AxisRowKind.epoch ? AxisLook.cornerBold : AxisLook.corner);
    // 해보다 작은 눈금에서는 지금 자리를 굵게 앞에 두고 보기 폭은 작은 글로(`<b>827년 5월</b><small>· 12일 보기</small>`).
    final years = row.kind == AxisRowKind.years;
    final context = years ? marks.context : '';
    final text = years ? (context.isEmpty ? '${spanText(marks.spanYears)} 보기' : '· ${spanText(marks.spanYears)} 보기') : row.corner;
    if (text.isEmpty && row.mark.isEmpty && context.isEmpty) return;
    final textLook = context.isEmpty ? look : AxisLook.cornerSmall;
    final width = c.text.widthOf(text, textLook);
    if (width == null) return;
    double contextWidth = 0;
    if (context.isNotEmpty) {
      final measured = c.text.widthOf(context, AxisLook.cornerStrong);
      if (measured == null) return;
      contextWidth = measured + 6;
    }
    double markWidth = 0;
    if (row.mark.isNotEmpty) {
      final measured = c.text.widthOf(row.mark, AxisLook.groupMark);
      if (measured == null) return;
      markWidth = measured + gap;
    }
    final at = right - arrow - markWidth - width;
    if (context.isNotEmpty) {
      c.later.add('axis-corner', context, AxisLook.cornerStrong, at - contextWidth, center - AxisLook.cornerStrong.size * .6);
    }
    c.later.add('axis-corner', text, textLook, at, center - textLook.size * .6);
    if (row.mark.isNotEmpty) {
      c.later.add('axis-corner', row.mark, AxisLook.groupMark, at + width + gap, center - AxisLook.groupMark.size * .6);
    }
    if (row.arrow == AxisArrow.none) return;
    final down = row.arrow == AxisArrow.down;
    final aw = down ? AxisSprites.arrowHeight : AxisSprites.arrowWidth, ah = down ? AxisSprites.arrowWidth : AxisSprites.arrowHeight;
    _sprites.arrow(down, right - AxisLook.arrowInset - aw, center - ah / 2 + AxisLook.arrowDrop, 0xff000000 | Look.accent);
  }

  /// 연도 · 시대 줄의 모서리(목업 서고): 오른쪽 맞춤 글 하나 — 연도 줄은 'n년 보기'(10 · 먹 60), 시대 줄은 줄 이름(10 굵게 · 먹 60 · 첫 단 가운데).
  void _mockCorner(PaintContext c, AxisRow row, RulerModel marks) {
    final years = row.kind == AxisRowKind.years;
    final text = years ? '${spanText(marks.spanYears)} 보기' : row.corner;
    final look = years ? AxisLook.mockSpan : AxisLook.mockCorner;
    final width = c.text.widthOf(text, look);
    if (width == null || text.isEmpty) return;
    final mid = years ? row.top + AxisLook.mockMid : row.contentTop + AxisModel.epochPad - 1 + AxisLook.epochTag / 2;
    c.later.add('axis-corner', text, look, c.left - AxisLook.mockRight - width, mid - look.size * .6);
  }

  /// 보조 달력 줄의 모서리 — 달력 고르기 단추(`.tl-cal-pick`). 지금 연표는 `<select>`라 이름이 오른쪽 맞춤으로 앉고
  /// 그 오른쪽에 css 그라데이션 둘로 그린 8 × 4px 내림 세모가 붙는다. 단추의 폭은 `<select>`의 제 크기 —
  /// 가장 긴 달력 이름에 안 여백(왼 2 · 오른 12)을 더한 값이다(기준 덤프 `보조달력-열림`: x 129~229 · 폭 100 · 높이 18).
  void _calCorner(PaintContext c, AxisRow row, double center) {
    final right = c.left - AxisLook.calPickRight;
    double widest = 0;
    for (final cal in AuxCalendar.list) {
      final measured = c.text.widthOf(cal.name, AxisLook.corner);
      if (measured == null) return;
      if (measured > widest) widest = measured;
    }
    final boxLeft = right - (widest + AxisLook.calPickPadLeft + AxisLook.calPickPadRight);
    // 커서를 받는 범위는 이 단추 안뿐이다(지금 연표의 `<select>` 제 크기) — 모서리 칸 전체가 아니다.
    model
      ?..calPickL = boxLeft
      ..calPickR = right;
    final hovered = _hovered(row);
    if (hovered) {
      // css `.tl-cal-pick:hover { background-color: color-mix(in srgb, var(--paper-ink) 6%, transparent) }` — 종이-2 위에 얹힌 값.
      final tint = _calFill[0] ??= mixSrgb(0xff000000 | Look.ink, 0xff000000 | Look.paper2, .06);
      final top = center - AxisLook.calPickHeight / 2;
      _box(c, boxLeft, top, right, top + AxisLook.calPickHeight, AxisLook.calPickRadius, tint, tint, border: false);
      c.stats.shapes++;
    }
    final look = hovered ? AxisLook.calPickHot : AxisLook.corner;
    final width = c.text.widthOf(row.corner, look);
    if (width == null) return;
    c.later.add('axis-corner', row.corner, look, right - AxisLook.calPickPadRight - width, center - look.size * .6);
    // 세모는 단추의 오른쪽 끝에서 1px 안(css `right 1px center`), 세로 가운데.
    _sprites.caret(
      right - AxisLook.calCaretRight - AxisSprites.caretWidth, center - AxisSprites.caretHeight / 2,
      hovered ? (0xff000000 | Look.ink) : (0xff000000 | Look.muted),
    );
  }

  /// 그 줄의 모서리 단추에 커서가 올라가 있는가.
  bool _hovered(AxisRow row) {
    final m = model;
    if (m == null || hover.kind == AxisHitKind.none || hover.row < 0 || hover.row >= m.rows.length) return false;
    return identical(m.rows[hover.row], row) &&
        (hover.kind == AxisHitKind.groupToggle || hover.kind == AxisHitKind.eraFold || hover.kind == AxisHitKind.capSec || hover.kind == AxisHitKind.calPick);
  }

  /// 소속 줄의 갈고리(`.tl-axis-row.is-sub .tl-corner::before` — 6×6, 왼쪽 · 아래 선).
  void _elbow(PaintContext c, double center) {
    final color = withAlpha(0xff000000 | Look.muted, .5);
    final top = center - 3 - 2;
    c.quads
      ..add(AxisLook.subPad, top, AxisLook.subPad + 1, top + 6, color)
      ..add(AxisLook.subPad, top + 5, AxisLook.subPad + 6, top + 6, color);
  }

  // ---- 연도 눈금 ----

  void _ticks(PaintContext c, AxisRow row, RulerModel marks) {
    final v = c.v, w = c.w, left = c.left;
    // css의 `.tl-tick { top: 8px }`는 줄 높이 1.5의 글 상자 기준이다 — 1.2로 그리는 만큼 내려 맞춘다.
    final top = row.contentTop + 8 + (AxisLook.tick.size * 1.5 - AxisLook.tick.size * 1.2) / 2;
    // 목업(서고 dateHeader): 해보다 큰 눈금은 눈금 오른쪽 4에 왼쪽 맞춤 · 오른쪽 끝을 넘으면 숨김. 해보다 작은 눈금은 옛 가운데 맞춤.
    final mock = marks.context.isEmpty;
    for (final t in marks.ticks) {
      if (!t.shown) continue;
      final x = v.xOf(t.minute);
      if (x < left - 60 || x > w + 60) continue;
      final look = mock ? AxisLook.mockTick : (t.major ? AxisLook.tickMajor : AxisLook.tick);
      final width = c.text.widthOf(t.label, look);
      if (width == null) continue;
      if (mock) {
        if (x < left || x + AxisLook.mockTickX + width > w - 4) continue;
        c.later.add('axis-tick', t.label, look, x + AxisLook.mockTickX, row.top + AxisLook.mockMid - look.size * .6);
      } else {
        c.later.add('axis-tick', t.label, look, x - width / 2, top);
      }
    }
  }

  // ---- 시대 구분 ----

  /// 시대 구분 = 흰 이름 종이(목업 서고 labelEra — 리메이크 2부): 높이 15 · 왼쪽 두 귀 모따기 3(화면에 잘린 쪽은 직각) · 오른쪽 직각 · 종이 칠 · 테 먹 40,
  /// 이름 9.5 굵게 먹 80을 왼쪽 6(잘렸으면 그림 영역 왼쪽 + 6)에 — 다 들지 않으면 첫 글자, 그것도 안 들면 글 없이. 단은 17마다.
  void _epochs(PaintContext c, AxisRow row) {
    final v = c.v, w = c.w, left = c.left;
    const h = AxisLook.epochTag, k = AxisLook.epochCham, edge = AxisLook.epochEdge, fill = 0xff000000 | Look.paper;
    for (final e in row.epochs) {
      final a = v.xOf(e.start), b = v.xOf(e.end);
      if (b < left || a > w) continue;
      final cutL = a < left;
      final x0 = math.max(a, left).roundToDouble(), x1 = math.min(b, w + 20).roundToDouble();
      if (x1 - x0 < 2) continue;
      final y0 = (row.contentTop + AxisModel.epochPad - 1 + e.lane * AxisModel.epochHeight).roundToDouble(), y1 = y0 + h;
      final q = c.quads;
      if (cutL) {
        q.add(x0, y0, x1, y1, fill);
      } else {
        for (int i = 0; i < k; i++) {
          q.add(x0 + k - i, y0 + i, x1, y0 + i + 1, fill);
          q.add(x0 + k - i, y1 - i - 1, x1, y1 - i, fill);
          q.add(x0 + k - i - 1, y0 + i, x0 + k - i, y0 + i + 1, edge);
          q.add(x0 + k - i - 1, y1 - i - 1, x0 + k - i, y1 - i, edge);
        }
        q.add(x0, y0 + k, x1, y1 - k, fill);
      }
      final l = cutL ? x0 : x0 + k;
      q.hLine(l, x1, y0, edge);
      q.hLine(l, x1, y1 - 1, edge);
      q.vLine(x0, cutL ? y0 : y0 + k, cutL ? y1 : y1 - k, edge);
      if (b <= w) q.vLine(x1 - 1, y0, y1, edge);
      c.stats.shapes++;
      const look = AxisLook.mockEpoch;
      final room = x1 - x0 - 12;
      final full = c.text.widthOf(e.name, look);
      if (full == null) continue;
      final first = e.name.isEmpty ? '' : String.fromCharCode(e.name.runes.first);
      final text = full <= room ? e.name : ((c.text.widthOf(first, look) ?? room + 1) <= room ? first : '');
      if (text.isEmpty) continue;
      c.later.add('axis-epoch', text, look, x0 + AxisLook.epochText, (y0 + y1) / 2 - .5 - look.size * .6);
    }
  }

  // ---- 간지 ----

  void _ganji(PaintContext c, AxisRow row, RulerModel marks) {
    final v = c.v, w = c.w, left = c.left;
    final top = row.contentTop, height = row.contentHeight;
    if (marks.ganjiMode == GanjiMode.hint) {
      final cycle = model?.yearCycle;
      final text = cycle?.custom == true ? '확대하면 ${cycle!.title} 줄이 보입니다' : '확대하면 간지가 보입니다';
      if (c.text.widthOf(text, AxisLook.hint) == null) return;
      c.later.add('axis-ganji', text, AxisLook.hint, left + 8, top + height / 2 - AxisLook.hint.size * .6);
      return;
    }
    if (marks.ganjiMode == GanjiMode.cells || marks.ganjiMode == GanjiMode.days) {
      // 해(또는 날)마다 이어지므로 틈 없는 하나의 긴 둥근 칸 — 번갈아 짙은 바탕, 갑자(갑자일)는 강조.
      final cellTop = top + 3, cellBottom = top + height - 3;
      final list = marks.ganji;
      for (int i = 0; i < list.length; i++) {
        final g = list[i];
        final x1 = v.xOf(g.start), x2 = v.xOf(g.end);
        if (x2 < left || x1 > w) continue;
        final joinL = i > 0 && (v.xOf(list[i - 1].end) - x1).abs() < 1.5;
        final joinR = i + 1 < list.length && (x2 - v.xOf(list[i + 1].start)).abs() < 1.5;
        final l = x1 + (joinL ? 0 : .5), r = x2 - (joinR ? 0 : .5);
        if (r - l < .5) continue;
        final gapja = g.index == 0;
        final fill = g.alt
            ? (_ganjiEdge[2] ??= mixSrgb(0xff000000 | Look.muted, 0xff000000 | Look.paper, .12))
            : (_ganjiEdge[3] ??= mixSrgb(0xff000000 | Look.muted, 0xff000000 | Look.paper, .08));
        final edge = gapja
            ? (_ganjiEdge[1] ??= mixOklab(0xff000000 | Look.accent, 0xff000000 | Look.paper, .70))
            : (_ganjiEdge[0] ??= mixOklab(0xff000000 | Look.muted, 0xff000000 | Look.ink, .92));
        _box(c, l, cellTop, r, cellBottom, AxisLook.cellRadius, fill, edge, roundL: !joinL, roundR: !joinR, leftEdge: joinL ? mixSrgb(edge, edge & 0x00ffffff, .55) : null, openRight: joinR);
        c.stats.shapes++;
        final look = gapja
            ? (_ganjiInk[1] ??= const TextLook(10.5, ui.FontWeight.w700, 0xff000000 | Look.accent, spacing: -.14))
            : (_ganjiInk[0] ??= TextLook(10.5, ui.FontWeight.w400, mixSrgb(0xff000000 | Look.muted, 0xff000000 | Look.ink, .30), spacing: -.14));
        final width = c.text.widthOf(g.name, look);
        if (width == null || r - l < width + 4) continue;
        c.later.add('axis-ganji', g.name, look, (l + r) / 2 - width / 2, (cellTop + cellBottom) / 2 - look.size * .6);
      }
      return;
    }
    // 몇 해마다 눈금 · 60년마다 갑자: 왼쪽 1px 선(accent 55%)에 이름을 붙인다.
    final tickTop = top + 2, tickBottom = top + height - 2;
    final soft = withAlpha(0xff000000 | Look.accent, .55);
    for (final g in marks.ganji) {
      final x = v.xOf(g.start);
      if (x < left - 30 || x > w) continue;
      // 사용자 순환의 한 바퀴 눈금은 웹의 일반 tl-atick(굵은 첫 해 강조 없음)이다.
      final gapja = g.index == 0 && !(model?.yearCycle?.custom == true && marks.ganjiMode == GanjiMode.gapja);
      final look = gapja ? AxisLook.ganjiGapja : AxisLook.ganjiTick;
      final text = marks.ganjiMode == GanjiMode.gapja ? '${g.name} ${g.year}' : g.name;
      final width = c.text.widthOf(text, look);
      if (width == null) continue;
      c.quads.add(x, tickTop, x + 1, tickBottom, gapja ? (0xff000000 | Look.accent) : soft);
      c.stats.shapes++;
      c.later.add('axis-ganji', text, look, x + AxisLook.tickTextPad, (tickTop + tickBottom) / 2 - look.size * .6);
      if (marks.ganjiMode != GanjiMode.ticks || g.year.isEmpty) continue;
      final yearWidth = c.text.widthOf(g.year, AxisLook.ganjiYear);
      if (yearWidth == null) continue;
      c.later.add('axis-ganji', g.year, AxisLook.ganjiYear, x + AxisLook.tickTextPad + width + 3, (tickTop + tickBottom) / 2 - AxisLook.ganjiYear.size * .6);
    }
  }

  // ---- 보조 달력(음력 · 이슬람력 · 페르시아력) ----

  /// 펼친 보조 달력 줄. 지금 연표의 `_draw`(js/timeline.js 5822~5877) 그대로다 —
  /// 하루가 20px을 넘으면 **날 눈금**(초하루는 달 이름 · 음력 보름은 강조), 아니면 **달 눈금**이다.
  /// 환산은 넣을 때 한 번 뜬 '달의 시작 표'([AuxCalendarTable])로 한다. 표가 아직 없거나 표 밖이면 줄은 비어 있다.
  void _cal(PaintContext c, AxisRow row) {
    final m = model;
    if (m == null) return;
    final table = AuxCalendarStore.shared?.table(m.altCal);
    if (table == null) return;
    final v = c.v;
    final top = row.contentTop, height = row.contentHeight;
    final cellTop = top + 3, cellBottom = top + height - 3;
    if (cellBottom - cellTop < 1) return;
    final j0 = dayAt(yearAt(v.lo)).j, j1 = dayAt(yearAt(v.hi)).j;
    // 문턱 둘: 하루가 20px을 넘으면 날 눈금, 한 번 켜지면 18.4px까지 버틴다.
    final dayWidth = v.ppm * _yearMinutes / 365.25;
    _calDay = _calDay ? dayWidth >= AxisLook.calDayPx * (1 - _thresholdGap) : dayWidth >= AxisLook.calDayPx;
    // 도움말이 달 칸인지 날 칸인지를 가릴 수 있게 줄 구성 쪽에도 적어 둔다(문턱은 여기서만 센다).
    m.calDay = _calDay;
    if (_calDay) {
      _calDays(c, table, j0, j1, cellTop, cellBottom);
      return;
    }
    _calMonths(c, table, j0, j1, cellTop, cellBottom);
  }

  /// 달 눈금. 칸은 다음 달의 초하루까지 이어지고, 목록의 마지막은 30일 뒤로 끊는다(지금 연표와 같다).
  void _calMonths(PaintContext c, AuxCalendarTable table, int j0, int j1, double cellTop, double cellBottom) {
    final v = c.v, w = c.w, left = c.left;
    final months = table.monthsIn(j0 - 1, j1 + 1);
    for (int i = 0; i < months.length; i++) {
      final month = months[i];
      final nextT = i + 1 < months.length ? tOfJdn(months[i + 1].startJdn) : tOfJdn(month.startJdn + 30);
      final x1 = v.xOf(minuteOfYear(tOfJdn(month.startJdn))), x2 = v.xOf(minuteOfYear(nextT));
      if (x2 < left || x1 > w) continue;
      final l = math.max(x1, left), r = math.min(x2, w);
      final span = r - l;
      if (span < 1) continue;
      final cutL = x1 < left, cutR = x2 > w;
      final boxL = l + (cutL ? 0 : .5);
      final boxR = boxL + math.max(AxisLook.calMonthMin, span - (cutL ? 0 : .5) - (cutR ? 0 : .5));
      final name = table.monthName(month);
      final label = month.yearStart ? '${table.yearName(month.year)} $name' : name;
      // 들어가는지 재는 굵기는 지금 연표와 같은 500이다(글은 아래에서 제 굵기로 그린다).
      final labelWidth = c.text.widthOf(label, AxisLook.calFit), nameWidth = c.text.widthOf(name, AxisLook.calFit);
      if (labelWidth == null || nameWidth == null) continue;
      final text = span >= labelWidth + 8 ? label : (span >= nameWidth + 6 ? name : '');
      final alt = i.isOdd;
      final fill = _calFill[alt ? 1 : 2] ??= mixSrgb(0xff000000 | Look.muted, 0xff000000 | Look.paper, alt ? .12 : .08);
      final edge = _ganjiEdge[0] ??= mixOklab(0xff000000 | Look.muted, 0xff000000 | Look.ink, .92);
      _box(
        c, boxL, cellTop, boxR, cellBottom, AxisLook.cellRadius, fill, edge,
        roundL: !cutL, roundR: !cutR,
        // 윤달은 네 변이 모두 파선이다(css `.tl-axis .tl-calmon.is-leap { border-style: dashed }`).
        dashL: month.leap ? AxisLook.dashOn : 0, dashR: month.leap ? AxisLook.dashOn : 0, dashH: month.leap,
      );
      c.stats.shapes++;
      if (text.isEmpty) continue;
      final look = month.yearStart ? AxisLook.calFirst : _calInk;
      final width = c.text.widthOf(text, look);
      if (width == null) continue;
      c.later.add('axis-cal', text, look, (boxL + boxR) / 2 - width / 2, (cellTop + cellBottom) / 2 - look.size * .6);
    }
  }

  /// 날 눈금. 한 화면에 500칸까지만 만든다(지금 연표와 같은 안전장치).
  void _calDays(PaintContext c, AuxCalendarTable table, int j0, int j1, double cellTop, double cellBottom) {
    final v = c.v, w = c.w, left = c.left;
    // 날마다 해 좌표를 두 번 셈하지 않게 앞 날의 끝을 이어 쓴다(다음 날의 시작과 같은 값이다).
    double tNow = tOfJdn(j0);
    for (int j = j0; j <= j1 + 1 && j - j0 < _maxCalDays; j++) {
      final date = table.dateOfJdn(j);
      if (date == null) break; // 표 밖 — 지금 연표도 ICU가 답을 못 주면 거기서 그친다
      final tNext = tOfJdn(j + 1);
      // 기원전 1년 12월 31일 다음은 빈 0년 자리를 건너뛰므로 그날만 하루 폭으로 끊는다(`HT.cal.dayEnd`).
      final tEnd = tNext - tNow > .01 ? tNow + 1 / 366 : tNext;
      final x1 = v.xOf(minuteOfYear(tNow)), x2 = v.xOf(minuteOfYear(tEnd));
      tNow = tNext;
      if (x2 < left || x1 > w) continue;
      final first = date.day == 1;
      final name = '${date.leap ? '윤' : ''}${date.month}월';
      final label = first ? (date.month == 1 && !date.leap ? '${table.yearName(date.year)} $name' : name) : '${date.day}';
      final fitWidth = c.text.widthOf(label, AxisLook.calFit);
      if (fitWidth == null) continue;
      final text = x2 - x1 >= fitWidth + 6 ? label : (first ? '${date.month}' : '');
      final boxL = x1 + .5, boxR = boxL + math.max(AxisLook.calDayMin, x2 - x1 - 1);
      // 한 칸 걸러 짙은 바탕은 날이 아니라 **달**마다 바뀐다(지금 연표의 `(p.m + 윤달) % 2`).
      final alt = (date.month + (date.leap ? 1 : 0)).isOdd;
      final fill = _calFill[alt ? 1 : 2] ??= mixSrgb(0xff000000 | Look.muted, 0xff000000 | Look.paper, alt ? .12 : .08);
      final edge = _ganjiEdge[0] ??= mixOklab(0xff000000 | Look.muted, 0xff000000 | Look.ink, .92);
      _box(c, boxL, cellTop, boxR, cellBottom, AxisLook.cellRadius, fill, edge);
      c.stats.shapes++;
      if (text.isEmpty) continue;
      final look = first ? AxisLook.calFirst : (table.lunar && date.day == 15 ? AxisLook.calFull : _calInk);
      final width = c.text.widthOf(text, look);
      if (width == null) continue;
      c.later.add('axis-cal', text, look, (boxL + boxR) / 2 - width / 2, (cellTop + cellBottom) / 2 - look.size * .6);
    }
  }

  // ---- 접힌 묶음의 가는 막대 ----

  void _groupBars(PaintContext c, AxisRow row) {
    final v = c.v, w = c.w, left = c.left;
    final n = math.min(row.members.length, 4);
    if (n == 0) return;
    final bh = math.min(5, (AxisModel.groupHeight - 6) ~/ n - 1).toDouble();
    if (bh < 1) return;
    final top0 = row.contentTop + (AxisModel.groupHeight - (n * (bh + 1) - 1)) / 2;
    for (int i = 0; i < n; i++) {
      final d = row.members[i];
      if (row.groupKey == AxisModel.epochFold) {
        final cells = [...d.cells]..sort((a, b) => a.start.compareTo(b.start));
        final top = top0 + i * (bh + 1);
        for (final cell in cells) {
          final l = math.max(v.xOf(cell.start), left), r = math.min(v.xOf(cell.end), w);
          if (r - l < .5) continue;
          final color = _barColor[cell.color] ??= mixSrgb(0xff000000 | cell.color, 0xff000000 | Look.paper, .62);
          _box(c, l, top, math.max(l + 2, r), top + bh, AxisLook.barRadius, color, color, border: false);
          c.stats.shapes++;
        }
        continue;
      }
      final color = _barColor[d.track.color] ??= mixSrgb(0xff000000 | d.track.color, 0xff000000 | Look.paper, .62);
      final top = top0 + i * (bh + 1);
      for (final span in d.spans) {
        final l = math.max(v.xOf(span.$1), left), r = math.min(v.xOf(span.$2), w);
        if (r - l < .5) continue;
        _box(c, l, top, math.max(l + 2, r), top + bh, AxisLook.barRadius, color, color, border: false);
        c.stats.shapes++;
      }
    }
  }

  // ---- 나라별 연호 · 도읍 칸 ----

  void _cells(PaintContext c, AxisRow row, List<AxisCell> cells, double laneHeight, {required bool era}) {
    final v = c.v, w = c.w, left = c.left;
    final byLane = <int, List<AxisCell>>{};
    final order = <AxisCell, int>{};
    // 번갈아 짙은 바탕(is-alt)의 차례는 갈래와 상관없이 그 줄에 보이는 칸의 시작 순이다(칸은 이미 시작 순으로 온다).
    double sum = 0;
    for (final cell in cells) {
      final x0 = v.xOf(cell.start), x1 = v.xOf(cell.end);
      if (x1 < left || x0 > w) continue;
      (byLane[row.folded ? 0 : cell.lane] ??= []).add(cell);
      order[cell] = order.length;
      sum += math.min(x1, w) - math.max(x0, left);
    }
    if (byLane.isEmpty) return;
    // 이름을 붙일지 정하는 평균 폭(지금 연표의 avg).
    final avg = sum / order.length;
    // 도읍 노선도가 도시를 비추면 같은 이름의 칸만 밝다 — 같은 이름이 둘 이상 보일 때만 나머지를 흐린다.
    final city = era ? null : hotCity;
    int cityHits = 0;
    if (city != null) {
      for (final cell in order.keys) {
        if (cell.name == city) cityHits++;
      }
    }
    final filtered = emphasis?.look.filtered ?? false;
    for (final entry in byLane.entries) {
      final list = entry.value..sort((a, b) => a.start.compareTo(b.start));
      final strip = layoutStrip(list, (cell) => v.xOf(cell.start), (cell) => v.xOf(cell.end), left, w, minW: .5);
      final top = row.contentTop + entry.key * laneHeight + 3, bottom = top + laneHeight - 6;
      for (final s in strip) {
        final cell = s.cell;
        final key = axisCellKey(cell);
        final color = 0xff000000 | (cell.color == 0 ? row.track!.color : cell.color);
        final temporary = cell.style & AxisModel.styleTemporary != 0;
        final alt = (order[cell] ?? 0).isOdd;
        final spot = pickedCell == key;
        final dim = cityHits > 1 && cell.name != city ? AxisLook.cityDim : 1.0;
        var fill = spot
            ? (_spotFill[color] ??= mixSrgb(color, 0xff000000 | Look.paper, .48))
            : temporary
                ? (_cellFill[_key(color, 1)] ??= mixSrgb(color, 0xff000000 | Look.paper, .03))
                : (alt ? (_cellAlt[color] ??= mixSrgb(color, 0xff000000 | Look.paper, .12)) : (_cellFill[_key(color, 0)] ??= mixSrgb(color, 0xff000000 | Look.paper, .08)));
        final strong = _cellEdge[_key(color, 1)] ??= mixOklab(color, 0xff000000 | Look.ink, .84);
        var edge = spot ? strong : (_cellEdge[_key(color, 0)] ??= mixOklab(color, 0xff000000 | Look.ink, .92));
        // 검색 강조에 든 칸은 테두리가 `--warn`(css `.tl-acell.is-match`).
        if (filtered && matchCells.contains(key)) edge = AxisLook.warn;
        fill = _dim(fill, dim);
        edge = _dim(edge, dim);
        final unknownStart = cell.style & AxisModel.styleStartUnknown != 0, unknownEnd = cell.style & AxisModel.styleEndUnknown != 0;
        final look = _labelLook(color, era: era, exile: cell.style & AxisModel.styleExile != 0, temporary: temporary, spot: spot);
        final full = c.text.widthOf(cell.name, look);
        if (full == null) continue;
        String text = '';
        if (era) {
          if (avg >= 4 && s.width >= full + 8) text = cell.name;
        } else if (s.width >= full + 10) {
          text = cell.name;
        } else if (cell.name.isNotEmpty) {
          final head = cell.name.substring(0, 1);
          final headWidth = c.text.widthOf(head, look);
          if (headWidth != null && s.width >= headWidth + 8) text = head;
        }
        final width = text.isEmpty ? null : (text == cell.name ? full : c.text.widthOf(text, look));
        if (text.isNotEmpty && width == null) continue;
        // 미정인 끝의 꼬리 길이는 지금 연표의 `unkCell`과 같다: 3px 아래로는 내려가지 않고, 칸 폭의 40%와
        // (글자가 있으면) 글자 양옆에 남는 자리의 절반, 없으면 폭의 30% 가운데 가장 작은 값.
        final fade = unknownStart || unknownEnd
            ? math.max(3.0, math.min(AxisLook.unknownFade, math.min(s.width * .4, width != null ? (s.width - width) / 2 : s.width * .3)))
            : 0.0;
        _box(
          c, s.l, top, s.r, bottom, AxisLook.cellRadius, fill, edge,
          roundL: !s.jl && !s.atL, roundR: !s.jr && !s.atR,
          leftEdge: s.jl ? _dim(mixSrgb(edge, edge & 0x00ffffff, .55), dim) : null, openRight: s.jr,
          dashL: temporary || unknownStart ? AxisLook.dashOn : 0, dashR: temporary || unknownEnd ? AxisLook.dashOn : 0,
          // 임시 도읍은 네 변이 모두 점선이다(css `.tl-axis .tl-ccell.is-temp { border-style: dashed }`).
          dashH: temporary,
          fadeL: unknownStart, fadeR: unknownEnd, fadeLen: fade,
          ring: spot ? _dim(strong, dim) : null,
        );
        c.stats.shapes++;
        // 이설이 있는 칸은 이름 밑에 옅은 가로 점선('이설 있음'). 고른 것이 있으면 이 표식만 .45로 흐려진다.
        if (cell.style & AxisModel.styleVariant != 0) _variantHint(c, s, top, bottom, edge);
        if (text.isEmpty) continue;
        c.later.add('axis-cell', text, look, (s.l + s.r) / 2 - width! / 2, (top + bottom) / 2 - look.size * .6, dim);
      }
    }
  }

  /// 색의 투명도를 [t]만큼 곱한다(고르기 · 흐림 · 노선도 비춤의 밝기 — `saveLayer` 없이 항목마다).
  static int _dim(int argb, double t) => t >= 1 ? argb : withAlpha(argb, ((argb >>> 24) / 255) * t);

  /// '이설 있음' 점선(`.tl-calt.is-has`): 칸 이름 밑에 1px 점 · 1 켜고 2 끔. 유령 구분선(경계마다 세로 점선)은
  /// 경계 해를 실어 오는 길이 아직 없어 못 그린다(계약 6-3의 style 32는 '있음'만 말한다).
  void _variantHint(PaintContext c, StripCell s, double top, double bottom, int edge) {
    final y = bottom - AxisLook.variantInset - 1;
    final l = s.l + 3, r = s.r - 3;
    if (r - l < 4) return;
    final color = _dim(mixSrgb(edge, edge & 0x00ffffff, .88), emphasis?.trimDim ?? 1);
    c.quads.hLine(l, r, y, color, dash: AxisLook.variantDash, gap: AxisLook.variantGap, phase: l);
    c.stats.shapes++;
  }

  TextLook _labelLook(int color, {required bool era, required bool exile, required bool temporary, bool spot = false}) {
    final key = _key(color, (era ? 0 : 1) | (exile ? 2 : 0) | (temporary ? 4 : 0) | (spot ? 8 : 0));
    // 굵기(기준 덤프): 연호 칸은 400(`.tl-acell`이 따로 적지 않아 물려받는다) · 도읍 칸은 600 · 임시 도읍은 500.
    return _cellInk[key] ??= TextLook(
      10.5, era ? ui.FontWeight.w400 : (temporary ? ui.FontWeight.w500 : ui.FontWeight.w600),
      // 고른 칸(`.is-spot`)의 글은 글자색 그대로다.
      spot ? (0xff000000 | Look.ink) : mixSrgb(color, 0xff000000 | Look.ink, .30), italic: exile, spacing: -.14,
    );
  }

  /// 배도 갈래: 도읍 줄 아래에 옅은 칸으로.
  void _secondary(PaintContext c, AxisRow row) {
    final v = c.v, w = c.w, left = c.left;
    final base = row.contentTop + row.lanes * AxisModel.capHeight + 1;
    for (final cell in row.data!.sec) {
      final a = v.xOf(cell.start), b = v.xOf(cell.end);
      if (b <= left || a >= w) continue;
      final l = a <= left ? left : a + .5, r = b >= w ? w : b - .5;
      if (r - l < 1) continue;
      final top = base + cell.lane * AxisModel.secHeight, bottom = top + AxisModel.secHeight - 3;
      final color = 0xff000000 | (cell.color == 0 ? row.track!.color : cell.color);
      final fill = _cellFill[_key(color, 2)] ??= mixSrgb(color, 0xff000000 | Look.paper, .04);
      final edgeSoft = _cellEdge[_key(color, 0)] ??= mixOklab(color, 0xff000000 | Look.ink, .92);
      final edge = mixSrgb(edgeSoft, edgeSoft & 0x00ffffff, .65);
      _box(c, l, top, r, bottom, AxisLook.secRadius, fill, edge, roundL: a > left, roundR: b < w);
      c.stats.shapes++;
      final look = _cellInk[_key(color, 16)] ??= TextLook(9.5, ui.FontWeight.w500, mixSrgb(color, 0xff000000 | Look.ink, .30), spacing: -.14);
      final width = c.text.widthOf(cell.name, look);
      if (width == null || r - l < width + 10) continue;
      c.later.add('axis-cell', cell.name, look, (l + r) / 2 - width / 2, (top + bottom) / 2 - look.size * .6);
    }
  }

  // ---- 둥근 네모 한 칸(채움 + 1px 테두리) ----

  /// 채움은 네모 묶음과 모서리 조각에, 테두리는 1px 네모와 모서리 조각에 모은다.
  /// [border]가 거짓이면 테두리가 없고(가는 막대), [leftEdge]는 이어 붙은 쪽의 옅은 구분선,
  /// [openRight]는 오른쪽으로 이어져 테두리를 두지 않는 쪽이다. [dashL] · [dashR]이 0보다 크면 그쪽 세로 테두리가 점선이고
  /// [dashH]면 위아래 테두리까지 점선이다(임시 도읍의 네 변). [fadeL] · [fadeR]은 미정인 끝 — 그쪽이 칸 안에서
  /// 종이로 스며들고, 스미는 길이는 [fadeLen](0이면 옛 어림값). [ring]을 주면 안쪽에 1.5px 고리를 한 겹 더 두른다(고른 칸).
  void _box(
    PaintContext c, double l, double t, double r, double b, double radius, int fill, int edge, {
    bool roundL = true, bool roundR = true, bool border = true, int? leftEdge, bool openRight = false,
    double dashL = 0, double dashR = 0, bool dashH = false, bool fadeL = false, bool fadeR = false, double fadeLen = 0, int? ring,
  }) {
    if (r - l < .5 || b - t < .5) return;
    const paper = Look.paper;
    final rad = AxisSprites.snap(math.min(radius, math.min((r - l) / 2, (b - t) / 2)));
    // 채움
    double bodyL = l, bodyR = r;
    if (roundL) {
      _sprites.add(AxisSprites.cornerTopLeft, l, t, rad, fill);
      _sprites.add(AxisSprites.cornerBottomLeft, l, b - rad, rad, fill);
      c.quads.add(l, t + rad, l + rad, b - rad, fill);
      bodyL = l + rad;
    }
    if (roundR) {
      _sprites.add(AxisSprites.cornerTopRight, r - rad, t, rad, fill);
      _sprites.add(AxisSprites.cornerBottomRight, r - rad, b - rad, rad, fill);
      c.quads.add(r - rad, t + rad, r, b - rad, fill);
      bodyR = r - rad;
    }
    if (bodyR > bodyL) {
      final want = fadeLen > 0 ? fadeLen : 24.0;
      final reach = math.min(want, (bodyR - bodyL) / ((fadeL && fadeR) ? 2 : 1));
      if (fadeL) c.quads.addFade(bodyL, t, bodyL + reach, b, paper, fill);
      if (fadeR) c.quads.addFade(bodyR - reach, t, bodyR, b, fill, paper);
      final mid0 = bodyL + (fadeL ? reach : 0), mid1 = bodyR - (fadeR ? reach : 0);
      if (mid1 > mid0) c.quads.add(mid0, t, mid1, b, fill);
    }
    // 테두리
    if (!border) return;
    final hl = roundL ? l + rad : l, hr = roundR ? r - rad : r;
    if (hr > hl) {
      if (dashH) {
        c.quads
          ..hLine(hl, hr, t, edge, dash: AxisLook.dashOn, gap: AxisLook.dashOff, phase: hl)
          ..hLine(hl, hr, b - 1, edge, dash: AxisLook.dashOn, gap: AxisLook.dashOff, phase: hl);
      } else {
        c.quads
          ..add(hl, t, hr, t + 1, edge)
          ..add(hl, b - 1, hr, b, edge);
      }
    }
    _vEdge(c, l, roundL ? t + rad : t, roundL ? b - rad : b, leftEdge ?? edge, dashL, dashL == AxisLook.dotOn ? AxisLook.dotOff : AxisLook.dashOff);
    if (!openRight) _vEdge(c, r - 1, roundR ? t + rad : t, roundR ? b - rad : b, edge, dashR, dashR == AxisLook.dotOn ? AxisLook.dotOff : AxisLook.dashOff);
    if (roundL) {
      _sprites.add(AxisSprites.cornerTopLeft, l, t, rad, edge, border: true);
      _sprites.add(AxisSprites.cornerBottomLeft, l, b - rad, rad, edge, border: true);
    }
    if (roundR) {
      _sprites.add(AxisSprites.cornerTopRight, r - rad, t, rad, edge, border: true);
      _sprites.add(AxisSprites.cornerBottomRight, r - rad, b - rad, rad, edge, border: true);
    }
    // 고른 칸의 안쪽 고리(css `box-shadow: inset 0 0 0 1.5px var(--edge)`) — 테두리 바로 안쪽에 0.5px 더.
    if (ring == null || r - l < 4 || b - t < 4) return;
    c.quads
      ..add(l + 1, t + 1, r - 1, t + 1.5, ring)
      ..add(l + 1, b - 1.5, r - 1, b - 1, ring)
      ..add(l + 1, t + 1, l + 1.5, b - 1, ring)
      ..add(r - 1.5, t + 1, r - 1, b - 1, ring);
  }

  static void _vEdge(PaintContext c, double x, double y0, double y1, int color, double dash, double gap) {
    if (dash <= 0) {
      c.quads.add(x, y0, x + 1, y1, color);
      return;
    }
    for (double y = y0; y < y1; y += dash + gap) {
      final end = math.min(y + dash, y1);
      if (end > y) c.quads.add(x, y, x + 1, end, color);
    }
  }
}

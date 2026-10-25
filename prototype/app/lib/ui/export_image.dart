import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../controller.dart';
import '../scene/fonts.dart';
import '../scene/glyph_atlas.dart';
import '../scene/labels.dart';
import '../scene/layout.dart';
import '../scene/lens_titles.dart';
import '../scene/levels.dart';
import '../scene/marks.dart';
import '../scene/painter.dart';
import '../scene/ruler.dart';
import '../scene/scene.dart';
import '../scene/sprites.dart';
import '../scene/text_paragraph.dart';
import '../scene/tile_cache.dart';
import '../shell/look.dart';
import '../shell/motion_controls.dart';
import '../shell/parts.dart';
import 'app_bus.dart';
import 'date_text.dart';
import 'export_svg.dart';

// 이미지로 저장(명세 06의 7-5). 지금 보고 있는 기간과 보기 조건 그대로, **모든 트랙을 한 장에** 담아 PNG로 적는다.
// 세로는 내용 높이 전체라서 화면 밖으로 밀려난 트랙도 다 들어가고, 왼쪽 칸 폭은 화면과 같다.
//
// 그리는 길: 화면의 장면을 건드리지 않게 같은 자료로 [TimelineController] · [TimelineScene] · [TimelinePainter]를 **따로** 지어
// 그 크기로 놓고, 타일 · 이름 자리 · 글자가 다 올 때까지 기다린 뒤 `ui.PictureRecorder`에 한 번 그려 `toImage` → PNG로 바꾼다
// (기다리고 그리는 절차는 `test/render_scene_test.dart`와 같다).
// 그림에는 **문턱이 하나**다(움직임 원칙 ⑨) — 새로 지은 장면이라 눈금 · 이름 · 빈 줄 접기의 이력이 비어 있고,
// 단계도 붙들림 없이 고른다. 메아리 조명도 고른 것의 강조도 싣지 않는다(새 장면은 아무것도 고르지 않은 상태다).
//
// 혼자 서는 부품이라 [AppBus]만 받는다:
//   `bus.controller.view`            — 지금 보고 있는 기간(분).
//   `bus.scene.layout`               — 켠 자료집 · 보기 조건 · 접힌 줄.
//   `bus.scene.cache.fetch`          — 타일(화면이 이미 받아 둔 것을 그대로 쓴다).
//   `bus.ask({'op':'layout'})`       — 배치의 사본(SceneLayout에 사본을 만드는 길이 없다 — 보고 참고).
//
// 인쇄도 이 그림으로 한다(아래 '인쇄' 절) — A4 가로 한 장에 여백 8mm를 두고 얹어 PNG로 적은 뒤
// 윈도의 인쇄 대화 상자로 보낸다.
//
// **SVG 저장**도 같은 장면으로 한다([buildExportSvg] · `export_svg.dart`): 똑같이 장면을 세워 다 가라앉힌 뒤,
// 그리기를 받는 쪽만 [SvgCanvas]로 바꿔 한 번 그린다. 글은 진짜 `<text>`라 SVG에서 고르고 찾을 수 있고,
// 띠 · 칸 · 선은 `<path>` · `<rect>` · `<pattern>`이다. 위 여백 · 제목 · 기간 글은 PNG와 같은 값이다.

/// 고를 수 있는 가로 크기(px)와 처음 값.
const exportWidths = <double>[1200, 1800, 2600, 3600];
const exportDefaultWidth = 1800.0;

/// 제목 칸의 길이 제한과, 제목이 있을 때 그림 위에 붙는 띠의 높이(px).
const exportTitleLimit = 60;
const exportTitleHeight = 46.0;

/// 제목이 없을 때의 위 여백과, 제목이 있든 없든 늘 두는 아래 여백(px).
/// 지금 연표의 `toSVG`와 같다 — `titleH = title ? 46 : 10` · `total = bodyTop + Σ트랙높이 + 24`(T:8806~).
const exportHeadMargin = 10.0;
const exportFootMargin = 24.0;

/// 만들 수 있는 가장 큰 그림(화소)과 그것을 넘었을 때의 글.
const exportPixelLimit = 60000000;
const exportTooBigMessage = '그림이 너무 큽니다 — 가로 크기를 줄여 주세요';

/// 파일 이름(겹치면 뒤에 번호가 붙는다). 지금 연표와 같다 — `역사연표.png` · `역사연표.svg`.
const exportFileBase = '역사연표', exportFileExtension = '.png', exportSvgExtension = '.svg';

/// 제목의 기본값 — `역사 연표 (기원전 1500년 ~ 1500년)`. [lo] · [hi]는 계약의 시간(분)이고,
/// 확대했으면 달 · 날까지 적는다(지금 연표의 `spanRange`와 같은 규칙 — `date_text.dart`).
String defaultExportTitle(double lo, double hi) => '역사 연표 (${spanRange(tOfMinutes(lo), tOfMinutes(hi))})';

/// 다 만든 그림 한 장 — PNG 바이트와 화소 크기.
@immutable
class ExportImage {
  const ExportImage(this.png, this.width, this.height);
  final Uint8List png;
  final int width, height;
}

/// 그림을 만들지 못했다. [message]는 사람에게 그대로 보이는 글이다.
@immutable
class ExportImageException implements Exception {
  const ExportImageException(this.message);
  final String message;

  @override
  String toString() => message;
}

void _guardSize(double width, double height) {
  if (width * height > exportPixelLimit) throw const ExportImageException(exportTooBigMessage);
}

/// 한 줄을 [x]에 밑줄 [baseline]로 적는다. [toRight]면 [x]가 글의 **오른쪽 끝**이다.
void _paintLine(
  ui.Canvas canvas,
  String text,
  double x,
  double baseline, {
  required double size,
  required int color,
  ui.FontWeight weight = ui.FontWeight.w400,
  double room = double.infinity,
  bool toRight = false,
}) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(fontFamily: sceneFontFamily, fontSize: size, fontWeight: weight, maxLines: 1, ellipsis: '…', textDirection: ui.TextDirection.ltr),
  )
    ..pushStyle(ui.TextStyle(color: ui.Color(color), fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, fontSize: size, fontWeight: weight))
    ..addText(text);
  final paragraph = builder.build()..layout(ui.ParagraphConstraints(width: math.max(1, room)));
  final left = toRight ? x - math.min(paragraph.maxIntrinsicWidth, room) : x;
  canvas.drawParagraph(paragraph, ui.Offset(left, baseline - paragraph.alphabeticBaseline));
}

/// 제목을 그림 왼쪽 위에 적는다(지금 연표의 `toSVG`와 같은 자리 · 크기: x 16 · 밑줄 32 · 20px · 500).
void _paintTitle(ui.Canvas canvas, String title, double width) =>
    _paintLine(canvas, title, 16, 32, size: 20, weight: ui.FontWeight.w500, color: Look.ink, room: math.max(1, width - 32));

/// 아래 여백에 지금 보는 기간을 적는다 — 지금 연표의 `toSVG`와 같은 자리 · 크기
/// (오른쪽 끝에서 8 · 밑줄은 바닥에서 8 · 11px · `--muted`).
void _paintFooter(ui.Canvas canvas, double lo, double hi, double width, double height) {
  final a = tOfMinutes(lo), b = tOfMinutes(hi), prec = precFor(b - a);
  _paintLine(
    canvas,
    '${formatT(a, prec)} ~ ${formatT(b, prec)}',
    width - 8,
    height - 8,
    size: 11,
    color: Look.muted,
    room: math.max(1, width - 16),
    toRight: true,
  );
}

/// 다 준비된 장면 한 벌 — 이 위에 PNG를 굽거나 SVG를 적는다.
class ExportFrame {
  const ExportFrame({required this.painter, required this.text, required this.width, required this.band, required this.sceneHeight, required this.height, required this.lo, required this.hi});

  /// 이 장면의 그리개(층 · 그림판 · 이름 자리가 다 준비돼 있다).
  final TimelinePainter painter;

  /// 그리개가 쓰는 글자 뒷단.
  final SceneText text;

  /// 그림의 가로(px)와 제목 띠(또는 위 여백)의 높이.
  final double width, band;

  /// 연표 그림의 높이(날짜 칸 + 내용 전체)와 그림 한 장의 높이(띠 + 연표 + 아래 여백).
  final double sceneHeight, height;

  /// 지금 보고 있는 기간(분).
  final double lo, hi;
}

/// 내보낼 장면 한 벌을 세워 타일 · 이름 자리 · 글자가 다 올 때까지 돌린 뒤 [draw]를 부르고, 끝나면 치운다.
/// [makeText]로 글자 뒷단을 갈아 끼운다 — PNG는 그림판(`AtlasText`), SVG는 `<text>`로 적는 뒷단이다.
Future<T> _withExportScene<T>(
  AppBus bus, {
  required double width,
  required String title,
  SceneText Function()? makeText,
  bool svg = false,
  required Future<T> Function(ExportFrame frame) draw,
}) async {
  final liveScene = bus.scene, liveLayout = bus.scene.layout;
  final lo = bus.controller.view.lo, hi = bus.controller.view.hi;
  final band = title.isEmpty ? exportHeadMargin : exportTitleHeight;

  // 화면이 쓰는 배치를 건드리지 않게 같은 자료로 새로 짓는다(줄 높이는 흐르지 않고 바로 제자리로).
  final layout = SceneLayout.fromJson(await bus.ask(const {'op': 'layout'}))..reduceMotion = true;
  layout.enable(liveLayout.enabledPacks.toSet());
  layout.setConditions(liveLayout.conditions);
  // 접은 트랙 · 접은 민족 · 끈 트랙 · 펼친 소속 · 켠 대범위 — 타일은 화면의 거르개 · 변형이 걸린 것이 오므로 줄도 같은 상태여야 한다.
  layout.setViewState(liveLayout.viewState);
  layout.setFolded(liveLayout.foldedRows);
  layout.finishFlow();

  // 타일은 화면의 보관이 쓰는 길을 그대로 빌린다. 판 번호를 화면의 것으로 두면 화면이 지금 켠 자료집으로 풀린다
  // (보기 조건이 같으니 자료집도 같다 — 새 장면이 건네는 packs는 그래서 쓰지 않는다).
  final packsVersion = liveLayout.version;
  var closed = false;
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(width, 1000)
    ..setExtent(bus.controller.minMinute, bus.controller.maxMinute)
    ..setContentHeight(layout.totalHeight);
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    fetchTile: (level, x, chunk, packs) async {
      final bytes = await liveScene.cache.fetch(TileKey(level, x, chunk, packsVersion));
      // 다 그린 뒤에 도착한 타일은 받아 넣지 않는다 — 치운 장면에 '다시 그려라'가 가지 않게.
      if (closed) throw StateError('내보내기가 끝났습니다');
      return bytes;
    },
    ask: bus.ask,
    // 이름 자리는 이 자리에서 바로 셈한다(작업자를 하나 더 띄우지 않는다 — 셈하는 식은 화면과 같다).
    labelCompute: (input) async => placeLabels(input),
  );
  // 그리기만 바꾸는 표시 값은 장면 **곁에** 매달려 있어 새 장면에 따라오지 않는다 — 화면과 같게 옮겨 적는다
  // (지금 연표의 toSVG도 `alt: this.showAlt && !this._bird`로 화면과 같이 끈다 — js:8841 · 8964 · 11물결 bands3 ㈒).
  // 읽는 층: hangs · figures · rails · strips · axis.
  final liveMarks = SceneMarks.of(liveScene);
  SceneMarks.of(scene)
    ..showAlt = liveMarks.showAlt
    ..showHouses = liveMarks.showHouses
    ..leaderLabel = liveMarks.leaderLabel
    ..leaderOrdinal = liveMarks.leaderOrdinal
    ..lens = liveMarks.lens
    ..showGanji = liveMarks.showGanji
    ..showEras = liveMarks.showEras
    ..showCapitals = liveMarks.showCapitals
    ..showEpochs = liveMarks.showEpochs
    ..version += 1;
  // 관점의 이름도 같은 장면 곁의 값이다 — 화면이 받아 둔 것을 그대로 쓴다.
  final liveLens = LensTitles.of(liveScene);
  if (!liveLens.isEmpty) LensTitles.of(scene).put(events: liveLens.events, bands: liveLens.bands);
  final text = (makeText?.call() ?? AtlasText())
    ..maxNewPerFrame = 4000
    ..budgetMicros = 2000000;
  // 조각 그림판은 온 앱이 함께 쓴다 — 화면이 쓰던 배율을 그대로 두어 내보내기가 그것을 다시 뜨지 않게 한다.
  // SVG로 적을 때는 그리개가 제 묶음도 SVG 묶음으로 짓게 한다 — 그러지 않으면 층이 사사로이 들고 있는 묶음
  // (기간 막대가 연대 폭 빗금 위에 덮어 그리는 `RailLayer._overlay`)이 `drawVertices`로 나가 SVG에서만 그림이 빠진다(11물결 svg ㈎).
  final painter = TimelinePainter(
    scene,
    text: text,
    quads: svg ? SvgQuads.new : null,
    lines: svg ? SvgLines.new : null,
    patterns: svg ? SvgPatterns.new : null,
    clearType: false, // 그림 저장은 늘 회색 — ClearType의 색 테두리가 다른 화면에서 지저분하다(검토 초점 5)
  )..devicePixelRatio = Sprites.shared.scale;

  try {
    controller.showRange(lo, hi);
    scene.level = levelFor(controller.view.ppm);

    // 타일 · 이름 자리 · 글자가 모두 준비될 때까지 그려 본다. 빈 줄 접기로 내용 높이가 달라지면 그만큼 창을 키워 다시 기다린다.
    double body = -1, head = -1;
    int calm = 0;
    for (int i = 0; i < 600 && calm < 4; i++) {
      final wanted = math.max(layout.totalHeight, 1.0);
      if (wanted != body || controller.view.head != head) {
        body = wanted;
        head = controller.view.head;
        _guardSize(width, band + head + body + exportFootMargin);
        controller
          ..setContentHeight(body)
          ..resize(width, head + body)
          ..showRange(lo, hi)
          ..scrollTo(0);
        scene.level = levelFor(controller.view.ppm);
        calm = 0;
      }
      final probe = ui.PictureRecorder();
      painter.paint(ui.Canvas(probe), ui.Size(width, head + body));
      probe.endRecording().dispose();
      await Future<void>.delayed(const Duration(milliseconds: 25));
      scene.tick(25);
      final stats = scene.stats, labels = scene.labelOutput;
      final settled = stats.blanks == 0 &&
          stats.covers == 0 &&
          !scene.fading &&
          labels != null &&
          labels.deferred == 0 &&
          !text.starved &&
          !scene.labelWorker.busy &&
          !painter.gutter.rowLabels.pending &&
          scene.settled;
      calm = settled ? calm + 1 : 0;
    }

    head = controller.view.head;
    body = math.max(layout.totalHeight, 1.0);
    final sceneHeight = head + body, height = band + sceneHeight + exportFootMargin;
    _guardSize(width, height);

    return await draw(ExportFrame(painter: painter, text: text, width: width, band: band, sceneHeight: sceneHeight, height: height, lo: lo, hi: hi));
  } finally {
    // 치우기 전에 한 번 쉰다: 미뤄 둔 알림(날짜 칸 높이 · 방금 도착한 타일 · 막 끝난 이름 자리)이 장면이 살아 있는 동안 지나가게.
    closed = true;
    scene.cache.want(const [], const []);
    await Future<void>.delayed(Duration.zero);
    scene.dispose();
    text.dispose();
    controller.dispose();
  }
}

/// 그림 한 장을 만들어 [ui.Image] 그대로 돌려준다 — 부른 쪽이 `dispose`한다.
/// PNG로 적을 때는 [buildExportImage], 인쇄 종이에 얹을 때는 [buildPrintSheet]가 쓴다.
Future<ui.Image> _renderExport(AppBus bus, {required double width, required String title}) =>
    _withExportScene(bus, width: width, title: title, draw: (f) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(ui.Rect.fromLTWH(0, 0, width, f.height), ui.Paint()..color = const ui.Color(Look.paper));
      if (title.isNotEmpty) _paintTitle(canvas, title, width);
      _paintFooter(canvas, f.lo, f.hi, width, f.height);
      canvas.save();
      canvas.translate(0, f.band);
      canvas.clipRect(ui.Rect.fromLTWH(0, 0, width, f.sceneHeight));
      f.painter.paint(canvas, ui.Size(width, f.sceneHeight));
      canvas.restore();
      final picture = recorder.endRecording();
      final image = await picture.toImage(width.round(), f.height.ceil());
      picture.dispose();
      return image;
    });

/// 그림 한 장을 만들어 PNG로 돌려준다. [width]는 고른 가로 크기(px), [title]이 비어 있으면 위의 제목 띠가 없다.
/// 너무 크면 [ExportImageException]([exportTooBigMessage])으로 막는다.
Future<ExportImage> buildExportImage(AppBus bus, {required double width, String title = ''}) async {
  final image = await _renderExport(bus, width: width, title: title);
  try {
    return ExportImage(await _png(image), image.width, image.height);
  } finally {
    image.dispose();
  }
}

// ─────────────────────────────── SVG로 저장(명세 06의 7-5) ───────────────────────────────

/// 지금 보기를 SVG 한 장으로 적는다. PNG와 **같은 장면 · 같은 여백 · 같은 제목 · 같은 기간 글**이고,
/// 글만 진짜 `<text>`라 SVG에서 고르고 찾을 수 있다(지금 연표의 `toSVG`와 같음).
Future<ExportSvg> buildExportSvg(AppBus bus, {required double width, String title = ''}) => _withExportScene(
  bus,
  width: width,
  title: title,
  // 폭 재기는 PNG와 같은 뒷단(그림판)에 맡긴다 — 이름 자리가 PNG와 한 픽셀도 다르지 않게.
  makeText: () => SvgText(inner: AtlasText()),
  svg: true,
  draw: (f) async {
    final canvas = SvgCanvas(width: f.width, height: f.height);
    canvas.save();
    canvas.translate(0, f.band);
    canvas.clipRect(ui.Rect.fromLTWH(0, 0, f.width, f.sceneHeight));
    paintSceneToSvg(
      f.painter,
      canvas,
      ui.Size(f.width, f.sceneHeight),
      text: f.text as SvgText,
      quads: SvgQuads(),
      dividers: SvgLines(Look.line),
      patterns: SvgPatterns(),
      ruler: Ruler(),
    );
    canvas.restore();
    final head = StringBuffer('<rect x="0" y="0" width="${svgNum(f.width)}" height="${svgNum(f.height)}" fill="${svgHex(Look.paper)}"/>');
    // 제목 · 기간 글은 PNG(_paintTitle · _paintFooter)와 같은 자리 · 크기다. `<text>`의 y는 글의 밑줄이다.
    if (title.isNotEmpty) {
      head.write('<text x="16" y="32" font-size="20" font-weight="500" fill="${svgHex(Look.ink)}">${svgEscape(title)}</text>');
    }
    final a = tOfMinutes(f.lo), b = tOfMinutes(f.hi), prec = precFor(b - a);
    head.write(
      '<text x="${svgNum(f.width - 8)}" y="${svgNum(f.height - 8)}" font-size="11" font-weight="400" text-anchor="end" fill="${svgHex(Look.muted)}">'
      '${svgEscape('${formatT(a, prec)} ~ ${formatT(b, prec)}')}</text>',
    );
    final stats = f.painter.scene.stats;
    return ExportSvg(
      await canvas.toSvg(head: head.toString()),
      texts: canvas.texts,
      elements: canvas.elements,
      shapes: stats.shapes,
      labels: stats.labels,
      skipped: Map.of(canvas.skipped),
    );
  },
);

/// SVG를 만들어 파일로 적고, 적은 곳의 경로와 **만든 것 그대로**([ExportSvg])를 돌려준다. [folder]를 주면 그리로(검사).
///
/// 옮기지 못한 그리기([ExportSvg.skipped])를 여기서 버리지 않는다 — 버리면 그림 일부가 파일에서 조용히 빠진 채
/// 사람에게는 '저장했습니다'만 보인다. 부른 쪽이 그 수를 보고 알릴 수 있게 그대로 넘긴다([savedSvgNote]).
Future<({String path, ExportSvg made})> saveExportSvg(AppBus bus, {required double width, String title = '', Directory? folder}) async {
  final made = await buildExportSvg(bus, width: width, title: title);
  final dir = folder ?? await exportFolder();
  dir.createSync(recursive: true);
  final file = exportTargetFile(dir, extension: exportSvgExtension)..writeAsStringSync(made.svg);
  return (path: file.path, made: made);
}

/// SVG를 적은 뒤 사람에게 보일 글. 옮기지 못한 그리기가 하나라도 있으면 몇 건인지 뒤에 덧붙인다 —
/// 그리개에 새 그리기가 붙어 SVG에서만 빠지는 날, 검사가 아니라 **저장한 그 자리에서** 드러나게.
String savedSvgNote(String path, ExportSvg made) {
  final lost = made.skipped.values.fold(0, (sum, n) => sum + n);
  return lost == 0 ? '저장했습니다 — $path' : '저장했습니다 — $path (옮기지 못한 그리기 $lost건)';
}

/// 그린 것을 PNG 바이트로.
Future<Uint8List> _png(ui.Image image) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) throw const ExportImageException('그림을 만들지 못했습니다.');
  return bytes.buffer.asUint8List();
}

// ─────────────────────────────── 인쇄(명세 06의 7-5) ───────────────────────────────
//
// 지금 연표는 SVG를 `@page{size:A4 landscape;margin:8mm}`인 쪽에 얹어 브라우저에게 인쇄를 맡긴다(viewer.js:3416~3423).
// 새 앱에는 그런 인쇄 층이 없고 새 꾸러미도 넣지 않으므로, **종이를 그림 안에 그린다**:
// 만든 그림을 A4 가로(297×210mm) 비율의 흰 종이 한 장 가운데, 사방 8mm 여백 안에 담아 PNG로 적은 뒤
// 윈도의 인쇄 대화 상자(`Start-Process -Verb Print`)로 보낸다. 사진 인쇄가 '페이지에 맞춤'으로 찍으면
// 종이의 비율이 A4 가로 그대로라 여백도 8mm 그대로 나온다.

/// A4 가로 한 장의 치수와 사방 여백(mm).
const a4LongMm = 297.0, a4ShortMm = 210.0, printMarginMm = 8.0;

/// 인쇄 종이의 가장 큰 가로 화소 — A4 가로를 300dpi로 뜬 값. 종이가 이보다 커지면 그림을 줄여 담는다
/// (더 키워야 선명해지는 것이 아니라 파일만 커진다).
const printSheetMaxWidth = 3508.0;

/// 인쇄할 파일의 이름.
const printFileBase = '역사연표-인쇄';

/// A4 가로 한 장에 [w]×[h]인 그림을 담을 때의 종이 크기와 그림이 앉을 자리.
/// 종이 크기를 그림에 맞춰 정하므로 **늘려 그리는 일이 없다**(글자가 흐려지지 않는다).
/// 세로로 아주 긴 그림이라 종이가 [printSheetMaxWidth]를 넘으면 그때만 줄인다.
({double sheetWidth, double sheetHeight, ui.Rect at}) printSheetLayout(double w, double h) {
  const boxLongMm = a4LongMm - 2 * printMarginMm, boxShortMm = a4ShortMm - 2 * printMarginMm;
  var sheetWidth = math.max(w * a4LongMm / boxLongMm, h * a4LongMm / boxShortMm);
  var scale = 1.0;
  if (sheetWidth > printSheetMaxWidth) {
    scale = printSheetMaxWidth / sheetWidth;
    sheetWidth = printSheetMaxWidth;
  }
  final sheetHeight = sheetWidth * a4ShortMm / a4LongMm;
  final boxLeft = sheetWidth * printMarginMm / a4LongMm, boxTop = sheetHeight * printMarginMm / a4ShortMm;
  final boxWidth = sheetWidth - 2 * boxLeft, boxHeight = sheetHeight - 2 * boxTop;
  final dw = w * scale, dh = h * scale;
  return (
    sheetWidth: sheetWidth,
    sheetHeight: sheetHeight,
    at: ui.Rect.fromLTWH(boxLeft + (boxWidth - dw) / 2, boxTop + (boxHeight - dh) / 2, dw, dh),
  );
}

/// 인쇄할 종이 한 장 — [sheet]와, 그림이 **인쇄 폭에서 차지하는 만큼**([fill] · 1이면 여백 안을 꽉 채웠다).
/// 세로로 긴 연표는 한 장에 담느라 가운데 가는 띠가 되므로, 대화 상자가 그 값을 사람에게 알린다.
typedef PrintSheet = ({ExportImage sheet, double fill});

/// 인쇄할 종이 한 장(A4 가로 · 여백 8mm)을 PNG로 만든다.
Future<PrintSheet> buildPrintSheet(AppBus bus, {required double width, String title = ''}) async {
  final image = await _renderExport(bus, width: width, title: title);
  try {
    final plan = printSheetLayout(image.width.toDouble(), image.height.toDouble());
    final sheetWidth = plan.sheetWidth.ceil(), sheetHeight = plan.sheetHeight.ceil();
    _guardSize(sheetWidth.toDouble(), sheetHeight.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // 여백은 흰 종이다(지금 연표도 `@page`의 여백에는 아무것도 찍지 않는다) — 그림의 종이빛은 그림 안에만.
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, sheetWidth.toDouble(), sheetHeight.toDouble()), ui.Paint()..color = const ui.Color(0xffffffff));
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      plan.at,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final sheet = await picture.toImage(sheetWidth, sheetHeight);
    picture.dispose();
    try {
      final boxWidth = plan.sheetWidth * (a4LongMm - 2 * printMarginMm) / a4LongMm;
      return (sheet: ExportImage(await _png(sheet), sheetWidth, sheetHeight), fill: plan.at.width / boxWidth);
    } finally {
      sheet.dispose();
    }
  } finally {
    image.dispose();
  }
}

/// 만든 파일을 인쇄로 보내는 길. 검사에서 갈아 끼우는 자리다([printExportImage] · [ExportDialog]의 `printFile`).
typedef PrintFile = Future<void> Function(String path);

/// 기본 인쇄 길 — 윈도의 인쇄 대화 상자를 띄운다. 띄우지 못하면 까닭을 [ExportImageException]으로 올린다
/// (대화 상자가 그 글을 그대로 보여 준다).
Future<void> printFileWithShell(String path) async {
  if (!Platform.isWindows) {
    throw const ExportImageException('이 컴퓨터에서는 인쇄 대화 상자를 띄울 수 없습니다 — 그림으로 저장해 인쇄해 주세요.');
  }
  final quoted = path.replaceAll("'", "''"); // PowerShell의 작은따옴표는 겹쳐 쓴다
  try {
    final process = await Process.start('powershell', ['-NoProfile', '-Command', "Start-Process -FilePath '$quoted' -Verb Print"]);
    final out = process.stdout.transform(systemEncoding.decoder).join(); // 받지 않으면 powershell이 멎는다
    final reason = await process.stderr.transform(systemEncoding.decoder).join();
    // `Start-Process`는 대화 상자를 띄우고 바로 끝난다. 그래도 끝나지 않으면 띄운 것으로 본다.
    final code = await process.exitCode.timeout(const Duration(seconds: 30), onTimeout: () => 0);
    await out;
    if (code != 0) {
      final first = reason.split('\n').map((s) => s.trim()).firstWhere((s) => s.isNotEmpty, orElse: () => '오류 $code');
      throw ExportImageException('인쇄 대화 상자를 띄우지 못했습니다 — $first');
    }
  } on ExportImageException {
    rethrow;
  } on Object catch (e) {
    throw ExportImageException('인쇄 대화 상자를 띄우지 못했습니다 — $e');
  }
}

/// 인쇄할 그림을 두는 임시 폴더. **한 시간이 지난** 지난번 것만 지운다 —
/// 방금 보낸 파일은 인쇄가 아직 읽고 있을 수 있다(지우지 못하면 그냥 두고 다음 이름으로 적는다).
Directory printFolder() {
  final folder = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}ht-timeline-print');
  folder.createSync(recursive: true);
  final stale = DateTime.now().subtract(const Duration(hours: 1));
  for (final old in folder.listSync()) {
    try {
      if (old.statSync().modified.isBefore(stale)) old.deleteSync();
    } on Object {
      // 인쇄가 붙들고 있거나 벌써 없는 파일이다.
    }
  }
  return folder;
}

/// 지금 보기를 A4 가로 한 장으로 만들어 인쇄 대화 상자로 보낸다.
/// 적은 파일의 경로와, 그림이 인쇄 폭에서 차지하는 만큼([PrintSheet]의 `fill`)을 돌려준다.
/// [folder] · [printFile]을 주면 그리로(검사).
Future<({String path, double fill})> printExportImage(
  AppBus bus, {
  required double width,
  String title = '',
  Directory? folder,
  PrintFile printFile = printFileWithShell,
}) async {
  final made = await buildPrintSheet(bus, width: width, title: title);
  final dir = folder ?? printFolder();
  dir.createSync(recursive: true);
  final file = exportTargetFile(dir, base: printFileBase)..writeAsBytesSync(made.sheet.png);
  await printFile(file.path);
  return (path: file.path, fill: made.fill);
}

/// 그림을 적을 폴더 — 내려받기 폴더, 모르면 문서 폴더.
Future<Directory> exportFolder() async {
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null && downloads.existsSync()) return downloads;
  } on Object {
    // 내려받기 폴더를 모르는 환경이다 — 문서 폴더로 간다.
  }
  return getApplicationDocumentsDirectory();
}

/// 덮어쓰지 않는 이름을 고른다: `역사연표.png` · `역사연표 (2).png` · `역사연표 (3).png` …
File exportTargetFile(Directory folder, {String base = exportFileBase, String extension = exportFileExtension}) {
  final sep = Platform.pathSeparator;
  var file = File('${folder.path}$sep$base$extension');
  for (int n = 2; file.existsSync() && n <= 9999; n++) {
    file = File('${folder.path}$sep$base ($n)$extension');
  }
  return file;
}

/// 그림을 만들어 파일로 적고, 적은 곳의 경로를 돌려준다. [folder]를 주면 그리로(검사).
Future<String> saveExportImage(AppBus bus, {required double width, String title = '', Directory? folder}) async {
  final image = await buildExportImage(bus, width: width, title: title);
  final dir = folder ?? await exportFolder();
  dir.createSync(recursive: true);
  final file = exportTargetFile(dir)..writeAsBytesSync(image.png);
  return file.path;
}

/// 이미지 · 인쇄 대화 상자를 연다(`📷` 단추 · `P`).
Future<void> showExportDialog(BuildContext context, AppBus bus) => showDialog<void>(
  context: context,
  barrierColor: Ui.ink20,
  builder: (_) => ExportDialog(bus: bus),
);

/// 대화 상자의 알맹이. 혼자 띄워 볼 수 있게 밖으로 내놓는다(검사).
/// [printFile]은 만든 종이를 인쇄로 보내는 길이다 — 검사에서 갈아 끼운다.
class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key, required this.bus, this.printFile = printFileWithShell});
  final AppBus bus;
  final PrintFile printFile;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  late final TextEditingController _title = TextEditingController(
    text: defaultExportTitle(widget.bus.controller.view.lo, widget.bus.controller.view.hi),
  );
  double _width = exportDefaultWidth;
  bool _working = false, _failed = false;
  String _note = '';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() => _run('그림을 만들고 있습니다…', '그림을 저장하지 못했습니다.', () async {
    return '저장했습니다 — ${await saveExportImage(widget.bus, width: _width, title: _title.text.trim())}';
  });

  Future<void> _saveSvg() => _run('SVG를 만들고 있습니다…', 'SVG를 저장하지 못했습니다.', () async {
    final done = await saveExportSvg(widget.bus, width: _width, title: _title.text.trim());
    // 옮기지 못한 그리기가 있으면 그 수까지 알린다 — 그림이 조용히 빠진 채 '저장했습니다'만 보이지 않게.
    return savedSvgNote(done.path, done.made);
  });

  Future<void> _print() => _run('인쇄할 그림을 만들고 있습니다…', '인쇄하지 못했습니다.', () async {
    final done = await printExportImage(widget.bus, width: _width, title: _title.text.trim(), printFile: widget.printFile);
    // 세로로 긴 연표는 한 장에 담느라 많이 줄어든다 — 얼마나 줄었는지와 넓히는 길을 함께 알린다.
    return done.fill >= .9
        ? '인쇄 대화 상자를 띄웠습니다 — A4 가로 한 장(여백 8mm)입니다.'
        : '인쇄 대화 상자를 띄웠습니다 — 세로가 길어 한 장에 담으니 인쇄 폭의 ${(done.fill * 100).round()}%입니다. '
              '트랙을 접거나(A) 보는 기간을 좁히면 커집니다.';
  });

  /// 오래 걸리는 일 하나 — 하는 동안 단추를 잠그고, 끝나면 아래 글에 결과나 까닭을 적는다.
  Future<void> _run(String doing, String failure, Future<String> Function() work) async {
    setState(() {
      _working = true;
      _failed = false;
      _note = doing;
    });
    String note;
    bool failed = false;
    try {
      note = await work();
    } on ExportImageException catch (e) {
      note = e.message;
      failed = true;
    } on Object {
      note = failure;
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      _failed = failed;
      _note = note;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width;
    return Dialog(
      backgroundColor: Ui.surface,
      surfaceTintColor: const Color(0x00000000),
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ui.menuRadius), side: const BorderSide(color: Ui.line)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: math.min(720, math.max(320, wide - 24))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 좁고 낮은 창에서는 단추 줄이 두 줄이 되어 대화 상자가 창보다 높아질 수 있다 —
            // 머리와 알맹이만 굴러가게 하고 단추 줄은 늘 보이게 둔다.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('이미지 · 인쇄', style: TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -.38, color: Ui.text)),
                          ),
                          ShellButton(tooltip: '닫기', onPressed: () => Navigator.of(context).pop(), width: 32, padding: EdgeInsets.zero, child: const Text('✕')),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '지금 보고 있는 시기와 보기 조건 그대로, 모든 트랙을 한 장에 담아 그림으로 만듭니다.\n'
                            '인쇄는 그 그림을 A4 가로 한 장(사방 여백 8mm)에 담아 보냅니다.',
                            style: TextStyle(fontSize: 13.5, height: 1.6, color: Ui.text2),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 200, child: _field('가로 크기', _widthPicker())),
                              const SizedBox(width: 16),
                              Expanded(child: _field('제목', _titleBox(), hint: '(그림 위에 적힙니다)')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: Ui.surface,
                border: Border(top: BorderSide(color: Ui.line)),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(Ui.menuRadius)),
              ),
              child: Padding(padding: const EdgeInsets.fromLTRB(22, 14, 22, 14), child: LayoutBuilder(builder: _foot)),
            ),
          ],
        ),
      ),
    );
  }

  /// 대화 상자의 아래 줄. 지금 연표와 같은 차례로 인쇄는 맨 왼쪽 · SVG 저장 · PNG 저장 차례로 맨 오른쪽(index.html:167~172).
  /// 좁은 창에서는 한 줄에 다 서지 못하므로 글을 단추 줄 위로 내린다.
  Widget _foot(BuildContext context, BoxConstraints box) {
    final note = Text(
      _note,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12.5, height: 1.5, color: _failed ? Ui.ink : Ui.text3),
    );
    final print = _Button(label: '인쇄', onPressed: _working ? null : _print);
    final close = _Button(label: '닫기', onPressed: _working ? null : () => Navigator.of(context).pop());
    final svg = _Button(label: 'SVG 저장', onPressed: _working ? null : _saveSvg);
    final save = _Button(label: 'PNG 저장', primary: true, onPressed: _working ? null : _save);
    if (box.maxWidth < 420) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          note,
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [print, close, svg, save]),
        ],
      );
    }
    return Row(
      children: [
        print,
        const SizedBox(width: 12),
        Expanded(child: note),
        const SizedBox(width: 12),
        close,
        const SizedBox(width: 8),
        svg,
        const SizedBox(width: 8),
        save,
      ],
    );
  }

  Widget _field(String name, Widget child, {String? hint}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text.rich(
        TextSpan(
          text: name,
          children: hint == null ? null : [TextSpan(text: ' $hint', style: const TextStyle(fontWeight: FontWeight.w400, color: Ui.text3))],
        ),
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Ui.text2),
      ),
      const SizedBox(height: 6),
      child,
    ],
  );

  Widget _box({required Widget child}) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(color: Ui.surface, borderRadius: BorderRadius.circular(Ui.controlRadius), border: Border.all(color: Ui.lineStrong)),
    child: child,
  );

  Widget _widthPicker() => MotionSegmented<double>(
    value: _width,
    options: [for (final width in exportWidths) MotionChoice(width, '${width.round()}px${_widthNote(width)}')],
    onChanged: _working ? null : (value) => setState(() => _width = value),
    label: '그림 너비',
  );

  static String _widthNote(double w) => w == 2600 ? ' (고화질)' : (w == 3600 ? ' (인쇄용)' : '');

  Widget _titleBox() => _box(
    child: TextField(
      controller: _title,
      enabled: !_working,
      maxLines: 1,
      style: const TextStyle(fontSize: 13, color: Ui.text),
      inputFormatters: [LengthLimitingTextInputFormatter(exportTitleLimit)],
      decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true, counterText: ''),
    ),
  );
}

/// 대화 상자의 아래 단추 — 지금 연표의 `.btn` · `.btn-primary`.
class _Button extends StatefulWidget {
  const _Button({required this.label, this.onPressed, this.primary = false});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final off = widget.onPressed == null;
    // 으뜸 단추는 반전 채움, 나머지는 채움 없이 ink20 선(올리면 ink8).
    final background = widget.primary ? Ui.ink : (_hover ? Ui.ink8 : null);
    return Opacity(
      opacity: off ? .45 : 1,
      child: MouseRegion(
        cursor: off ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Ui.controlRadius)),
            foregroundDecoration: widget.primary ? null : BoxDecoration(borderRadius: BorderRadius.circular(Ui.controlRadius), border: Border.all(color: Ui.ink20)),
            child: Text(
              widget.label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: widget.primary ? Ui.paper : Ui.text),
            ),
          ),
        ),
      ),
    );
  }
}

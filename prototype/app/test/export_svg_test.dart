import 'load_app_fonts.dart';

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/context.dart';
import 'package:archive_prototype/scene/paint/patterns.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/ruler.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/date_text.dart';
import 'package:archive_prototype/ui/export_image.dart';
import 'package:archive_prototype/ui/export_svg.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// SVG로 저장(명세 06의 7-5 · 대조표 기능-11): 받는 쪽만 바꾼 화폭([SvgCanvas]) · 네모 · 무늬 · 조각의 묶음 ·
// 진짜 `<text>`로 적는 글자 뒷단 · PNG와 같은 여백과 제목 · 넘긴 그리기 호출이 없는지 ·
// 그리개와 **같은 글줄을 같은 자리에** 적는지(진짜 엔진 · 진짜 저장소).

const _rowHeight = 142.0;
const _m = 1000000.0;
final _ppm = 32 / bucketMinutes(9);
double _px(double pixels) => pixels / _ppm;

Map<String, dynamic> _rowJson(int id) => {
  'id': id, 'height': _rowHeight, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

Map<String, dynamic> _layoutJson(int tracks, int rows) => {
  'packs': [
    {'id': 1, 'name': '별여울 기록집', 'events': tracks * rows},
  ],
  'tracks': [
    for (int t = 0; t < tracks; t++)
      {
        'id': t + 1, 'pack': 1, 'ord': t, 'name': '갈래 ${t + 1}',
        'rows': [for (int r = 0; r < rows; r++) _rowJson(t * rows + r)],
      },
  ],
  'epochs': const [],
};

/// 검사용 앱 길(export_image_test와 같은 것): 트랙 [tracks]개 × 줄 [rows]줄.
({AppBus bus, TimelineController controller, TimelineScene scene}) makeBus({int tracks = 2, int rows = 2}) {
  final json = _layoutJson(tracks, rows);
  final count = tracks * rows;
  Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async => switch (query['op']) {
    'layout' => json,
    'rows_near' => {'near': [for (int r = 0; r < count; r++) r], 'far': const <int>[]},
    'row_labels' => {
      'labels': [for (final r in query['rows'] as List) {'row': r, 'items': const []}],
    },
    _ => const <String, dynamic>{},
  };

  final layout = SceneLayout.fromJson(json);
  final controller = TimelineController()
    ..resize(1920, 560)
    ..setExtent(-2000 * _m, 2000 * _m)
    ..setContentHeight(layout.totalHeight);
  final origin = tileOrigin(9, 1).toDouble();
  controller.showRange(origin, origin + (1920 - SceneView.gutter) / _ppm);
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    fetchTile: (level, x, chunk, packs) async {
      final tile = TileBuilder(level: level, x: x, chunk: chunk);
      for (int r = chunk * chunkRows; r < (chunk + 1) * chunkRows && r < count; r++) {
        tile
          ..band(100 + r, r, _px(40), _px(1500), '나라 $r')
          ..event(10 + r, r, _px(200 + r * 30), '별여울의 기록 $r');
      }
      return tile.build();
    },
    labelCompute: (input) async => placeLabels(input),
    ask: ask,
  );
  return (bus: AppBus(ask: ask, controller: controller, scene: scene), controller: controller, scene: scene);
}

/// SVG 안의 `<text …>글</text>`을 (글, x, y)로 훑는다.
final _textRe = RegExp(r'<text ([^>]*)>([^<]*)</text>');
final _attrRe = RegExp(r'([-a-zA-Z:]+)="([^"]*)"');
List<(String, double, double)> svgTexts(String svg) => [
  for (final m in _textRe.allMatches(svg))
    () {
      final at = {for (final a in _attrRe.allMatches(m.group(1)!)) a.group(1)!: a.group(2)!};
      return (m.group(2)!.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>'), double.parse(at['x']!), double.parse(at['y']!));
    }(),
];

int countOf(String svg, String needle) => needle.allMatches(svg).length;

Future<void> loadFonts() async {
  await loadAppFonts();
  for (final (family, files) in [
    ('Noto Sans KR', ['C:/Windows/Fonts/NotoSansKR-VF.ttf']),
    ('Malgun Gothic', ['C:/Windows/Fonts/malgun.ttf', 'C:/Windows/Fonts/malgunbd.ttf']),
  ]) {
    final loader = FontLoader(family);
    var any = false;
    for (final path in files) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length)));
      any = true;
    }
    if (any) await loader.load();
  }
}

void main() {
  group('SvgCanvas — 받는 쪽', () {
    test('자리 바꾸기를 펴서 뿌리 좌표로 적는다', () async {
      final canvas = SvgCanvas(width: 100, height: 100);
      canvas.save();
      canvas.translate(10, 20);
      canvas.scale(2);
      canvas.drawRect(const ui.Rect.fromLTWH(1, 2, 3, 4), ui.Paint()..color = const ui.Color(0xff112233));
      canvas.restore();
      final svg = await canvas.toSvg();
      expect(svg, contains('<rect x="12" y="24" width="6" height="8" fill="#112233"/>'));
    });

    test('자르기는 무리로 감싸고 restore에서 닫는다', () async {
      final canvas = SvgCanvas(width: 100, height: 100);
      canvas.save();
      canvas.clipRect(const ui.Rect.fromLTRB(5, 6, 50, 60));
      canvas.drawCircle(const ui.Offset(10, 10), 3, ui.Paint()..color = const ui.Color(0xff000000));
      canvas.restore();
      canvas.drawCircle(const ui.Offset(80, 80), 3, ui.Paint()..color = const ui.Color(0xff000000));
      final svg = await canvas.toSvg();
      expect(svg, contains('<clipPath id="h0"><rect x="5" y="6" width="45" height="54"/></clipPath>'));
      expect(countOf(svg, '<g clip-path='), 1);
      expect(countOf(svg, '</g>'), 1);
      expect(svg.indexOf('</g>'), lessThan(svg.lastIndexOf('<circle')), reason: '무리 밖의 동그라미는 잘리지 않는다');
    });

    test('같은 색 네모는 <path> 하나로 모으고, 꼭짓점 색이 다르면 그 칸만 번짐으로', () async {
      final canvas = SvgCanvas(width: 100, height: 100);
      final quads = SvgQuads()
        ..add(0, 0, 10, 10, 0xff445566)
        ..add(20, 0, 30, 10, 0xff445566)
        ..addFade(40, 0, 60, 10, 0xff445566, 0x00445566)
        ..add(70, 0, 80, 10, 0xffaabbcc);
      quads.flush(canvas);
      final svg = await canvas.toSvg();
      expect(countOf(svg, '<path '), 2, reason: '같은 색이 이어진 둘 + 뒤의 하나');
      expect(svg, contains('M0 0H10V10H0ZM20 0H30V10H20Z'));
      expect(countOf(svg, '<linearGradient '), 1);
      expect(svg, contains('stop-opacity="0"'));
      expect(quads.count, 0, reason: '내보내면 비운다');
    });

    test('가는 선은 1px 네모로 모은다', () async {
      final canvas = SvgCanvas(width: 100, height: 100);
      final lines = SvgLines(0xffebe2d2)
        ..add(4.7, 0, 4.7, 30)
        ..add(0, 9.2, 50, 9.2);
      lines.flush(canvas);
      final svg = await canvas.toSvg();
      expect(svg, contains('M4 0H5V30H4ZM0 9H50V10H0Z'));
      expect(svg, contains('fill="#ebe2d2"'));
    });

    test('무늬는 <pattern>으로 — 줄 굵기 · 주기 · 시작 자리가 그대로', () async {
      final canvas = SvgCanvas(width: 100, height: 100);
      final patterns = SvgPatterns()
        ..add(const PatternSpec.stripes(90, 1.5, 4), 10, 10, 50, 40, 0xff806040, phaseX: 2, phaseY: 0)
        ..add(const PatternSpec.dots(6, 1.2), 60, 10, 90, 40, 0x80112233);
      patterns.flush(canvas);
      final svg = await canvas.toSvg();
      expect(svg, contains('<pattern id="h0" patternUnits="userSpaceOnUse" width="4" height="4" patternTransform="translate(2 0) scale(1)">'));
      expect(svg, contains('<rect x="0" y="0" width="1.5" height="4" fill="#806040"/>'));
      expect(svg, contains('<circle cx="3" cy="3" r="1.2" fill="#112233" fill-opacity="0.5"/>'));
      expect(countOf(svg, 'fill="url(#h'), 2);
    });

    test("화소 계단(정통성 '주장' — PatternSpec.stairs)은 기운 줄이 아니라 n칸 한 장에 왼쪽 아래 → 오른쪽 위로 오르는 1px 칸", () async {
      final canvas = SvgCanvas(width: 100, height: 100);
      final patterns = SvgPatterns()
        ..add(const PatternSpec.stairs(5), 10, 10, 50, 40, 0x40262626, phaseX: 3, phaseY: 1)
        // 같은 각 · 굵기 · 주기의 기운 줄(stairs의 angle 45 · line 1 · period 5와 같은 값) — 열쇠가 갈려 따로 선다.
        ..add(const PatternSpec.stripes(45, 1, 5), 60, 10, 90, 40, 0x40262626, phaseX: 3, phaseY: 1);
      expect(patterns.tileOf(0), 5, reason: '한 장 = 주기(기운 줄의 주기 ÷ sin 45°가 아니다)');
      patterns.flush(canvas);
      final svg = await canvas.toSvg();
      expect(svg, contains('<pattern id="h0" patternUnits="userSpaceOnUse" width="5" height="5" patternTransform="translate(3 1) scale(1)">'));
      // (i, 4 − i) — 맨 왼쪽 칸이 맨 아래 줄 · 맨 오른쪽 칸이 맨 윗줄(오르는 '/').
      final head = svg.indexOf('<pattern id="h0"'), tail = svg.indexOf('</pattern>', head);
      final stairs = svg.substring(head, tail);
      for (int i = 0; i < 5; i++) {
        expect(stairs, contains('<rect x="$i" y="${4 - i}" width="1" height="1" fill="#262626" fill-opacity="0.25"/>'), reason: '칸 $i');
      }
      expect(countOf(stairs, '<rect '), 5);
      expect(countOf(stairs, '<line '), 0, reason: '기운 줄로 그리지 않는다');
      expect(countOf(svg, '<pattern '), 2, reason: '같은 각 · 굵기 · 주기의 기운 줄과 다른 무늬');
    });

    test('조각 그림판은 data: PNG 한 장 + 조각마다 가림막', () async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawCircle(const ui.Offset(8, 8), 8, ui.Paint()..color = const ui.Color(0xffffffff));
      final picture = recorder.endRecording();
      final sheet = picture.toImageSync(16, 16);
      picture.dispose();
      final canvas = SvgCanvas(width: 100, height: 100);
      canvas.drawRawAtlas(
        sheet,
        Float32List.fromList([1, 0, 30, 40, 2, 0, 60, 40]),
        Float32List.fromList([0, 0, 16, 16, 0, 0, 16, 16]),
        Int32List.fromList([0xff112233, 0x80445566]),
        ui.BlendMode.modulate,
        null,
        ui.Paint(),
      );
      final svg = await canvas.toSvg();
      sheet.dispose();
      expect(countOf(svg, '<image id='), 1, reason: '그림판 한 장은 한 번만 품는다');
      expect(svg, contains('data:image/png;base64,'));
      expect(countOf(svg, '<mask '), 1, reason: '같은 조각이니 가림막도 하나');
      expect(svg, contains('<rect x="30" y="40" width="16" height="16" fill="#112233" mask='));
      expect(svg, contains('<rect x="60" y="40" width="32" height="32" fill="#445566" fill-opacity="0.5" mask='));
    });

    test('옮기지 않는 그리기는 세어 둔다', () async {
      final canvas = SvgCanvas(width: 10, height: 10);
      canvas.drawPath(ui.Path(), ui.Paint());
      canvas.drawShadow(ui.Path(), const ui.Color(0xff000000), 2, false);
      canvas.clipRect(const ui.Rect.fromLTWH(0, 0, 5, 5), clipOp: ui.ClipOp.difference);
      expect(canvas.skipped, {'drawPath': 1, 'drawShadow': 1, 'clipRect(difference)': 1});
    });

    test('갈아 끼우지 못한 묶음은 drawVertices로 나가 세어진다', () async {
      // 층이 제 네모 묶음을 밖에서 갈아 끼울 수 없게 지어 두면(`RailLayer._overlay` — 연대 폭 빗금 위에 덮는 막대 토막)
      // 그 그림은 SVG에서만 빠진다. 그래도 [SvgCanvas.skipped]에 남으므로 저장 글이 사람에게 알린다([savedSvgNote]).
      final canvas = SvgCanvas(width: 100, height: 100);
      Quads()
        ..add(0, 0, 10, 10, 0xff445566)
        ..flush(canvas);
      expect(canvas.skipped, {'drawVertices': 1});
      expect(canvas.elements, 0, reason: '그림에는 한 조각도 들어가지 않는다');
    });
  });

  group('SvgText — 진짜 <text>', () {
    test('글줄 상자의 위를 밑줄로 내려 적고, 꼴을 속성으로 적는다', () async {
      await loadFonts();
      final text = SvgText(inner: ParagraphText());
      addTearDown(text.dispose);
      text.beginFrame();
      const look = TextLook(12.5, ui.FontWeight.w700, 0xcc2e2820, spacing: -.2);
      final canvas = SvgCanvas(width: 100, height: 100);
      expect(text.paint(canvas, '별여울', look, 20, 30), isTrue);
      final svg = await canvas.toSvg();
      final baseline = text.baselineOf('별여울', look);
      expect(baseline, greaterThan(9), reason: '12.5px · 줄 높이 1.2의 밑줄');
      expect(svgTexts(svg).length, 1);
      expect(svgTexts(svg).first.$1, '별여울');
      expect(svgTexts(svg).first.$2, 20);
      expect(svgTexts(svg).first.$3, closeTo(30 + baseline, 0.01));
      expect(svg, contains('font-size="12.5" font-weight="700" fill="#2e2820" fill-opacity="0.8" letter-spacing="-0.2"'));
    });

    test('폭 재기는 안쪽 뒷단에 그대로 맡긴다 — 이름 자리가 PNG와 같게', () {
      final inner = ParagraphText();
      final text = SvgText(inner: inner);
      addTearDown(text.dispose);
      text.beginFrame();
      const look = TextLook(12, ui.FontWeight.w400, 0xff000000);
      expect(text.widthOf('별여울', look), inner.widthOf('별여울', look));
      expect(text.canFade, isTrue, reason: '옅어짐은 fill-opacity 하나로 — 그림판 방식과 같다');
    });
  });

  group('SVG 한 장', () {
    test('PNG와 같은 크기 · 같은 여백 · 같은 제목과 기간 글', () async {
      await loadFonts();
      final f = makeBus();
      f.controller.showRange(minutesOfT(-1500), minutesOfT(1500));
      final png = await buildExportImage(f.bus, width: 1200, title: '별여울의 연표');
      final svg = await buildExportSvg(f.bus, width: 1200, title: '별여울의 연표');
      expect(svg.svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
      expect(svg.svg, contains('width="1200" height="${svgNum(png.height.toDouble())}"'));
      expect(svg.svg, contains('font-family="Pretendard, ChosunKm, Noto Sans KR, Malgun Gothic, sans-serif"'));
      expect(svg.svg, contains('<rect x="0" y="0" width="1200" height="${svgNum(png.height.toDouble())}" fill="#ffffff"/>'));
      expect(svg.svg, contains('<text x="16" y="32" font-size="20" font-weight="500" fill="#000000">별여울의 연표</text>'));
      expect(svg.svg, contains('text-anchor="end" fill="#666666">기원전 1500년 ~ 1500년</text>'));
      expect(svg.svg, endsWith('</svg>'));
    });

    test('넘긴 그리기 호출이 없다', () async {
      await loadFonts();
      final f = makeBus();
      final svg = await buildExportSvg(f.bus, width: 1200);
      expect(svg.skipped, isEmpty);
      expect(svg.elements, greaterThan(10), reason: '빈 종이 한 장이 아니다');
    });

    test('<text>의 수가 장면의 글줄 수와 같다(제목 · 기간 글은 따로)', () async {
      await loadFonts();
      final f = makeBus();
      final svg = await buildExportSvg(f.bus, width: 1200, title: '별여울의 연표');
      expect(svg.texts, svg.labels, reason: '그리개가 그린 글줄을 하나도 빠뜨리지 않는다');
      expect(svg.texts, greaterThan(0));
      expect(svgTexts(svg.svg).length, svg.texts + 2, reason: '제목 하나 · 기간 글 하나가 더 있다');
      final names = svgTexts(svg.svg).map((t) => t.$1).toList();
      expect(names, containsAll(['나라 0', '별여울의 기록 0']), reason: '띠 이름과 사건 이름이 글로 들어 있다');
      // 왼쪽 칸의 갈래 이름은 화면에서 한 글자씩 세로로 선다 — SVG에서도 글자마다 `<text>` 하나다.
      expect(names, containsAll(['갈', '래', '1']));
    });

    test('화면의 장면과 보기를 건드리지 않는다', () async {
      await loadFonts();
      final f = makeBus();
      final before = (f.controller.view.lo, f.controller.view.ppm, f.controller.view.top, f.controller.view.width, f.controller.view.height, f.scene.layout.version, f.scene.layout.totalHeight);
      await buildExportSvg(f.bus, width: 1800, title: '별여울의 연표');
      final after = (f.controller.view.lo, f.controller.view.ppm, f.controller.view.top, f.controller.view.width, f.controller.view.height, f.scene.layout.version, f.scene.layout.totalHeight);
      expect(after, before);
    });

    test('파일로 적고 덮어쓰지 않는다 — 역사연표.svg', () async {
      await loadFonts();
      final folder = Directory.systemTemp.createTempSync('ht-export-svg');
      addTearDown(() => folder.deleteSync(recursive: true));
      final f = makeBus();
      final first = await saveExportSvg(f.bus, width: 1200, title: '별여울의 연표', folder: folder);
      expect(first.path.endsWith('역사연표.svg'), isTrue);
      expect(File(first.path).readAsStringSync(), startsWith('<svg '));
      final second = await saveExportSvg(f.bus, width: 1200, folder: folder);
      expect(second.path.endsWith('역사연표 (2).svg'), isTrue);
    });

    test('적은 것을 부른 쪽에 그대로 넘긴다 — 넘긴 그리기를 버리지 않는다', () async {
      await loadFonts();
      final folder = Directory.systemTemp.createTempSync('ht-export-svg-made');
      addTearDown(() => folder.deleteSync(recursive: true));
      final f = makeBus();
      final done = await saveExportSvg(f.bus, width: 1200, title: '별여울의 연표', folder: folder);
      expect(done.made.skipped, isEmpty);
      expect(done.made.texts, done.made.labels);
      expect(done.made.texts, greaterThan(0));
      expect(done.made.svg, File(done.path).readAsStringSync(), reason: '적은 파일과 같은 글이다');
    });

    test('옮기지 못한 그리기가 있으면 저장 글에 몇 건인지 덧붙인다', () {
      const path = r'C:\내려받기\역사연표.svg';
      const clean = ExportSvg('<svg/>', texts: 3, elements: 9, shapes: 9, labels: 3, skipped: {});
      expect(savedSvgNote(path, clean), '저장했습니다 — $path');
      const lost = ExportSvg('<svg/>', texts: 3, elements: 9, shapes: 9, labels: 3, skipped: {'drawVertices': 2, 'drawPath': 1});
      expect(savedSvgNote(path, lost), '저장했습니다 — $path (옮기지 못한 그리기 3건)', reason: '조용히 빠뜨리지 않는다');
    });

    test('너무 크면 그리지 않고 막는다', () async {
      final f = makeBus(tracks: 30, rows: 8);
      await expectLater(
        buildExportSvg(f.bus, width: 3600),
        throwsA(isA<ExportImageException>().having((e) => e.message, '글', exportTooBigMessage)),
      );
    });
  });

  group('진짜 자료로', () {
    final dll = File('../engine/target/release/archive_engine.dll');
    final db = File(File('../data/moonwake3h/archive.db').existsSync() ? '../data/moonwake3h/archive.db' : '../data/moonwake3/archive.db');
    final ready = dll.existsSync() && db.existsSync();

    /// 실제 저장소로 장면 하나를 세워 그리개와 SVG를 나란히 돌린다.
    Future<({List<DebugLabel> drawn, String svg, SvgCanvas canvas, int shapes})> render(double startYear, double endYear) async {
      await loadFonts();
      final engine = ArchiveEngine(libraryPath: dll.absolute.path);
      addTearDown(engine.close);
      final info = await engine.start(db.absolute.path);
      final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
      final layout = SceneLayout.fromJson(Map<String, dynamic>.from((await engine.call(const {'op': 'layout'}))['data'] as Map));
      const width = 1920.0, height = 1020.0;
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(width, height)
        ..setExtent(double.parse(meta['min'] as String), double.parse(meta['max'] as String))
        ..setContentHeight(layout.totalHeight);
      final scene = TimelineScene(
        controller: controller,
        layout: layout,
        fetchTile: engine.tile,
        ask: (query) async => Map<String, dynamic>.from((await engine.call(query))['data'] as Map),
      );
      addTearDown(scene.dispose);
      scene.applyLayoutToView();
      controller.resize(width, height);
      controller.showRange(minuteOfYear(startYear), minuteOfYear(endYear));
      final text = SvgText(inner: AtlasText())
        ..maxNewPerFrame = 4000
        ..budgetMicros = 2000000;
      addTearDown(text.dispose);
      final painter = TimelinePainter(scene, text: text)..debug = true;
      int calm = 0;
      for (int i = 0; i < 400 && calm < 4; i++) {
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), const ui.Size(width, height));
        recorder.endRecording().dispose();
        await Future<void>.delayed(const Duration(milliseconds: 25));
        scene.tick(25);
        final s = scene.stats, labels = scene.labelOutput;
        calm = s.blanks == 0 && s.covers == 0 && !scene.fading && labels != null && labels.deferred == 0 && !text.starved && !scene.labelWorker.busy && scene.settled ? calm + 1 : 0;
      }
      expect(calm, greaterThanOrEqualTo(4), reason: '장면이 가라앉지 않았습니다');
      final drawn = [...painter.debugLabels];
      final canvas = SvgCanvas(width: width, height: height);
      paintSceneToSvg(
        painter,
        canvas,
        const ui.Size(width, height),
        text: text,
        quads: SvgQuads(),
        dividers: SvgLines(Look.line),
        patterns: SvgPatterns(),
        ruler: Ruler(),
      );
      return (drawn: drawn, svg: await canvas.toSvg(), canvas: canvas, shapes: scene.stats.shapes);
    }

    test('그리개와 같은 글줄을 같은 자리에 적는다 — 밀집-세부', () async {
      final made = await render(775, 940);
      expect(made.canvas.skipped, isEmpty, reason: '넘긴 그리기 호출이 없어야 한다');
      final texts = svgTexts(made.svg);
      // ignore: avoid_print
      print('밀집-세부: <text> ${texts.length} · 그리개의 글줄 ${made.drawn.length} · 도형 ${made.shapes} · 조각 ${made.canvas.elements} · SVG ${(made.svg.length / 1024).round()}KB');
      expect(texts.length, made.drawn.length);
      expect(texts.length, greaterThan(100), reason: '실제 저장소의 한 장면이다');
      // 자리: `<text>`의 y는 밑줄이라 그리개가 적은 글줄 상자의 위보다 내려와 있다. x는 그대로여야 한다.
      for (int i = 0; i < texts.length; i++) {
        expect(texts[i].$1, made.drawn[i].text, reason: '$i번째 글줄');
        expect(texts[i].$2, closeTo(made.drawn[i].at.dx, 0.01), reason: '$i번째 글줄의 가로 자리');
        expect(texts[i].$3 - made.drawn[i].at.dy, inInclusiveRange(6, 24), reason: '$i번째 글줄의 밑줄');
      }
    }, skip: ready ? false : '자료 처리부 DLL 또는 저장소가 없습니다', timeout: const Timeout(Duration(minutes: 5)));

    test('그리개와 같은 글줄을 같은 자리에 적는다 — 전체', () async {
      final made = await render(-1500, 1500);
      expect(made.canvas.skipped, isEmpty);
      final texts = svgTexts(made.svg);
      // ignore: avoid_print
      print('전체: <text> ${texts.length} · 그리개의 글줄 ${made.drawn.length} · 도형 ${made.shapes} · 조각 ${made.canvas.elements} · SVG ${(made.svg.length / 1024).round()}KB');
      expect(texts.length, made.drawn.length);
      expect(made.shapes, greaterThan(500), reason: '도형도 함께 적었다');
    }, skip: ready ? false : '자료 처리부 DLL 또는 저장소가 없습니다', timeout: const Timeout(Duration(minutes: 5)));

    test('저장소 한 벌을 SVG 한 장에 담아 파일로 적는다 — 같은 장면의 PNG와 나란히', () async {
      await loadFonts();
      final engine = ArchiveEngine(libraryPath: dll.absolute.path);
      addTearDown(engine.close);
      final info = await engine.start(db.absolute.path);
      final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
      Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async => Map<String, dynamic>.from((await engine.call(query))['data'] as Map);
      final layout = SceneLayout.fromJson(await ask(const {'op': 'layout'}));
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 1020)
        ..setExtent(double.parse(meta['min'] as String), double.parse(meta['max'] as String))
        ..setContentHeight(layout.totalHeight);
      final scene = TimelineScene(controller: controller, layout: layout, fetchTile: engine.tile, ask: ask);
      addTearDown(scene.dispose);
      scene.applyLayoutToView();
      controller.resize(1920, 1020);
      final bus = AppBus(ask: ask, controller: controller, scene: scene);
      final folder = Directory('../results/export-svg')..createSync(recursive: true);

      for (final (name, from, to) in [('밀집-세부', 775.0, 940.0), ('전체', -1500.0, 1500.0)]) {
        controller.showRange(minuteOfYear(from), minuteOfYear(to));
        final title = defaultExportTitle(controller.view.lo, controller.view.hi);
        final png = await buildExportImage(bus, width: 1200, title: title);
        File('${folder.path}/$name.png').writeAsBytesSync(png.png);
        final svg = await buildExportSvg(bus, width: 1200, title: title);
        File('${folder.path}/$name.svg').writeAsStringSync(svg.svg);
        expect(svg.skipped, isEmpty, reason: '$name — 넘긴 그리기 호출');
        expect(svg.texts, svg.labels, reason: '$name — 글줄을 하나도 빠뜨리지 않는다');
        // ignore: avoid_print
        print('$name: PNG ${png.width}×${png.height} ${(png.png.length / 1024).round()}KB · '
            'SVG ${(svg.svg.length / 1024).round()}KB · 조각 ${svg.elements} · <text> ${svg.texts} · 도형 ${svg.shapes}');
      }
      // ignore: avoid_print
      print('저장: ${folder.absolute.path}');
    }, skip: ready ? false : '자료 처리부 DLL 또는 저장소가 없습니다', timeout: const Timeout(Duration(minutes: 10)));
  });
}

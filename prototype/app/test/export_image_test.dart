import 'load_app_fonts.dart';

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/axis_model.dart';
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/date_text.dart';
import 'package:archive_prototype/ui/export_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 이미지로 저장 · 인쇄(명세 06의 7-5): 제목의 기본값 · 한 장에 담기는 크기 · 위아래 여백 ·
// 화면을 건드리지 않는 것 · 너무 큰 그림 막기 · 덮어쓰지 않는 파일 이름 ·
// A4 가로 한 장(여백 8mm)에 담기 · 인쇄로 보내기와 실패했을 때의 글 · 대화 상자의 모양.

const _rowHeight = 142.0;
const _m = 1000000.0;
final _ppm = 32 / bucketMinutes(9); // 통 32px → 단계 9
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

/// 검사용 앱 길: 트랙 [tracks]개 × 줄 [rows]줄(줄마다 142px)이라 내용이 창(560)보다 훨씬 높다.
/// 자료 처리부 대신 타일을 지어 주고, `layout` · `rows_near` · `row_labels`에 답한다.
({AppBus bus, TimelineController controller, TimelineScene scene, List<Map<String, dynamic>> asked}) makeBus({int tracks = 3, int rows = 4}) {
  final json = _layoutJson(tracks, rows);
  final count = tracks * rows;
  final asked = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async {
    asked.add(query);
    return switch (query['op']) {
      'layout' => json,
      'rows_near' => {'near': [for (int r = 0; r < count; r++) r], 'far': const <int>[]},
      'row_labels' => {
        'labels': [for (final r in query['rows'] as List) {'row': r, 'items': const []}],
      },
      _ => const <String, dynamic>{},
    };
  }

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
  return (bus: AppBus(ask: ask, controller: controller, scene: scene), controller: controller, scene: scene, asked: asked);
}

/// 그림의 **아래 여백 안**에서 종이빛이 아닌 점이 있는 줄(y)들. 아래 여백의 글을 눈 대신 화소로 본다.
Future<List<int>> _bottomInk(ExportImage image) async {
  final codec = await ui.instantiateImageCodec(image.png);
  final frame = await codec.getNextFrame();
  final data = (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  frame.image.dispose();
  codec.dispose();
  final rows = <int>[];
  for (int y = image.height - exportFootMargin.toInt(); y < image.height; y++) {
    for (int x = math.max(0, image.width - 300); x < image.width; x++) {
      final at = (y * image.width + x) * 4;
      if (data[at] != 0xfb || data[at + 1] != 0xf7 || data[at + 2] != 0xef) {
        rows.add(y);
        break;
      }
    }
  }
  return rows;
}

void main() {
  group('제목의 기본값', () {
    test('넓게 보면 해까지 — 역사 연표 (기원전 1500년 ~ 1500년)', () {
      expect(defaultExportTitle(minutesOfT(-1500), minutesOfT(1500)), '역사 연표 (기원전 1500년 ~ 1500년)');
    });

    test('확대했으면 달 · 날까지 적고, 같은 해면 뒤쪽의 겹치는 앞부분을 줄인다', () {
      expect(defaultExportTitle(minutesOfT(827), minutesOfT(829)), '역사 연표 (827년 1월 ~ 829년 1월)');
      expect(defaultExportTitle(minutesOfT(827.2), minutesOfT(827.6)), '역사 연표 (827년 3월 15일 ~ 8월 8일)');
      expect(defaultExportTitle(minutesOfT(-960), minutesOfT(-400)), '역사 연표 (기원전 960년 ~ 기원전 400년)');
    });
  });

  group('그림 만들기', () {
    test('모든 트랙이 한 장에 든다 — 세로는 위 여백 + 날짜 칸 + 내용 높이 전체 + 아래 여백', () async {
      final f = makeBus();
      final image = await buildExportImage(f.bus, width: 1200);
      final head = AxisModel(f.scene.layout).height;
      expect(image.width, 1200);
      expect(
        image.height,
        (exportHeadMargin + head + 12 * _rowHeight + exportFootMargin).ceil(),
        reason: '화면(560) 밖의 트랙까지 모두',
      );
      expect(image.png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10], reason: 'PNG의 머리');
    });

    test('위 여백 10 · 아래 여백 24 — 지금 연표의 toSVG와 같다', () {
      expect(exportHeadMargin, 10);
      expect(exportFootMargin, 24);
      expect(exportTitleHeight, 46);
    });

    test('아래 여백에 지금 보는 기간을 적는다 — 제목이 없어도', () async {
      final f = makeBus(tracks: 1, rows: 2);
      f.controller.showRange(minutesOfT(-1500), minutesOfT(1500));
      // 글자가 든 만큼 PNG가 커진다(같은 크기 · 같은 그림에서 아래 여백만 다르다).
      final withFooter = await buildExportImage(f.bus, width: 1200);
      expect(withFooter.height, greaterThan(0));
      final lines = await _bottomInk(withFooter);
      expect(lines, isNotEmpty, reason: '아래 24px 안에 글자가 찍혔다');
      expect(lines.every((y) => y >= withFooter.height - exportFootMargin), isTrue, reason: '아래 여백 안에만 적는다');
    });

    test('제목이 있으면 위가 10에서 46으로 넓어진다(아래 24는 그대로)', () async {
      final f = makeBus();
      final plain = await buildExportImage(f.bus, width: 1200);
      final titled = await buildExportImage(f.bus, width: 1200, title: '별여울의 연표');
      expect(titled.width, plain.width);
      expect(titled.height, plain.height + (exportTitleHeight - exportHeadMargin).toInt());
    });

    test('고른 가로 크기가 그대로 그림의 폭이다', () async {
      final f = makeBus(tracks: 1, rows: 2);
      for (final width in exportWidths) {
        final image = await buildExportImage(f.bus, width: width);
        expect(image.width, width.round());
      }
    });

    test('화면의 장면과 보기를 건드리지 않는다', () async {
      final f = makeBus();
      final before = (f.controller.view.lo, f.controller.view.ppm, f.controller.view.top, f.controller.view.width, f.controller.view.height, f.scene.layout.version, f.scene.layout.totalHeight);
      await buildExportImage(f.bus, width: 2600, title: '별여울의 연표');
      final after = (f.controller.view.lo, f.controller.view.ppm, f.controller.view.top, f.controller.view.width, f.controller.view.height, f.scene.layout.version, f.scene.layout.totalHeight);
      expect(after, before);
    });

    test('너무 크면 그리지 않고 막는다', () async {
      final f = makeBus(tracks: 30, rows: 8); // 240줄 × 142px × 3600 = 6천만 화소를 넘는다
      await expectLater(
        buildExportImage(f.bus, width: 3600),
        throwsA(isA<ExportImageException>().having((e) => e.message, '글', exportTooBigMessage)),
      );
    });
  });

  group('진짜 자료로', () {
    final dll = File('../engine/target/release/archive_engine.dll');
    final db = File(File('../data/moonwake3/archive.db').existsSync() ? '../data/moonwake3/archive.db' : '../data/moonwake2/archive.db');

    test('저장소 한 벌을 한 장에 담아 파일로 적는다', () async {
      await loadAppFonts();
      // 검사 환경에는 시스템 글꼴이 없다 — 지금 연표가 이 PC에서 쓰는 글꼴을 같은 이름으로 올린다(test/render_scene_test.dart와 같게).
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
      controller.showRange(minutesOfT(-1500), minutesOfT(1500));
      final bus = AppBus(ask: ask, controller: controller, scene: scene);

      final title = defaultExportTitle(controller.view.lo, controller.view.hi);
      final folder = Directory('../results/export-image')..createSync(recursive: true);
      final image = await buildExportImage(bus, width: 1200, title: title);
      File('${folder.path}/역사연표.png').writeAsBytesSync(image.png);
      expect(image.width, 1200);
      expect(image.height, greaterThan(AxisModel(layout).height), reason: '날짜 칸 아래로 내용이 있다');
      expect(image.png.length, greaterThan(20000), reason: '빈 종이 한 장이 아니다');
      // ignore: avoid_print
      print('저장: ${folder.absolute.path}${Platform.pathSeparator}역사연표.png (${image.width}×${image.height} · ${(image.png.length / 1024).round()}KB · 제목 "$title")');

      // 인쇄로 보내는 종이도 같은 자료로 한 장 떠 둔다(눈으로 보는 증거 — 인쇄 자체는 띄우지 않는다).
      final made = await buildPrintSheet(bus, width: 1200, title: title);
      File('${folder.path}/역사연표-인쇄.png').writeAsBytesSync(made.sheet.png);
      expect(made.sheet.width / made.sheet.height, closeTo(297 / 210, 2e-3), reason: 'A4 가로');
      // ignore: avoid_print
      print('인쇄 종이: ${made.sheet.width}×${made.sheet.height} (${(made.sheet.png.length / 1024).round()}KB · 인쇄 폭의 ${(made.fill * 100).round()}%)');
    }, skip: dll.existsSync() && db.existsSync() ? false : '자료 처리부 DLL 또는 저장소가 없습니다', timeout: const Timeout(Duration(minutes: 5)));
  });

  group('파일로 적기', () {
    test('이미 있으면 번호를 붙여 덮어쓰지 않는다', () {
      final folder = Directory.systemTemp.createTempSync('ht-export-name')..createSync(recursive: true);
      addTearDown(() => folder.deleteSync(recursive: true));
      final first = exportTargetFile(folder);
      expect(first.path.endsWith('역사연표.png'), isTrue);
      first.writeAsBytesSync(const [0]);
      final second = exportTargetFile(folder);
      expect(second.path.endsWith('역사연표 (2).png'), isTrue);
      second.writeAsBytesSync(const [0]);
      expect(exportTargetFile(folder).path.endsWith('역사연표 (3).png'), isTrue);
    });

    test('그림을 적고 그 경로를 돌려준다', () async {
      final folder = Directory.systemTemp.createTempSync('ht-export-save');
      addTearDown(() => folder.deleteSync(recursive: true));
      final f = makeBus(tracks: 1, rows: 2);
      final path = await saveExportImage(f.bus, width: 1200, title: '별여울의 연표', folder: folder);
      expect(path.endsWith('역사연표.png'), isTrue);
      expect(File(path).readAsBytesSync().sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });
  });

  group('A4 가로 한 장 — 인쇄', () {
    /// 종이가 A4 가로(297:210)인가, 여백이 사방 8mm인가.
    void expectA4(({double sheetWidth, double sheetHeight, ui.Rect at}) plan) {
      expect(plan.sheetWidth / plan.sheetHeight, closeTo(297 / 210, 1e-9), reason: 'A4 가로의 비율');
      final left = plan.sheetWidth * 8 / 297, top = plan.sheetHeight * 8 / 210;
      expect(plan.at.left, greaterThanOrEqualTo(left - 1e-6));
      expect(plan.at.top, greaterThanOrEqualTo(top - 1e-6));
      expect(plan.sheetWidth - plan.at.right, greaterThanOrEqualTo(left - 1e-6));
      expect(plan.sheetHeight - plan.at.bottom, greaterThanOrEqualTo(top - 1e-6));
    }

    test('넓적한 그림은 줄이지 않고 여백 안의 폭을 꽉 채운다', () {
      final plan = printSheetLayout(1200, 800);
      expectA4(plan);
      expect(plan.at.width, closeTo(1200, 1e-6), reason: '1:1 — 늘리지도 줄이지도 않는다');
      expect(plan.at.height, closeTo(800, 1e-6));
      expect(plan.at.width, closeTo(plan.sheetWidth * 281 / 297, 1e-6), reason: '여백 8mm를 뺀 폭을 꽉 채운다');
      expect(plan.at.center.dy, closeTo(plan.sheetHeight / 2, 1e-6), reason: '세로 가운데');
    });

    test('세로로 긴 그림은 종이가 너무 커지지 않게 줄여 담는다', () {
      final plan = printSheetLayout(1200, 5000);
      expectA4(plan);
      expect(plan.sheetWidth, printSheetMaxWidth);
      expect(plan.at.width / plan.at.height, closeTo(1200 / 5000, 1e-9), reason: '비율은 그대로');
      expect(plan.at.height, closeTo(plan.sheetHeight * 194 / 210, 1e-3), reason: '여백 8mm를 뺀 높이를 꽉 채운다');
      expect(plan.at.center.dx, closeTo(plan.sheetWidth / 2, 1e-6), reason: '가로 가운데');
    });

    test('종이 한 장을 만든다 — 비율이 A4 가로인 PNG', () async {
      final f = makeBus(tracks: 1, rows: 2);
      final made = await buildPrintSheet(f.bus, width: 1200, title: '별여울의 연표');
      expect(made.sheet.png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(made.sheet.width / made.sheet.height, closeTo(297 / 210, 2e-3), reason: '화소로 올림한 만큼만 어긋난다');
      expect(made.sheet.width, greaterThan(1200), reason: '그림이 여백 안에 들어갔다');
      expect(made.fill, closeTo(1, 1e-6), reason: '넓적한 그림이라 인쇄 폭을 꽉 채운다');
    });

    test('세로로 긴 연표는 인쇄 폭의 얼마를 차지하는지 함께 알린다', () {
      final plan = printSheetLayout(1200, 11280); // 진짜 자료(월흔해 한 벌 · 1200px)의 크기
      final box = plan.sheetWidth * 281 / 297;
      expect(plan.at.width / box, lessThan(.1), reason: '한 장에 담으면 가는 띠가 된다 — 대화 상자가 이 값을 알린다');
    });

    test('만든 종이를 인쇄로 보내고 그 경로를 돌려준다', () async {
      final folder = Directory.systemTemp.createTempSync('ht-export-print');
      addTearDown(() => folder.deleteSync(recursive: true));
      final sent = <String>[];
      final f = makeBus(tracks: 1, rows: 2);
      final done = await printExportImage(
        f.bus,
        width: 1200,
        folder: folder,
        printFile: (p) async => sent.add(p),
      );
      expect(sent, [done.path], reason: '적은 파일을 그대로 인쇄로 보낸다');
      expect(done.path.endsWith('역사연표-인쇄.png'), isTrue);
      expect(File(done.path).readAsBytesSync().sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });

    test('인쇄 길이 실패하면 까닭이 그대로 올라온다', () async {
      final folder = Directory.systemTemp.createTempSync('ht-export-print-fail');
      addTearDown(() => folder.deleteSync(recursive: true));
      final f = makeBus(tracks: 1, rows: 2);
      await expectLater(
        printExportImage(
          f.bus,
          width: 1200,
          folder: folder,
          printFile: (p) async => throw const ExportImageException('인쇄 대화 상자를 띄우지 못했습니다 — 기본 프린터가 없습니다'),
        ),
        throwsA(isA<ExportImageException>().having((e) => e.message, '글', contains('기본 프린터가 없습니다'))),
      );
    });
  });

  group('대화 상자', () {
    Future<void> open(WidgetTester tester, AppBus bus, {PrintFile? printFile}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Ui.bg,
          body: ExportDialog(bus: bus, printFile: printFile ?? (p) async {}),
        ),
      ),
    );

    testWidgets('가로 크기 넷과 제목 · 인쇄 · SVG 저장 · PNG 저장이 지금 연표의 차례로 있다', (tester) async {
      final f = makeBus();
      await open(tester, f.bus);
      expect(find.text('이미지 · 인쇄'), findsOneWidget);
      expect(find.text('1800px'), findsOneWidget, reason: '처음 값');
      expect(find.text('인쇄'), findsOneWidget);
      expect(find.text('SVG 저장'), findsOneWidget);
      expect(find.text('PNG 저장'), findsOneWidget);
      // 지금 연표의 단추 줄(index.html:167~172): 인쇄는 맨 왼쪽 · 오른쪽 끝은 SVG 저장 → PNG 저장.
      final at = {for (final label in ['인쇄', 'SVG 저장', 'PNG 저장']) label: tester.getCenter(find.text(label)).dx};
      expect(at['인쇄']!, lessThan(at['SVG 저장']!));
      expect(at['SVG 저장']!, lessThan(at['PNG 저장']!));
      for (final width in exportWidths) {
        expect(find.textContaining('${width.round()}px'), findsWidgets);
      }
    });

    testWidgets('SVG 저장을 누르면 단추가 잠기고, 그리지 못하면 까닭을 적는다', (tester) async {
      final f = makeBus(tracks: 60, rows: 8); // 480줄 × 142px × 1800px = 6천만 화소를 넘는다
      await open(tester, f.bus);
      await tester.tap(find.text('SVG 저장'));
      await tester.pump();
      expect(find.text('SVG를 만들고 있습니다…'), findsOneWidget);
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(tester.widget<Text>(find.text(exportTooBigMessage)).style!.color, Ui.ink, reason: '실패는 색 없이 잉크로 적는다');
    });

    testWidgets('좁은 창(320px)에서도 단추 줄이 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = makeBus(tracks: 1, rows: 2);
      await open(tester, f.bus);
      expect(find.text('인쇄'), findsOneWidget);
      expect(find.text('PNG 저장'), findsOneWidget);
    });

    testWidgets('인쇄를 누르면 단추가 잠기고, 그리지 못하면 까닭을 적는다', (tester) async {
      final f = makeBus(tracks: 60, rows: 8); // 480줄 × 142px × 1800px = 6천만 화소를 넘는다
      await open(tester, f.bus);
      await tester.tap(find.text('인쇄'));
      await tester.pump();
      expect(find.text('인쇄할 그림을 만들고 있습니다…'), findsOneWidget);
      expect(
        tester.widget<Opacity>(find.ancestor(of: find.text('PNG 저장'), matching: find.byType(Opacity)).first).opacity,
        .45,
        reason: '만드는 동안 단추가 잠긴다',
      );
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(tester.widget<Text>(find.text(exportTooBigMessage)).style!.color, Ui.ink, reason: '실패는 색 없이 잉크로 적는다');
    });

    testWidgets('제목 칸은 지금 보는 기간으로 채워져 있고 60자까지 받는다', (tester) async {
      final f = makeBus();
      f.controller.showRange(minutesOfT(-1500), minutesOfT(1500));
      await open(tester, f.bus);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, defaultExportTitle(f.controller.view.lo, f.controller.view.hi));
      expect(field.controller!.text.startsWith('역사 연표 (기원전 1500년'), isTrue);
      expect(field.decoration!.hintText, isNull, reason: '입력 칸에 회색 예시 글자를 두지 않는다');
      await tester.enterText(find.byType(TextField), '가' * 80);
      await tester.pump();
      expect(field.controller!.text.length, exportTitleLimit);
    });
  });
}

import 'load_app_fonts.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/strips.dart' show StripLayer;
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart' show Ui;
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_glue.dart' show readPlaces;
import 'package:archive_prototype/ui/cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 가문 조명(확정 설계 1-2 5-3 · 결정 7 A)을 진짜 자료 처리부 · 진짜 저장소로 그림에 떠서 웹의 같은 장면과 1배로 견준다(D1-N3).
// 앱 틀이 가문 창을 열 때 짓는 상태(`Look.house` · `houses` · 가문 기록 `x_spots`를 띠 번호로 바꾼 `spots`)를 손으로 지어 건다.
// 같은 장면을 ① 켜기 전 ② 켬 ③ 켰다 끈 뒤로 세 번 떠서 ③ = ①(픽셀까지)을 단언하고, ②를 PNG로 남긴다.
// 사용(app 폴더에서 — 저장소가 없으면 건너뜀):
//   flutter test --no-pub test/house_light_render_test.dart --dart-define=DB=<저장소> --dart-define=HOUSES=<가문 id,…>
//     [--dart-define=DLL=<자료 처리부>] [--dart-define=START=-60 --dart-define=END=1270] [--dart-define=REVEAL=<띠 uid> --dart-define=AT=110]
//     [--dart-define=OUT=../results/render] [--dart-define=NAME=가문조명]
//   HOUSES의 첫째가 누른 가문(`Look.house`)이고, 묶음(`Look.houses`)은 그 가문들의 `x_under`(없으면 자기)를 모두 합친 것이다.
//   REVEAL을 주면 그 띠의 윗변이 그림의 AT px(맨 위 60px은 앱 틀의 자리 — 기준 그림과 같은 좌표)에 오게 굴린다.
// 성씨 풍선(결정 6 A): BALLOON=<띠 uid>|<칸 참조>(예: 지도자 칸 leader:12)를 주면 그 칸에 커서를 올린 장면을 위젯째로 떠서
//   <NAME>-풍선.png로 남긴다(HOUSES 없이도 — 가문 기록은 칸 구역 42의 가문 id로 찾는다).

const _db = String.fromEnvironment('DB');
const _dll = String.fromEnvironment('DLL', defaultValue: '../engine/target/release/archive_engine.dll');
const _houses = String.fromEnvironment('HOUSES');
const _start = String.fromEnvironment('START', defaultValue: '-60'), _end = String.fromEnvironment('END', defaultValue: '1270');
const _reveal = String.fromEnvironment('REVEAL'), _at = String.fromEnvironment('AT', defaultValue: '110');
const _out = String.fromEnvironment('OUT', defaultValue: '../results/render');
const _name = String.fromEnvironment('NAME', defaultValue: '가문조명');
const _balloon = String.fromEnvironment('BALLOON');

/// 지금 연표의 해 좌표 → 1970년 기준 분(test/render_scene_test.dart와 같은 투영).
double minuteOfYear(double y) {
  final year = y.floor();
  final a = DateTime.utc(year < 0 ? year + 1 : year), b = DateTime.utc(year == -1 ? 1 : (year < 0 ? year + 2 : year + 1));
  return (a.millisecondsSinceEpoch + (b.millisecondsSinceEpoch - a.millisecondsSinceEpoch) * (y - year)) / 60000;
}

Future<void> _loadFonts() async {
  await loadAppFonts();
  // 리눅스(클라우드 작업 상자)에 깔아 둔 Pretendard — 웹 연표를 찍는 크로미움도 이 글꼴로 그린다(render_scene_test와 같은 길).
  final home = Platform.environment['HOME'] ?? '';
  for (final family in const ['Noto Sans KR', 'Malgun Gothic']) {
    final loader = FontLoader(family);
    var any = false;
    for (final w in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final file = File('$home/.fonts/Pretendard-$w.otf');
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length)));
      any = true;
    }
    if (any) await loader.load();
  }
}

void main() {
  final dll = File(_dll), db = File(_db);
  final ready = _db.isNotEmpty && _houses.isNotEmpty && dll.existsSync() && db.existsSync();

  test('가문 조명을 진짜 저장소의 장면에 켜고 끈다 — 끈 뒤는 켜기 전과 픽셀까지 같다', () async {
    await _loadFonts();
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    final info = await engine.start(db.absolute.path);
    final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from((await engine.call({'op': 'layout'}))['data'] as Map));
    const width = 1920.0, height = 1080.0, top = 60.0;
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(width, height - top)
      ..setExtent(double.parse(meta['min'] as String), double.parse(meta['max'] as String))
      ..setContentHeight(layout.totalHeight);
    Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async => Map<String, dynamic>.from((await engine.call(query))['data'] as Map);
    final scene = TimelineScene(
      controller: controller,
      layout: layout,
      fetchTile: (level, x, chunk, packs) => engine.tile(level, x, chunk, packs, variants: layout.variantKeys),
      ask: ask,
    );
    addTearDown(scene.dispose);
    scene.applyLayoutToView();
    controller.resize(width, height - top);
    controller.showRange(minuteOfYear(double.parse(_start)), minuteOfYear(double.parse(_end)));
    if (_reveal.isNotEmpty) {
      final place = readPlaces(await ask({'op': 'ids_of', 'uids': [_reveal]}))[_reveal];
      final row = place?.row;
      if (row != null) {
        final bandTop = layout.rowTop(row) + layout.geo(row).bandTop;
        controller.scrollTo(bandTop - (double.parse(_at) - top - controller.view.head));
      }
    }

    // 앱 틀(N2 — app_glue `_buildLook`)이 가문 창에서 짓는 상태: 누른 가문 + x_under 묶음 + x_spots를 띠 번호로.
    final ids = _houses.split(',').where((s) => s.isNotEmpty).toList();
    final houses = <String>{};
    final spotRows = <(String, double, double)>[];
    for (final id in ids) {
      final answer = await ask({'op': 'entity', 'uid': 'house:$id'});
      final x = jsonDecode(answer['json'] as String) as Map<String, dynamic>;
      final under = x['x_under'];
      houses.addAll(under is List ? [for (final u in under) '$u'] : [id]);
      for (final s in (x['x_spots'] as List? ?? const [])) {
        final m = s as Map;
        spotRows.add(('${m['uid']}', (m['start'] as num).toDouble(), (m['end'] as num).toDouble()));
      }
    }
    final places = readPlaces(await ask({'op': 'ids_of', 'uids': {for (final s in spotRows) s.$1}.toList()}));
    final spots = [
      for (final s in spotRows)
        if (places[s.$1]?.band != null) em.Spot(places[s.$1]!.band!, s.$2, s.$3),
    ];
    expect(spots, isNotEmpty, reason: '가문 기록의 x_spots가 띠에 놓여야 한다');
    final lit = em.Look(house: ids.first, houses: houses, spots: spots);

    final text = AtlasText()
      ..maxNewPerFrame = 4000
      ..budgetMicros = 2000000;
    addTearDown(text.dispose);
    final painter = TimelinePainter(scene, text: text)..debug = true;

    Future<void> settle() async {
      int calm = 0;
      for (int i = 0; i < 400 && calm < 4; i++) {
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), const ui.Size(width, height - top));
        recorder.endRecording().dispose();
        await Future<void>.delayed(const Duration(milliseconds: 25));
        scene.tick(25);
        final s = scene.stats, labels = scene.labelOutput;
        final settled = s.blanks == 0 && s.covers == 0 && !scene.fading && ((labels != null && labels.deferred == 0) || layout.allFolded) && !text.starved && !scene.labelWorker.busy && scene.settled;
        calm = settled ? calm + 1 : 0;
      }
      expect(calm, greaterThanOrEqualTo(4), reason: '장면이 가라앉지 않았습니다');
    }

    Future<Uint8List> shot(String? file) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(const ui.Rect.fromLTWH(0, 0, width, height), ui.Paint()..color = const ui.Color(0xfff4eee4));
      canvas.drawRect(const ui.Rect.fromLTWH(0, top, width, 1), ui.Paint()..color = const ui.Color(0x1a5a3c14));
      canvas.save();
      canvas.translate(0, top);
      canvas.clipRect(const ui.Rect.fromLTWH(0, 0, width, height - top));
      painter.paint(canvas, const ui.Size(width, height - top));
      canvas.restore();
      final picture = recorder.endRecording();
      final image = await picture.toImage(width.toInt(), height.toInt());
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (file != null) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final folder = Directory(_out)..createSync(recursive: true);
        File('${folder.path}/$file').writeAsBytesSync(png!.buffer.asUint8List());
      }
      picture.dispose();
      image.dispose();
      return raw!.buffer.asUint8List();
    }

    await settle();
    final before = await shot('$_name-끔.png');
    em.Emphasis.of(scene)
      ..reduceMotion = true
      ..set(lit);
    await settle();
    final on = await shot('$_name-켬.png');
    final fills = painter.debugSink.notes['조명칠']?.length ?? 0;
    em.Emphasis.of(scene).set(const em.Look());
    await settle();
    final after = await shot(null);
    var differ = 0;
    for (int i = 0; i < on.length; i += 4) {
      if (on[i] != before[i] || on[i + 1] != before[i + 1] || on[i + 2] != before[i + 2]) differ++;
    }
    expect(differ, greaterThan(0), reason: '켜면 달라진다');
    expect(after, before, reason: '켰다 끈 뒤의 장면 = 켜기 전 장면(픽셀까지)');
    // ignore: avoid_print
    print('가문 조명: 묶음 ${houses.join(',')} · 구간 ${spots.length} · 칠 $fills · 다른 픽셀 $differ → ${Directory(_out).absolute.path}/$_name-켬.png');
  }, skip: ready ? false : '자료 처리부 DLL 또는 저장소(DB) · 가문(HOUSES)이 없습니다', timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('성씨 풍선을 진짜 저장소의 장면 위에 띄운다(칸 위에 커서)', (tester) async {
    const width = 1920.0, height = 1080.0, top = 60.0;
    tester.view.physicalSize = const Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late ArchiveEngine engine;
    late TimelineScene scene;
    late TimelinePainter painter;
    late AppBus bus;
    late AtlasText text;
    await tester.runAsync(() async {
      await _loadFonts();
      engine = ArchiveEngine(libraryPath: dll.absolute.path);
      final info = await engine.start(db.absolute.path);
      final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
      final layout = SceneLayout.fromJson(Map<String, dynamic>.from((await engine.call({'op': 'layout'}))['data'] as Map));
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(width, height - top)
        ..setExtent(double.parse(meta['min'] as String), double.parse(meta['max'] as String))
        ..setContentHeight(layout.totalHeight);
      Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async => Map<String, dynamic>.from((await engine.call(query))['data'] as Map);
      scene = TimelineScene(
        controller: controller,
        layout: layout,
        fetchTile: (level, x, chunk, packs) => engine.tile(level, x, chunk, packs, variants: layout.variantKeys),
        ask: ask,
      );
      bus = AppBus(ask: ask, controller: controller, scene: scene);
      scene.applyLayoutToView();
      controller.resize(width, height - top);
      controller.showRange(minuteOfYear(double.parse(_start)), minuteOfYear(double.parse(_end)));
      final cut = _balloon.lastIndexOf('|');
      final bandUid = _balloon.substring(0, cut), ref = _balloon.substring(cut + 1);
      final place = readPlaces(await ask({'op': 'ids_of', 'uids': [_reveal.isNotEmpty ? _reveal : bandUid]}))[_reveal.isNotEmpty ? _reveal : bandUid];
      if (place?.row != null) {
        final bandTop = layout.rowTop(place!.row!) + layout.geo(place.row!).bandTop;
        controller.scrollTo(bandTop - (double.parse(_at) - top - controller.view.head));
      }
      final band = readPlaces(await ask({'op': 'ids_of', 'uids': [bandUid]}))[bandUid]?.band;
      expect(band, isNotNull, reason: '그 띠가 저장소에 있어야 한다');
      SceneMarks.of(scene)
        ..hotCell = '$band|$ref'
        ..version += 1;
      text = AtlasText()
        ..maxNewPerFrame = 4000
        ..budgetMicros = 2000000;
      painter = TimelinePainter(scene, text: text);
      for (int i = 0; i < 400; i++) {
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), const ui.Size(width, height - top));
        recorder.endRecording().dispose();
        await Future<void>.delayed(const Duration(milliseconds: 25));
        scene.tick(25);
        final s = scene.stats;
        if (i > 8 && s.blanks == 0 && s.covers == 0 && !scene.fading && !text.starved && !scene.labelWorker.busy && scene.settled) break;
      }
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        bus.dispose();
        scene.dispose();
        text.dispose();
        engine.close();
      });
    });
    final hit = StripLayer.hoverOf(scene).value;
    expect(hit, isNotNull, reason: '칸 층이 커서가 올라간 칸을 알렸어야 한다');
    final cards = ClusterCardController(bus: bus);
    addTearDown(cards.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
        home: Scaffold(
          backgroundColor: Ui.bg,
          body: RepaintBoundary(
            key: key,
            child: Column(
              children: [
                const SizedBox(height: top),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: CustomPaint(painter: painter)),
                      Positioned.fill(child: ClusterCardLayer(bus: bus, cards: cards, gutter: bus.controller.view.left)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(CardLook.hoverFirst);
    for (int i = 0; i < 10 && find.byType(HouseBalloon).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(HouseBalloon), findsOneWidget, reason: '160ms 뒤에 풍선이 선다');
    for (int i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30))); // 기록 받기(자료 처리부)
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 260));
    final glass = tester.getRect(find.descendant(of: find.byType(HouseBalloon), matching: find.byType(ConstrainedBox)).first);
    final cell = Rect.fromLTRB(hit!.rect.left, hit.rect.top + top, hit.rect.right, hit.rect.bottom + top);
    // 자리: 칸 아래 8px · 칸 왼쪽에서 8px 앞(화면 안이면).
    expect(glass.top, closeTo(cell.bottom + BalloonLook.gap, .51));
    expect(glass.left, closeTo(cell.left - BalloonLook.gap, .51));
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final folder = Directory(_out)..createSync(recursive: true);
      File('${folder.path}/$_name-풍선.png').writeAsBytesSync(png!.buffer.asUint8List());
      // ignore: avoid_print
      print('성씨 풍선: 칸 ${hit.key} ${hit.rect} · 가문 ${hit.houseId} · 풍선 $glass → ${folder.absolute.path}/$_name-풍선.png');
    });
  }, skip: !(_db.isNotEmpty && _balloon.isNotEmpty && dll.existsSync() && db.existsSync())); // 자료 처리부 DLL 또는 저장소(DB) · 칸(BALLOON)이 없으면 건너뜀
}

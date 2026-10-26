// 진단: 층마다 한 장면에 쓰는 시간(장면 만들기 쪽 — 그리기 명령을 모으는 시간)을 잰다. 검사가 아니라 재는 도구다.
// 사용: flutter test --no-pub test/profile_layers_test.dart --dart-define=DB=../data/v3b-1m/archive.db [--dart-define=YEARS=120 --dart-define=MAG=1 --dart-define=FRAMES=400]
import 'load_app_fonts.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _db = String.fromEnvironment('DB');
const _years = String.fromEnvironment('YEARS', defaultValue: '120');
const _mag = String.fromEnvironment('MAG', defaultValue: '1');
const _frames = String.fromEnvironment('FRAMES', defaultValue: '400');

Future<void> _loadFonts() async {
  await loadAppFonts();
  for (final family in ['Noto Sans KR']) {
    final loader = FontLoader(family);
    for (final path in ['C:/Windows/Fonts/NotoSansKR-VF.ttf', 'C:/Windows/Fonts/malgun.ttf']) {
      final file = File(path);
      if (!file.existsSync()) continue;
      loader.addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
      break;
    }
    await loader.load();
  }
}

void main() {
  final dll = File('../engine/target/release/archive_engine.dll');
  test('층별 시간', () async {
    if (_db.isEmpty || !File(_db).existsSync() || !dll.existsSync()) {
      markTestSkipped('DB를 주어야 잰다');
      return;
    }
    await _loadFonts();
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    final info = await engine.start(File(_db).absolute.path);
    final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from((await engine.call({'op': 'layout'}))['data'] as Map));
    const width = 1920.0, height = 1020.0;
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(width, height)
      ..setExtent(double.parse(meta['min'] as String), double.parse(meta['max'] as String))
      ..setContentHeight(layout.totalHeight);
    final scene = TimelineScene(
      controller: controller, layout: layout, fetchTile: engine.tile,
      ask: (query) async => Map<String, dynamic>.from((await engine.call(query))['data'] as Map),
    );
    addTearDown(scene.dispose);
    scene.applyLayoutToView();
    controller.resize(width, height);
    final min = double.parse(meta['min'] as String), max = double.parse(meta['max'] as String);
    final span = double.parse(_years) * 525960, mid = (min + max) / 2;
    controller.showRange(mid - span / 2, mid + span / 2);
    final mag = double.parse(_mag);
    if (mag != 1) controller.magnifyTo(mag, const ui.Offset(width / 2, height / 2));
    final text = AtlasText()
      ..maxNewPerFrame = 4000
      ..budgetMicros = 2000000;
    addTearDown(text.dispose);
    final painter = TimelinePainter(scene, text: text);

    void paint() {
      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const ui.Size(width, height));
      recorder.endRecording().dispose();
    }

    // 데우기: 타일 · 이름 자리 · 글자가 준비될 때까지.
    for (int i = 0; i < 200; i++) {
      paint();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      scene.tick(20);
    }
    // 재기: 장면마다 0.2%씩 옆으로 끈다(자료를 기다리지 않는다).
    TimelinePainter.profile = true;
    TimelinePainter.layerMicros.clear();
    final frames = int.parse(_frames);
    final watch = Stopwatch()..start();
    for (int i = 0; i < frames; i++) {
      final v = controller.view;
      controller.showRange(v.lo + v.span * .002, v.lo + v.span * 1.002);
      paint();
      if (i % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
        scene.tick(7);
      }
    }
    watch.stop();
    TimelinePainter.profile = false;
    final rows = TimelinePainter.layerMicros.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = rows.fold<int>(0, (n, e) => n + e.value);
    // ignore: avoid_print
    print('장면 $frames장 · 평균 ${(watch.elapsedMicroseconds / frames / 1000).toStringAsFixed(2)}ms(재는 틈 포함) · 층 합 ${(total / frames / 1000).toStringAsFixed(2)}ms · 도형 ${scene.stats.shapes} · 글줄 ${scene.stats.labels} · 타일 ${scene.stats.tiles}');
    for (final e in rows) {
      // ignore: avoid_print
      print('  ${e.key.padRight(28)} ${(e.value / frames / 1000).toStringAsFixed(3)}ms');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

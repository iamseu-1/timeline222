// 0.1.1 감독 지적 '신라 쪽 휠 해보면 신라 이름표 자체가 튀어나가'(2026-10-26 04:1x): 휠로 넓혀 보며 빈 줄이 다시 펴질 때(동아시아 + 감독 DLC —
// 신라 위 변한 줄) 줄의 몫은 0에서 자라는데 그 줄의 띠 · 머리 이름은 다 자란 키로 그려져, 아래 줄(신라)의 띠와 이름 위에 겹쳤다('신변한').
// 이제 흐르는 줄의 띠는 보이는 몫([SceneLayout.rowClip])에서 잘리고, 머리 이름은 이름 색줄이 그 몫에 다 들 때만 선다 — 늘 제 띠 안 · 아래 띠 위로 넘치지 않음.
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart';
import 'support/scene_text.dart';
import 'support/tile_builder.dart';

const m = 1000000.0;

(TimelineScene, TimelinePainter) make() {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(210);
  final ppm = 32 / bucketMinutes(9);
  controller.showRange(0, (1920 - SceneView.gutter) / ppm);
  final bytes = (TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(1, 1, 2 * m, 10 * m, '변한', color: 0xacb4ca)
        ..band(2, 2, 1 * m, 10 * m, '신라', color: 0x9cc4a8))
      .build();
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(twoTrackLayout()),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  scene.hide.add('fade');
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

void paintOnce(TimelinePainter painter) {
  for (int i = 0; i < 20 && (i == 0 || painter.text.starved); i++) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }
}

void main() {
  test('다시 펴지는 줄의 띠 · 머리 이름은 자라는 동안 제 몫 안 — 아래 줄의 띠 위로 넘치지 않는다', () async {
    final (scene, painter) = make();
    for (int i = 0; i < 40; i++) {
      scene.prepare();
      await pumpEventQueue();
    }
    final layout = scene.layout;
    layout.setFolded({1});
    layout.finishFlow();
    paintOnce(painter);
    expect(painter.debugBands.where((b) => b.id == 1), isEmpty, reason: '접힌 줄에는 띠가 없다');
    layout.setFolded(const {});
    expect(layout.rowClip(1), 0, reason: '펴지기 시작 — 보일 몫이 아직 없다');
    var sawCut = false, sawName = false;
    for (int step = 0; step < 40 && layout.flowing; step++) {
      layout.tickFlow(16);
      paintOnce(painter);
      final below = painter.debugBands.firstWhere((b) => b.id == 2).rect;
      final grown = painter.debugBands.where((b) => b.id == 1).map((b) => b.rect).toList();
      for (final r in grown) {
        expect(r.bottom, lessThanOrEqualTo(below.top + .5), reason: '장면 $step: 펴지는 띠가 아래 띠($below)를 덮음 — $r');
      }
      final clip = layout.rowClip(1);
      if (clip != null && grown.isNotEmpty && grown.first.height + .5 < layout.geo(1).bandHeight) sawCut = true;
      for (final tab in painter.debugLabels.where((l) => l.kind == 'tab' && l.text == '변한')) {
        sawName = true;
        expect(grown, isNotEmpty, reason: '장면 $step: 띠 없이 이름만');
        final band = grown.first;
        expect(tab.at.dy, greaterThanOrEqualTo(band.top - .5), reason: '장면 $step: 이름이 띠 위로 나감');
        expect(tab.at.dy + 9 * 1.2, lessThanOrEqualTo(band.bottom + .5), reason: '장면 $step: 이름이 띠($band) 아래로 나감 — ${tab.at}');
        expect(tab.at.dy + 9 * 1.2, lessThanOrEqualTo(below.top + .5), reason: '장면 $step: 이름이 아래 띠 위에 겹침');
      }
    }
    expect(sawCut, isTrue, reason: '자라는 동안 띠가 몫에서 잘린 장면이 있어야 한다');
    layout.finishFlow();
    paintOnce(painter);
    expect(painter.debugLabels.where((l) => l.kind == 'tab' && l.text == '변한'), isNotEmpty, reason: '다 펴진 뒤에는 이름이 선다');
    expect(sawName || layout.rowClip(1) == null, isTrue);
    expect(painter.debugBands.firstWhere((b) => b.id == 1).rect.height, closeTo(layout.geo(1).bandHeight, .01), reason: '다 펴진 띠는 제 키 그대로');
  });
}

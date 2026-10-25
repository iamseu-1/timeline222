// 장면 만들기 도움 — painter_test.dart의 것을 글자 그대로 옮기고 make에만 text · clearType · clock · gate · labelHold 인자를 더했다(옆 세션도 만지는 파일이라 원본은 그대로 둔다).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/labels.dart' show placeLabels;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/text_paragraph.dart' show SceneText;
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tile_builder.dart';

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

SceneLayout layout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1)]}],
  'epochs': [{'id': 1, 'pack': 1, 'start': 0, 'end': 900000000, 'color': 0xc8b193, 'name': '첫째 시대'}],
});

const m = 1000000.0; // 백만 분

/// 단계 9의 타일 0과 1. 1번 띠는 두 타일에 걸치고 화면 왼쪽 밖에서 시작한다.
Map<(int, int), Uint8List> tiles() {
  final left = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, 50 * m, 67108864, '별여울국', flags: Tile.clipRight)
    ..cell(10, 0, 55 * m, 67108864, '첫째 지도자', flags: Tile.clipRight)
    // 끝 미정인 띠의 바탕은 제 색의 6%뿐이라, 꼬리의 짙기를 재려면 종이와 또렷이 다른 색이어야 한다.
    ..band(3, 1, 60 * m, 65 * m, '은빛 나루', color: 0x202020, flags: Tile.fuzzyEnd);
  final right = TileBuilder(level: 9, x: 1, chunk: 0)
    ..band(1, 0, 0, 2 * m, '별여울국', flags: Tile.clipLeft)
    ..cell(10, 0, 0, 2 * m, '첫째 지도자', flags: Tile.clipLeft)
    ..band(2, 0, 2.5 * m, 4.5 * m, '해솔국')
    ..cell(11, 0, 2.5 * m, 2.7 * m, '해솔 내각', kind: 2);
  final top = TileBuilder(level: 11, x: 0, chunk: 0)..band(1, 0, 50 * m, 69.108864 * m, '별여울국');
  return {(9, 0): left.build(), (9, 1): right.build(), (11, 0): top.build()};
}

/// 1920×1080 · 통 32px(단계 9) · 타일 경계(67.1백만 분)가 화면 안에 오는 보기.
/// [clock]: 장면 시계(없으면 실제 시계) · [gate]: 주면 타일 받기가 그것이 끝날 때까지 기다린다(타일을 기다리는 장면).
/// [labelHold]: 주면 이름 자리를 이 자리에서 셈하되(작업자 대신) 판마다 그것이 돌려준 것이 끝날 때까지 기다린다(이름 판을 기다리는 장면).
(TimelineScene, TimelinePainter, List<(int, int)>) make({Set<(int, int)>? only, SceneText? text, bool clearType = true, double Function()? clock, Future<void>? gate,
    Future<void> Function()? labelHold}) {
  final controller = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(284);
  final span = (1920 - SceneView.gutter) / (32 / bucketMinutes(9));
  controller.showRange(57.1 * m, 57.1 * m + span);
  final asked = <(int, int)>[];
  final data = tiles();
  final scene = TimelineScene(
    controller: controller,
    layout: layout(),
    clock: clock,
    labelCompute: labelHold == null
        ? null
        : (input) async {
            await labelHold();
            return placeLabels(input);
          },
    fetchTile: (level, x, chunk, packs) async {
      asked.add((level, x));
      if (gate != null) await gate;
      final bytes = data[(level, x)];
      if (bytes == null || chunk != 0 || (only != null && !only.contains((level, x)))) {
        return (TileBuilder(level: level, x: x, chunk: chunk)).build();
      }
      return bytes;
    },
  );
  return (scene, TimelinePainter(scene, text: text, clearType: clearType)..debug = true, asked);
}

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
}

Future<void> loadAll(TimelineScene scene) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
}

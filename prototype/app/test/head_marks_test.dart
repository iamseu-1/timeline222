import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/schema4_items.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 감독 2026-10-26 수정 5 — 구멍 · 꼬리 마름모가 머리 줄의 글을 가리지 않게(구멍을 옮기지 않고 글이 비킨다).
// 머리 줄(이름 색줄)에 덧붙는 글(실권 끝 이름 · 칸 층 없는 꼬리표의 집권 · 실권 이름)은 [BandLayer.headTextBounds] 안에만 선다 —
// 왼쪽은 구멍 가운데 + [TagLook.markClear](띠의 맨 앞이 화면 안일 때), 오른쪽은 띠 끝 − [TagLook.nameRight](머리 이름과 같은 끝 · 마름모 자리).
// 띠 층 시험(bands_paint_test.dart)의 장면 짓기를 줄여 옮겼다.

const m = 1000000.0;
const sample = 0xacb4ca;

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 160, 'band_top': 19, 'band_h': 141, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

/// 1920×1080 · 단계 9의 타일 하나로 장면을 만든다. [from]은 화면 왼쪽 끝의 시각(분)이다.
(TimelineScene, TimelinePainter) make(void Function(TileBuilder) build, {double from = 0}) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(480);
  final ppm = 32 / bucketMinutes(9);
  controller.showRange(from, from + (1920 - SceneView.gutter) / ppm);
  final builder = TileBuilder(level: 9, x: 0, chunk: 0);
  build(builder);
  final bytes = builder.build();
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
      'tracks': [
        {'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1)]},
      ],
    }),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  scene.hide.add('fade');
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
  scene.prepare();
  for (int i = 0; i < 20 && (i == 0 || painter.text.starved); i++) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('머리 줄 글의 끝 — 왼쪽은 구멍 가운데 + 5(맨 앞이 화면 밖이면 없음), 오른쪽은 띠 끝 − 15(마름모 자리)', () async {
    final (scene, painter) = make((t) => t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample));
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final v = scene.controller.view;
    final l = v.xOf(2 * m), r = v.xOf(10 * m);
    expect(painter.bands.headTextBounds(1, l, r, SceneView.gutter), (l + TagLook.holeAt(TagEnd.cham, G.head) + TagLook.markClear, r - TagLook.nameRight));
    expect(TagLook.holeAt(TagEnd.cham, G.head) + TagLook.markClear, 12, reason: '구멍 가운데 7 + 반지름 2.5 + 테 1 + 1.5');
    expect(painter.bands.headTextBounds(1, SceneView.gutter - 5, r, SceneView.gutter).$1, double.negativeInfinity, reason: '구멍이 화면 밖이면 왼쪽 끝을 걸지 않는다');
  });

  test('실권이 띠 끝까지 가도 끝 이름은 꼬리 마름모 자리 앞(띠 끝 − 15)에서 끝난다 — 밑줄은 그대로 띠 끝 − 3까지', () async {
    final (scene, painter) = make((t) {
      t.band(1, 0, 2 * m, 10 * m, '별여울국', color: sample);
      t.item(Schema4.secPowerLine, 1, 0, 6 * m, 10 * m, ref: 1, name: '북설 칸국', color: 0x8b6f47, text2: 'p/holder');
    });
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final rect = painter.debugBands.single.rect;
    final name = painter.debugLabels.singleWhere((l) => l.kind == 'powerName');
    expect(name.text, '북설 칸국');
    final zones = painter.bands.headNameZones[0]!;
    final end = zones.last.$2 - 4; // 끝 이름 구간(앞뒤 4)의 오른쪽 — 이름 끝
    expect(end, lessThanOrEqualTo(rect.right - TagLook.nameRight + .01), reason: '마름모(띠 끝 − 7 ± 3)와 겹치지 않게 머리 이름과 같은 끝에서');
    expect(end, closeTo(rect.right - TagLook.nameRight, .01), reason: '비켜 선 만큼만 왼쪽으로(이름을 빼지 않는다)');
    final line = [for (final v in painter.debugSink.notes['실권밑줄'] ?? const <Object>[]) '$v'].single;
    final parts = line.split(' ')[1].split(',').map(double.parse).toList();
    expect((parts[0] + parts[2]) / 10, closeTo((rect.right - 3).roundToDouble(), 1), reason: '밑줄은 실권 끝(띠 안 3px 안쪽)까지 그대로');
  });
}

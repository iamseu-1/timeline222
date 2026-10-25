import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/unions.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 동군연합 이음줄(건의 8의 6-다 · 2026-10-14): 같은 사람이 같은 때 두 나라의 지도자이면 겹친 기간의 가운데에서 두 지도자 칸을 꿰는 줄과 끝의 고리.
// 두 나라는 다른 트랙일 수 있다(견본은 모두 그렇다) — 줄은 트랙 사이를 띠 뒤로 지난다. 한쪽 칸이 없으면 보이는 칸의 이름 앞에 겹고리 표지.
// 자료는 내보내기 구역 49(끝마다 하나 · 짝은 text2) — prototype/scripts/export/links.mjs.

final ppm = 32 / bucketMinutes(9);
double at(double px) => px / ppm;

/// style에 함께 실리는 순번(계약 6-2: 비트 15~26 = 순번 + 1).
int seq(int i) => (i + 1) << 15;

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': 2, 'rail_top': 0, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'dep': 0, 'zones': 0, 'hem': 0,
};

/// 트랙 둘 — 가람 갈래(줄 0) · 포구 갈래(줄 1). 둘 다 지도자 단이 있다.
SceneLayout layout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '가람 갈래', 'color': 0xa0bcc5, 'leader': 1, 'rail_levels': 2, 'rows': [row(0)]},
    {'id': 2, 'pack': 1, 'ord': 1, 'name': '포구 갈래', 'color': 0xc8b193, 'leader': 1, 'rail_levels': 2, 'rows': [row(1)]},
  ],
});

const tip = '동군연합 · 넷째 임금 — 가람 나라 · 포구 나라 · 1470년 ~ 1480년';

/// 가람 나라(띠 1 · 줄 0)의 넷째 임금(순번 3) · 포구 나라(띠 2 · 줄 1)의 둘째 임금(순번 1)이 같은 사람 — 겹친 기간의 가운데 700px(끝은 가운데 + 겹친 길이).
/// [both]가 거짓이면 포구 쪽 끝(과 그 칸)이 없다 — 표지 꼴.
Uint8List tile({bool both = true}) {
  final t = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, at(100), at(1600), '가람 나라', color: 0xa0bcc5)
    ..cell(10, 0, at(150), at(400), '셋째 임금', kind: 1, style: seq(2))
    ..cell(11, 0, at(400), at(1000), '넷째 임금', kind: 1, style: seq(3))
    ..item(49, 1, 0, at(700), at(900), ref: 1, name: tip, a: 3, b: 2, c: 1, text2: 'k1');
  if (both) {
    t
      ..band(2, 1, at(300), at(1500), '포구 나라', color: 0xc8b193)
      ..cell(20, 1, at(350), at(600), '포구 첫 임금', kind: 1, style: seq(0))
      ..cell(21, 1, at(600), at(900), '넷째 임금', kind: 1, style: seq(1))
      ..item(49, 2, 1, at(700), at(900), ref: 2, name: tip, a: 1, b: 1, c: 3, text2: 'k1');
  }
  return t.build();
}

(TimelineScene, TimelinePainter) make({bool both = true}) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..setContentHeight(600);
  controller.showRange(0, at(1920 - SceneView.gutter));
  final bytes = tile(both: both);
  final scene = TimelineScene(
    controller: controller,
    layout: layout(),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  return (scene, TimelinePainter(scene)..debug = true);
}

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
  for (int i = 0; i < 5; i++) {
    paint(painter);
  }
}

void main() {
  test('두 지도자 칸을 겹친 기간의 가운데에서 꿰는 줄 하나 — 위 칸 아랫변에서 아래 칸 윗변까지 · 평소 짙기 .5', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final v = scene.controller.view, layout = scene.layout;
    expect(painter.unions.debugLines, hasLength(1));
    final (x, y0, y3, alpha) = painter.unions.debugLines.single;
    expect(x, closeTo(v.xOf(at(700)), 1e-6));
    expect(y0, closeTo(v.yOf(layout.rowTop(0) + layout.geo(0).leaderTop + G.leader), 1e-6), reason: '가람 쪽 칸의 아랫변');
    expect(y3, closeTo(v.yOf(layout.rowTop(1) + layout.geo(1).leaderTop), 1e-6), reason: '포구 쪽 칸의 윗변(다른 트랙)');
    expect(alpha, UnionLook.rest);
    expect(painter.unions.debugMarks, isEmpty, reason: '줄을 그으면 표지는 없다');
  });

  test('줄에 올리면(같은 두 띠의 선 올림) 짙기 1 · 맞히기는 두 띠와 풍선 글', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final (x, y0, y3, _) = painter.unions.debugLines.single;
    final hit = painter.unions.hitUnion(x + 1, (y0 + y3) / 2);
    expect(hit?.$1, 1);
    expect(hit?.$2, 2);
    expect(hit?.$3, tip);
    expect(painter.unions.hitUnion(x + 20, (y0 + y3) / 2), isNull);
    SceneMarks.of(scene)
      ..hotLink = (2, 1)
      ..version += 1;
    paint(painter);
    expect(painter.unions.debugLines.single.$4, 1);
  });

  test('한쪽 칸이 없으면 줄 대신 보이는 칸의 이름 앞에 겹고리 표지', () async {
    final (scene, painter) = make(both: false);
    addTearDown(scene.dispose);
    await settle(scene, painter);
    expect(painter.unions.debugLines, isEmpty);
    expect(painter.unions.debugMarks, hasLength(1));
    final (band, ref, left) = painter.unions.debugMarks.single;
    expect(band, 1);
    expect(ref, 'leader:3');
    final cell = painter.strips.drawnCell(1, 'leader:3')!;
    expect(left + 2 * UnionLook.ring + UnionLook.pairGap, closeTo(cell.textL - UnionLook.markGap, 1e-6), reason: '이름 2px 앞에서 끝난다');
    expect(left, greaterThanOrEqualTo(cell.l + UnionLook.markInset), reason: '칸 안쪽에만');
  });

  test('조감에는 지도자 칸이 없어 줄도 표지도 없다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    scene.applyConditions(scene.layout.conditions.copyWith(density: 2));
    await settle(scene, painter);
    expect(painter.unions.debugLines, isEmpty);
    expect(painter.unions.debugMarks, isEmpty);
  });
}

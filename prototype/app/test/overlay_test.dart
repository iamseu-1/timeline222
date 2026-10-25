import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/scene_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 맨 위 층(paint/overlay.dart)의 검사 — 도착 고리(명세 06의 4-4 · css/common.css 1166~1174).
// 띠는 상자 안쪽 고리(띠 밖으로 넘치지 않는다) · 사건 점은 5px 밖 · 트랙은 옅은 바탕까지.
// 600ms(css --t-ring) 동안 한 번 옅어지고 되풀이하지 않으며, 움직임 줄이기에서는 그리지 않는다.
// 견본의 이름은 모두 가상이다.

const m = 1000000.0;

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 160, 'band_top': 19, 'band_h': 141, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

SceneLayout layout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1)]},
    {'id': 2, 'pack': 1, 'ord': 1, 'name': '별여울 갈래', 'rows': [row(2)]},
  ],
});

/// 1920×1080 · 단계 9의 타일 하나로 장면을 만든다. 시계는 검사가 쥔다([now]).
(TimelineScene, TimelinePainter, void Function(double)) make() {
  double clock = 0;
  final controller = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(480);
  final ppm = 32 / bucketMinutes(9);
  controller.showRange(0, (1920 - SceneView.gutter) / ppm);
  final builder = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(7, 0, 2 * m, 8 * m, '달무리국')
    ..band(8, 1, 2 * m, 8 * m, '바람뜰국')
    ..event(31, 0, 4 * m, '달무리의 기록', band: 7);
  final bytes = builder.build();
  final scene = TimelineScene(
    controller: controller,
    layout: layout(),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
    // 이름 자리는 그 자리에서 셈한다(사건이 든 다른 검사들과 같다). 주지 않으면 뒤의 작업자(isolate)가 셈하는데, 사건 점은 그 답이
    // 온 뒤에야 그려진다 — [settle]은 사건 고리를 정해진 횟수만 돌 뿐이라, 기기가 바쁘면 답이 오기 전에 그려 점이 없었다.
    labelCompute: (input) async => placeLabels(input),
    clock: () => clock,
  );
  scene.hide.add('fade');
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true, (double at) => clock = at);
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
  scene.prepare();
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), const ui.Size(1920, 1080));
  recorder.endRecording().dispose();
}

/// 한 장면을 그리고 고리가 남긴 기록을 돌려준다.
List<String> draw(TimelineScene scene, TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), const ui.Size(1920, 1080));
  recorder.endRecording().dispose();
  return [for (final note in painter.debugSink.notes['고리'] ?? const []) '$note'];
}

String? find(List<String> notes, String head) {
  for (final note in notes) {
    if (note.startsWith(head)) return note;
  }
  return null;
}

void main() {
  test('띠에 건 고리는 띠 상자 안쪽에 그려지고 띠 밖으로 넘치지 않는다', () async {
    final (scene, painter, now) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    SceneMarks.of(scene).showRing(SceneRing(band: 7, at: scene.now));
    final notes = draw(scene, painter);
    final ring = find(notes, '띠 7');
    expect(ring, isNotNull, reason: '고른 띠에 고리가 선다');
    // 띠의 상자와 같은 자리여야 한다(띠 층이 적어 둔 기록과 견준다).
    final band = (painter.debugSink.bands).firstWhere((b) => b.id == 7);
    expect(ring, contains('${band.rect.left.round()},${band.rect.top.round()}~${band.rect.right.round()},${band.rect.bottom.round()}'));
    expect(ring, contains('반지름=10/10'), reason: '모서리는 띠와 같은 10');
    now(800);
    expect(find(draw(scene, painter), '띠 7'), isNull, reason: 'ring 스프링이 옅어지면 되풀이하지 않는다');
  });

  test('줄에 걸면 그 줄의 띠에, 트랙에 걸면 옅은 바탕까지', () async {
    final (scene, painter, _) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    SceneMarks.of(scene).showRing(SceneRing(row: 1, at: scene.now));
    final rowNotes = draw(scene, painter);
    expect(find(rowNotes, '띠 8'), isNotNull);
    expect(find(rowNotes, '띠 7'), isNull, reason: '다른 줄의 띠는 건드리지 않는다');

    SceneMarks.of(scene).showRing(SceneRing(track: 2, at: scene.now));
    final trackNote = find(draw(scene, painter), '트랙 2');
    expect(trackNote, isNotNull);
    expect(trackNote, contains('바탕'));
    final top = scene.layout.trackTop(1), height = scene.layout.trackHeight(1);
    expect(trackNote, contains('${scene.controller.view.yOf(top).round()}'));
    expect(height, greaterThan(0));
  });

  test('사건 점의 고리는 점에서 5px 밖에 선다', () async {
    final (scene, painter, _) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    SceneMarks.of(scene).showRing(SceneRing(event: 31, at: scene.now));
    final note = find(draw(scene, painter), '사건 31');
    expect(note, isNotNull);
    // 그려진 점의 자리와 같은 가운데여야 한다(사건 층의 기록과 견준다).
    final dot = painter.debugDots.firstWhere((d) => d.eventId == 31);
    expect(note, contains('가운데=${dot.at.dx.round()},${dot.at.dy.round()}'));
    // 보통 점은 7px이라 지름은 7 + 5 × 2 = 17이다.
    expect(note, contains('지름=17'));
  });

  test('600ms 동안 한 번 옅어지고, 다시 걸면 처음부터', () async {
    final (scene, painter, now) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final marks = SceneMarks.of(scene)..showRing(SceneRing(band: 7, at: 0));
    double alphaOf(List<String> notes) => double.parse(find(notes, '밝기=')!.substring('밝기='.length));
    expect(alphaOf(draw(scene, painter)), 1);
    now(300);
    final mid = alphaOf(draw(scene, painter));
    expect(mid, inExclusiveRange(0, 1));
    now(500);
    expect(alphaOf(draw(scene, painter)), lessThan(mid));
    now(800);
    expect(find(draw(scene, painter), '밝기='), isNull);
    // 다시 걸면 그 시각에서 처음부터.
    marks.showRing(SceneRing(band: 7, at: scene.now));
    expect(alphaOf(draw(scene, painter)), 1);
  });

  test('다리가 도착한 뒤 uid를 번호로 바꿔 고리를 싣는다', () async {
    final (scene, painter, _) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final asked = <Map<String, dynamic>>[];
    final bus = AppBus(
      ask: (query) async {
        asked.add(query);
        // 계약 2-1의 ids_of — 띠 하나를 찾아 준다.
        return {
          'bands': [
            {'uid': '달무리국', 'id': 7, 'row': 0, 'start': 0, 'end': 8 * m},
          ],
          'events': <Object>[],
        };
      },
      controller: scene.controller,
      scene: scene,
    );
    addTearDown(bus.dispose);
    LiveSceneBridge(bus).go(const GoRequest(0, 8 * m, fly: false, ring: '달무리국'));
    await pumpEventQueue();
    expect(asked.single['op'], 'ids_of');
    final ring = SceneMarks.of(scene).ring;
    expect(ring, isNotNull);
    expect(ring!.band, 7);
    expect(find(draw(scene, painter), '띠 7'), isNotNull, reason: '실린 고리가 그대로 그려진다');
  });

  test('움직임 줄이기면 그리지 않는다 · 빈 고리는 걷힌다', () async {
    final (scene, painter, _) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    final marks = SceneMarks.of(scene)..showRing(SceneRing(band: 7, at: scene.now));
    scene.controller.reduceMotion = true;
    expect(draw(scene, painter), isEmpty);
    scene.controller.reduceMotion = false;
    expect(draw(scene, painter), isNotEmpty);
    marks.showRing(const SceneRing(at: 0));
    expect(marks.ring, isNull);
    expect(draw(scene, painter), isEmpty);
  });
}

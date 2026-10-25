import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/row_labels.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/edge_hint.dart';
import 'package:archive_prototype/ui/settle_glue.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 정착 잇기(ui/settle_glue.dart)의 검사 — 명세 06의 4-3절.
// 움직이기 전에 보이던 단위를 찍어 두었다가, 줄 접힘이 다 흐른 뒤의 배치로 밀려난 것을 세어 `bus.slot('edge-hint')`에 싣는다.
// 견본의 이름은 모두 가상이다.

const m = 1000000.0;

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 160, 'band_top': 19, 'band_h': 141, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'cats': <int>[],
};

/// 트랙 둘 · 줄 다섯. 첫 트랙의 세 줄은 한 민족 묶음이다.
SceneLayout layout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xc27a45,
      'rows': [row(0), row(1), row(2)],
      'groups': [{'depth': 0, 'first': 0, 'count': 3, 'name': '해솔족', 'color': 0x8a9a7c, 'kind': 0}],
    },
    {'id': 2, 'pack': 1, 'ord': 1, 'name': '바람뜰 갈래', 'color': 0x6a8ac2, 'rows': [row(3), row(4)]},
  ],
});

/// 줄마다 대표 정권 하나를 넣은 줄 이름(자료 처리부 대신 검사가 바로 넣는다).
RowLabels labelsOf(List<String> names) {
  final labels = RowLabels();
  labels.accept({
    for (int r = 0; r < names.length; r++)
      r: [RowLabel(period: 'p$r', kind: RowLabel.band, name: names[r], color: 0xb08050, start: (-1000 * m).toInt(), end: (1000 * m).toInt())],
  });
  return labels;
}

(TimelineScene, AppBus, SettleGlue, void Function(double)) make() {
  double clock = 0;
  // 창이 낮아야(몸통 46px) 줄 다섯이 화면 밖으로 밀려난다 — 리메이크 2부로 줄이 머리 한 줄(띠 24)이 되어 다섯 줄이 170px뿐이다.
  final controller = TimelineController()
    ..resize(1920, 120)
    ..setExtent(-2000 * m, 2000 * m);
  final ppm = 32 / bucketMinutes(9);
  controller.showRange(0, (1920 - SceneView.gutter) / ppm);
  final scene = TimelineScene(
    controller: controller,
    layout: layout(),
    fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
    clock: () => clock,
  );
  controller.setContentHeight(scene.layout.totalHeight);
  final bus = AppBus(ask: (q) async => <String, dynamic>{}, controller: controller, scene: scene);
  final glue = SettleGlue(bus: bus, labels: labelsOf(['별여울국', '달무리국', '바람뜰국', '은빛나루국', '해뜰마을']))..start();
  return (scene, bus, glue, (double at) => clock = at);
}

/// 손으로 끄는 척: 쥐었다가(정착 깨짐) [between]으로 옮기고 놓은 뒤, 0.3초를 흘려 정착시킨다.
/// 쥔 뒤 장면을 두 번 돌리는 것은 실제와 같다 — 첫 장면에 정착이 풀리고, 다음 장면에 '움직이기 전'이 찍힌다.
void drag(TimelineScene scene, void Function(double) at, void Function() between) {
  final controller = scene.controller;
  controller.pointerDown(const Offset(600, 300), 0);
  scene.tick(16);
  scene.tick(16);
  between();
  controller.pointerUp(const Offset(600, 300), 16);
  at(16);
  scene.tick(16);
  at(400); // 놓고 0.3초 뒤에 정착한다(fold.dart의 settleWait)
  scene.tick(16);
}

EdgeHintReport? reportOf(AppBus bus) {
  final value = bus.slot(EdgeHint.slot).value;
  return value is EdgeHintReport ? value : null;
}

void main() {
  test('지금 배치의 단위 — 트랙 · 민족 묶음 · 줄의 대표 정권', () {
    final (scene, bus, glue, _) = make();
    addTearDown(scene.dispose);
    addTearDown(bus.dispose);
    final keys = [for (final p in glue.placements()) p.unit.key];
    expect(keys, containsAll(['t:1', 't:2', 'g:${scene.layout.groupKeyOf(scene.layout.tracks[0], scene.layout.tracks[0].groups[0])}', 'p:p0', 'p:p4']));
    final people = glue.placements().firstWhere((p) => p.unit.kind == HintKind.people);
    expect(people.unit.name, '해솔족');
    expect(people.unit.groupWord, '민족');
    // 묶음의 자리는 그 묶음이 품은 줄 전체다.
    expect(people.top, scene.layout.rowTop(0));
    expect(people.top + people.height, scene.layout.rowTop(2) + scene.layout.geo(2).height);
    glue.dispose();
  });

  test('손으로 끌어 내려가면 위로 밀려난 것을 싣는다', () {
    final (scene, bus, glue, at) = make();
    addTearDown(scene.dispose);
    addTearDown(bus.dispose);
    expect(reportOf(bus), isNull);
    drag(scene, at, () => scene.controller.scrollTo(scene.layout.totalHeight));
    final report = reportOf(bus);
    expect(report, isNotNull, reason: '정착한 그 순간에 알린다');
    expect(report!.up, isNotEmpty);
    expect(report.down, isEmpty);
    // 첫 트랙은 통째로 밀려났으니 그 트랙 하나로 묶인다(그 안의 정권 · 민족은 빼고).
    expect(report.up.first.kind, HintKind.track);
    expect(report.up.map((u) => u.name), contains('해솔 갈래'));
    glue.dispose();
  });

  test('한 번에 서는 가기는 옮기기 전에 찍어 둔 것으로 센다', () {
    final (scene, bus, glue, _) = make();
    addTearDown(scene.dispose);
    addTearDown(bus.dispose);
    // 다리가 옮기기 전에 부른다(LiveSceneBridge.go · 접기).
    glue.beginJump();
    scene.controller.scrollTo(scene.layout.totalHeight);
    final report = reportOf(bus);
    expect(report, isNotNull);
    expect(report!.up.map((u) => u.name), contains('해솔 갈래'));
    glue.dispose();
  });

  test('제자리에 서 있으면 아무것도 싣지 않는다', () {
    final (scene, bus, glue, at) = make();
    addTearDown(scene.dispose);
    addTearDown(bus.dispose);
    drag(scene, at, () {});
    expect(reportOf(bus), isNull, reason: '밀려난 것이 없으면 떠 있는 안내를 건드리지 않는다');
    glue.dispose();
  });

  test('듣기를 그만두면 더 싣지 않는다', () {
    final (scene, bus, glue, at) = make();
    addTearDown(scene.dispose);
    addTearDown(bus.dispose);
    glue.dispose();
    drag(scene, at, () => scene.controller.scrollTo(scene.layout.totalHeight));
    expect(reportOf(bus), isNull);
  });
}

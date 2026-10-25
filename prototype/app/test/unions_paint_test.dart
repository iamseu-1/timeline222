import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show TagLook;
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/unions.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/sphere_crowns.dart';
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
/// [person]이면 두 트랙을 문화권 하나(가람 포구권)에 넣고, 넷째 임금을 사람 띠(왕관 — 가람 나라 넷째 칸 · 포구 나라 둘째 칸)로 얹는다(리메이크 4단계 과제 4).
SceneLayout layout({bool person = false}) => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '가람 갈래', 'color': 0xa0bcc5, 'leader': 1, 'rail_levels': 2, 'rows': [row(0)], if (person) 'sphere': 'river'},
    {'id': 2, 'pack': 1, 'ord': 1, 'name': '포구 갈래', 'color': 0xc8b193, 'leader': 1, 'rail_levels': 2, 'rows': [row(1)], if (person) 'sphere': 'river'},
  ],
  if (person) 'spheres': [{'id': 'river', 'name': '가람 포구권', 'count': 2, 'default': true}],
  if (person)
    'sphereLines': [
      {'kind': 1, 'sphere': 'river', 'start': at(400).round(), 'end': at(1000).round(), 'name': '넷째 임금', 'uid': 'fig-4', 'data': '[{"uid":"band-1","cell":3},{"uid":"band-2","cell":1}]'},
    ],
});

/// 왕관 표: 가람 나라(띠 1 · 줄 0) · 포구 나라(띠 2 · 줄 1)(칸의 때는 이 층이 보지 않는다).
Map<String, CrownBand> crowns({bool both = true}) => {
  'band-1': const CrownBand(1, 0, null, null, []),
  if (both) 'band-2': const CrownBand(2, 1, null, null, []),
};

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

(TimelineScene, TimelinePainter) make({bool both = true, bool person = false, Future<Map<String, dynamic>> Function(Map<String, dynamic>)? ask}) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..setContentHeight(600);
  controller.showRange(0, at(1920 - SceneView.gutter));
  final bytes = tile(both: both);
  final scene = TimelineScene(
    controller: controller,
    layout: layout(person: person),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
    ask: ask,
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

  test('위 나라 꼬리표 밑 흰 사슬(감독 고름 G5 #9 나)의 종이 위에서는 줄을 맞히지 않는다 — 두 띠 사이의 몫은 종이 뒤라 보이지 않고 그 자리의 누름은 사슬 칸(검토 2026-10-25)', () async {
    // 줄 값이 실린 새 저장소 꼴: 가람 갈래(줄 0)는 왕조 · 지도자 칸 — 왕조는 꼬리표 밑 사슬 · 포구 갈래(줄 1)는 지도자 칸만.
    Map<String, dynamic> cellRow(int id, {required bool dynasty}) => {
      ...row(id),
      'variant': 0, 'rail': 0, 'cell_rows': 1, 'dynasty': dynasty ? 1 : 0, 'leader': 1, 'cabinet': 0, 'hang': 0, 'fig_wide': 0,
    };
    final layout = SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
      'tracks': [
        {'id': 1, 'pack': 1, 'ord': 0, 'name': '가람 갈래', 'color': 0xa0bcc5, 'dynasty': 1, 'leader': 1, 'rail_levels': 2, 'rows': [cellRow(0, dynasty: true)]},
        {'id': 2, 'pack': 1, 'ord': 1, 'name': '포구 갈래', 'color': 0xc8b193, 'leader': 1, 'rail_levels': 2, 'rows': [cellRow(1, dynasty: false)]},
      ],
    });
    // 띠 look: 비트 20 = 칸이 있다 · 21 + 0 왕조 · 21 + 5 지도자.
    final bytes = (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, at(100), at(1600), '가람 나라', color: 0xa0bcc5, look: 1 << 20 | 1 << 21 | 1 << 26)
          ..cell(30, 0, at(100), at(1600), '가람 왕조', kind: 0, style: seq(0), color: 0xd9a57a)
          ..cell(10, 0, at(150), at(400), '셋째 임금', kind: 1, style: seq(2))
          ..cell(11, 0, at(400), at(1000), '넷째 임금', kind: 1, style: seq(3))
          ..item(49, 1, 0, at(700), at(900), ref: 1, name: tip, a: 3, b: 2, c: 1, text2: 'k1')
          ..band(2, 1, at(300), at(1500), '포구 나라', color: 0xc8b193, look: 1 << 20 | 1 << 26)
          ..cell(20, 1, at(350), at(600), '포구 첫 임금', kind: 1, style: seq(0))
          ..cell(21, 1, at(600), at(900), '넷째 임금', kind: 1, style: seq(1))
          ..item(49, 2, 1, at(700), at(900), ref: 2, name: tip, a: 1, b: 1, c: 3, text2: 'k1'))
        .build();
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(1920, 1080)
      ..setExtent(-at(100000), at(100000))
      ..setContentHeight(600);
    controller.showRange(0, at(1920 - SceneView.gutter));
    final scene = TimelineScene(
      controller: controller,
      layout: layout,
      fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
    );
    addTearDown(scene.dispose);
    final painter = TimelinePainter(scene)..debug = true;
    await settle(scene, painter);
    final v = scene.controller.view, geo = scene.layout.geo(0);
    expect(geo.dynastyChained, isTrue);
    final (x, y0, y3, _) = painter.unions.debugLines.single;
    final bottom = v.yOf(scene.layout.rowTop(0) + geo.bandTop + geo.bandHeight);
    final dyn = v.yOf(scene.layout.rowTop(0) + geo.strip(0).$1);
    expect(dyn, greaterThan(y0));
    expect(dyn + G.chain, lessThan(y3), reason: '줄이 왕조 사슬 뒤를 지난다');
    // 사슬 종이 위: 줄이 아니라 왕조 칸.
    expect(painter.strips.chainAt(x, dyn + 7), isTrue);
    expect(painter.unions.hitUnion(x, dyn + 7), isNull);
    expect(painter.strips.hitStrips(x, dyn + 7)?.kind, 0);
    // 띠 안의 몫(띠 위에 그린 줄)과 사슬 밑 바탕은 예전처럼 줄.
    expect(painter.unions.hitUnion(x, (y0 + bottom) / 2)?.$3, tip);
    expect(painter.unions.hitUnion(x, dyn + G.chain + 1)?.$3, tip);
  });

  test('두 단 띠의 칸 끝 — 혼자인 조각은 층 전체의 아랫변 · 겹친 조각의 아래 단 칸은 그 단의 윗변(칸 그림 갈래 걸음 2) · 스위치 legit 끔이면 한 단 자리', () async {
    // 두 트랙 모두 줄 값이 실린 두 단 줄(fig_wide 26 ~ 27 = 1) · 띠는 sub 22 ~ 23 = 1(제 단 둘).
    // 가람 나라: 넷째 임금(단 0 · 150 ~ 1000) · 주장(단 1 · 150 ~ 400) → 700은 혼자인 조각(층 전체 28).
    // 포구 나라: 첫 임금(단 0 · 350 ~ 1200) · 넷째 임금(공동 · 단 1 · 600 ~ 900) → 700은 겹친 조각의 단 1(층 윗선 + 14부터).
    Map<String, dynamic> twoLaneRow(int id) => {...row(id), 'fig_wide': 1 << 3 | 1 << 17 | 1 << 26, 'variant': 0, 'rail': 0, 'cell_rows': 1, 'dynasty': 0, 'leader': 1, 'cabinet': 0, 'hang': 0};
    const look = 1 << 20 | 1 << 26, sub = 1 << 22;
    Future<(TimelineScene, TimelinePainter)> build({required bool legit}) async {
      PaintPick.legit = legit;
      addTearDown(PaintPick.reset);
      final layout = SceneLayout.fromJson({
        'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
        'tracks': [
          {'id': 1, 'pack': 1, 'ord': 0, 'name': '가람 갈래', 'color': 0xa0bcc5, 'leader': 1, 'rail_levels': 2, 'rows': [twoLaneRow(0)]},
          {'id': 2, 'pack': 1, 'ord': 1, 'name': '포구 갈래', 'color': 0xc8b193, 'leader': 1, 'rail_levels': 2, 'rows': [twoLaneRow(1)]},
        ],
      })..reduceMotion = true;
      final bytes = (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, at(100), at(1600), '가람 나라', color: 0xa0bcc5, look: look, sub: sub)
            ..band(2, 1, at(300), at(1500), '포구 나라', color: 0xc8b193, look: look, sub: sub)
            ..cell(11, 0, at(150), at(1000), '넷째 임금', kind: 1, style: seq(3))
            ..cell(12, 0, at(150), at(400), '주장 임금', kind: 1, lane: 1, style: seq(4))
            ..cell(20, 1, at(350), at(1200), '포구 첫 임금', kind: 1, style: seq(0))
            ..cell(21, 1, at(600), at(900), '넷째 임금', kind: 1, lane: 1, style: seq(1))
            ..item(49, 1, 0, at(700), at(900), ref: 1, name: tip, a: 3, b: 2, c: 1, text2: 'k1')
            ..item(49, 2, 1, at(700), at(900), ref: 2, name: tip, a: 1, b: 1, c: 3, text2: 'k1'))
          .build();
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 1080)
        ..setExtent(-at(100000), at(100000))
        ..setContentHeight(layout.totalHeight + 200);
      controller.showRange(0, at(1920 - SceneView.gutter));
      final scene = TimelineScene(
        controller: controller,
        layout: layout,
        fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      addTearDown(scene.dispose);
      final painter = TimelinePainter(scene)..debug = true;
      await settle(scene, painter);
      return (scene, painter);
    }

    double floorY(TimelineScene scene, int row) {
      final layout = scene.layout, geo = layout.geo(row);
      return scene.controller.view.yOf(layout.rowTop(row) + TagLook.compactOf(geo, look, geo.leaderTop, sub: sub));
    }

    final (scene, painter) = await build(legit: true);
    expect(scene.layout.geo(0).leaderLanes, 2);
    final (x, y0, y3, _) = painter.unions.debugLines.single;
    expect(x, closeTo(scene.controller.view.xOf(at(700)), 1e-6));
    expect(y0, closeTo(floorY(scene, 0) + 2 * G.floor, 1e-6), reason: '가람 쪽 칸은 혼자인 조각 — 층 전체(두 단)의 아랫변');
    expect(y3, closeTo(floorY(scene, 1) + G.floor, 1e-6), reason: '포구 쪽 칸은 겹친 조각의 단 1 — 그 단의 윗변');
    final (offScene, offPainter) = await build(legit: false);
    expect(offScene.layout.geo(0).leaderLanes, 1);
    final (_, offY0, offY3, _) = offPainter.unions.debugLines.single;
    expect(offY0, closeTo(floorY(offScene, 0) + G.leader, 1e-6), reason: '끔 — 한 단 자리(예전 셈)');
    expect(offY3, closeTo(floorY(offScene, 1), 1e-6));
  });

  group('사람 띠로 그린 사람(리메이크 4단계 과제 4 걸음 4 · 정한 것 #7)', () {
    test('사람 띠가 있어도 왕관 표에 없는 짝은 그대로 — 줄 하나', () async {
      final (scene, painter) = make(person: true);
      addTearDown(scene.dispose);
      await settle(scene, painter);
      expect(painter.unions.debugLines, hasLength(1));
    });

    test('두 끝이 왕관 칸(띠 번호 · 지도자 순번)인 짝은 줄도 표지도 없다 — 실 · 뿔 매듭이 잇는다', () async {
      final (scene, painter) = make(person: true);
      addTearDown(scene.dispose);
      scene.crowns.put(crowns(), scene.layout, store: scene.storeVersion);
      expect(scene.crowns.cells, {(1, 3), (2, 1)});
      await settle(scene, painter);
      expect(painter.unions.debugLines, isEmpty);
      expect(painter.unions.debugMarks, isEmpty);
    });

    test('끝 하나만 왕관 칸이어도 걷는다 · 한쪽 칸이 없을 때의 겹고리 표지도', () async {
      final (scene, painter) = make(person: true);
      addTearDown(scene.dispose);
      scene.crowns.put(crowns(both: false), scene.layout, store: scene.storeVersion);
      expect(scene.crowns.cells, {(1, 3)});
      await settle(scene, painter);
      expect(painter.unions.debugLines, isEmpty);
      expect(painter.unions.debugMarks, isEmpty);
      final (one, onePainter) = make(both: false, person: true);
      addTearDown(one.dispose);
      one.crowns.put(crowns(), one.layout, store: one.storeVersion);
      await settle(one, onePainter);
      expect(onePainter.unions.debugMarks, isEmpty);
    });

    test('왕관 표를 기다리는 동안은 쉰다(걷힐 줄이 한 장면 비치지 않게) · 사람 띠가 없는 자료는 기다리지 않는다', () async {
      final never = Completer<Map<String, dynamic>>();
      final (scene, painter) = make(person: true, ask: (q) => q['op'] == 'ids_of' ? never.future : Future.error(StateError('모름')));
      addTearDown(scene.dispose);
      await settle(scene, painter);
      expect(scene.crowns.pending, isTrue);
      expect(painter.unions.debugLines, isEmpty);
      final (bare, barePainter) = make(ask: (q) => q['op'] == 'ids_of' ? never.future : Future.error(StateError('모름')));
      addTearDown(bare.dispose);
      await settle(bare, barePainter);
      expect(bare.crowns.pending, isFalse);
      expect(barePainter.unions.debugLines, hasLength(1));
    });
  });
}

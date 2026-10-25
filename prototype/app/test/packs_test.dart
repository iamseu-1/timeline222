import 'dart:ui' as ui;

import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';

// 장면: 자료집 셋(1 · 2 · 3)이 트랙을 하나씩(줄 둘씩) 갖고, 8번은 트랙 없이 4번 줄에 사건만 덧붙인다(support/pack_scene.dart).
(TimelineScene, TimelinePainter, List<List<int>>) make() => makePackScene();

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 500));
  recorder.endRecording().dispose();
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 60; i++) {
    paint(painter);
    await pumpEventQueue();
  }
}

double bandTop(TimelinePainter painter, int id) => painter.debugBands.firstWhere((b) => b.id == id).rect.top;

/// 날짜 칸의 높이는 날짜 칸을 맡은 층이 줄 구성에 따라 정한다 — 세로를 보는 검사는 몸통 높이를 426으로 맞춰 두고 그 값으로 견준다.
double fitBody(TimelineScene scene, [double body = 426]) {
  scene.controller.resize(1920, scene.controller.view.head + body);
  return scene.controller.view.head;
}

/// 제 타일 없이 메움만으로 그린 자리.
List<DrawTile> bare(TimelineScene scene) => [
  for (final d in scene.draw)
    if (d.isCover && scene.draw.every((o) => o.isCover || o.key != d.key)) d,
];

void main() {
  test('자료집을 끄는 장면은 조회를 기다리지 않는다: 줄은 흐르며 새 자리로 가고 옛 타일로 메운다', () async {
    final (scene, painter, _) = make();
    await settle(scene, painter);
    final head = fitBody(scene);
    paint(painter);
    expect(bandTop(painter, 102), head + 142 * 2 + 19);
    scene.setPacks({2, 3, 8}); // 1번 자료집을 끈다 — 기다리지 않고 바로 그린다(줄은 360ms 흐른다 — 여기서는 다 흐른 자리를 본다)
    expect(scene.layout.flowing, isTrue);
    scene.tick(400);
    paint(painter);
    expect(scene.layout.isVisible(0), isFalse);
    expect(scene.stats.blanks, 0, reason: '빈 자리 없이 옛 조합의 타일로 메운다');
    expect(scene.draw.every((d) => d.isCover), isTrue);
    expect(painter.debugBands.map((b) => b.id), isNot(contains(100)), reason: '끈 자료집의 줄은 옛 타일에 들어 있어도 그리지 않는다');
    expect(bandTop(painter, 102), head + 19, reason: '아래 줄이 바로 올라온다');
    expect(scene.controller.view.bodyHeight, 426);
  });

  test('옛 타일은 새 타일이 올 때까지만 메움으로 쓰인다', () async {
    final (scene, painter, asked) = make();
    await settle(scene, painter);
    scene.setPacks({2, 3, 8});
    scene.tick(400); // 흐름을 끝낸다
    paint(painter);
    expect(scene.draw.where((d) => d.isCover), isNotEmpty);
    await settle(scene, painter);
    expect(asked.last, [2, 3, 8], reason: '다시 계산하지 않고 조회 조건만 바꿔 묻는다');
    expect(bare(scene), isEmpty, reason: '새 타일이 왔으니 메움은 물러난다(떠오르는 새 타일 밑에 깔린 것만 남는다)');
  });

  test('트랙 없이 사건만 덧붙인 자료집을 끄면 줄은 그대로고 사건만 준다', () async {
    final (scene, painter, asked) = make();
    fitBody(scene);
    scene.controller.scrollTo(142 * 4 - 100); // 4번 줄이 보이게
    await settle(scene, painter);
    expect(painter.debugDots.map((d) => d.eventId), contains(80));
    final tops = [for (int r = 0; r < 6; r++) scene.layout.rowTop(r)], height = scene.layout.totalHeight, top = scene.controller.view.top;
    scene.setPacks({1, 2, 3});
    scene.tick(400); // 흐름을 끝낸다
    expect([for (int r = 0; r < 6; r++) scene.layout.rowTop(r)], tops);
    expect(scene.layout.totalHeight, height);
    expect(scene.controller.view.top, top);
    await settle(scene, painter);
    expect(asked.last, [1, 2, 3]);
    expect(painter.debugDots.map((d) => d.eventId), isNot(contains(80)));
    expect(painter.debugDots.map((d) => d.eventId), contains(14));
  });

  test('위쪽 자료집을 꺼도 보던 줄은 화면에서 제자리에 머문다', () async {
    final (scene, painter, _) = make();
    final head = fitBody(scene);
    scene.controller.scrollTo(300); // 2번 줄(자료집 2)의 위 16px이 가려진 자리
    await settle(scene, painter);
    final v = scene.controller.view;
    final before = v.yOf(scene.layout.rowTop(2));
    expect(before, head - 16);
    scene.setPacks({2, 3, 8}); // 위의 두 줄(284px)이 빠진다
    scene.tick(400); // 흐름을 끝낸다
    expect(v.yOf(scene.layout.rowTop(2)), before);
    expect(v.top, 16);
    // 다시 켜면 위에 두 줄이 생기고, 보던 줄은 그대로.
    scene.setPacks({1, 2, 3, 8});
    scene.tick(400); // 흐름을 끝낸다
    expect(v.yOf(scene.layout.rowTop(2)), before);
    expect(v.top, 300);
  });

  test('보던 줄의 자료집을 끄면 그 아래에 남는 첫 줄이 그 자리를 잇는다', () async {
    final (scene, painter, _) = make();
    final head = fitBody(scene);
    scene.controller.scrollTo(284 + 142); // 3번 줄이 맨 위, 그 아래에 4번 줄
    await settle(scene, painter);
    final v = scene.controller.view;
    final before = v.yOf(scene.layout.rowTop(4));
    expect(before, head + 142);
    scene.setPacks({1, 3, 8}); // 보던 3번 줄(자료집 2)이 빠진다 → 그 아래 4번 줄이 제자리를 지킨다
    scene.tick(400); // 흐름을 끝낸다
    expect(v.yOf(scene.layout.rowTop(4)), before);
    expect(scene.layout.rowTop(1) - v.top, 0, reason: '빠진 줄의 자리에는 위에 남은 줄(1번)이 내려와 보인다');
  });

  test('자료집을 다 꺼도 장면은 버티고, 다시 켜면 돌아온다', () async {
    // DLC 관리 창이 마지막 하나까지 끌 수 있게 되었다(13물결) — 빈 조합에서도 줄 쌓기 · 그리기가 서야 한다.
    final (scene, painter, asked) = make();
    await settle(scene, painter);
    final height = scene.layout.totalHeight, requests = asked.length;
    scene.setPacks({});
    scene.tick(400); // 흐름을 끝낸다
    paint(painter);
    expect(scene.layout.enabledPacks, isEmpty);
    expect([for (int r = 0; r < 6; r++) scene.layout.isVisible(r)], everyElement(isFalse));
    expect(scene.layout.totalHeight, 0, reason: '보일 줄이 하나도 없다');
    expect(painter.debugBands, isEmpty, reason: '끈 자료집의 줄은 옛 타일에 들어 있어도 그리지 않는다');
    await settle(scene, painter);
    expect(asked.length, requests, reason: '받을 줄이 하나도 없으니 타일을 묻지 않는다');

    scene.setPacks({1, 2, 3, 8});
    scene.tick(400); // 흐름을 끝낸다
    paint(painter);
    expect(scene.layout.totalHeight, height);
    expect(bandTop(painter, 100), scene.controller.view.head + 19);
  });

  test('같은 조합으로 돌아오면 받아 둔 타일을 그대로 쓴다', () async {
    final (scene, painter, asked) = make();
    await settle(scene, painter);
    scene.setPacks({2, 3, 8});
    scene.tick(400); // 흐름을 끝낸다
    await settle(scene, painter);
    final requests = asked.length;
    scene.setPacks({1, 2, 3, 8});
    scene.tick(400); // 흐름을 끝낸다
    paint(painter);
    expect(bare(scene), isEmpty, reason: '처음 조합의 타일이 보관에 남아 있다');
    expect(scene.draw.where((d) => !d.isCover), isNotEmpty);
    await settle(scene, painter);
    expect(asked.length, requests, reason: '다시 묻지 않는다');
  });
}

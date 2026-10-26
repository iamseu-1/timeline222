import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/hit_test.dart';
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/gutter.dart' show GutterHit, GutterHitKind;
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/timeline_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart' show foldRow;
import 'support/tile_builder.dart';

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

TimelineScene makeScene({bool withEvents = false}) {
  final controller = TimelineController()..setExtent(-2.0e9, 3.0e7);
  final layout = SceneLayout.fromJson({
    'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
    'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [for (int i = 0; i < 12; i++) row(i)]}],
    'epochs': [],
  });
  controller.setContentHeight(layout.totalHeight);
  return TimelineScene(
    controller: controller,
    layout: layout,
    // 검사에서는 이름 자리를 같은 isolate에서 곧바로 계산한다(가짜 시계 아래에서는 진짜 작업자의 답이 오지 않는다).
    labelCompute: (input) async => placeLabels(input),
    fetchTile: (level, x, chunk, packs) async {
      final span = 256.0 * (1 << (2 * level));
      final tile = TileBuilder(level: level, x: x, chunk: chunk)..band(1, chunk * 8, 0, span, '별여울국', flags: 3);
      // 자료 범위 한가운데(-10억 분)에 사건 하나: 그 분을 품은 타일에만 싣는다.
      const at = -1.0e9;
      final origin = x * span;
      if (withEvents && chunk == 0 && at >= origin && at < origin + span) tile.event(100, 0, at - origin, '별여울의 기록', bits: 3 | 32);
      return tile.build();
    },
  );
}

Future<TimelineScene> pumpView(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final scene = makeScene();
  addTearDown(scene.dispose);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimelineView(scene: scene))));
  scene.controller.showAll();
  await tester.pumpAndSettle(const Duration(milliseconds: 20));
  return scene;
}

void main() {
  testWidgets('큰 화면과 가로 휴대폰 크기에서 예외 없이 그리고, 멎으면 장면을 더 만들지 않는다', (tester) async {
    for (final size in [const Size(1920, 1080), const Size(820, 410)]) {
      final scene = await pumpView(tester, size);
      expect(tester.takeException(), isNull);
      expect(scene.stats.shapes, greaterThan(0));
      expect(scene.busy.value, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: '멎어 있는 동안에는 시계가 돌지 않는다');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('휠은 기간을 확대하고 Ctrl + 휠은 돋보기다', (tester) async {
    final scene = await pumpView(tester, const Size(1920, 1080));
    final c = scene.controller;
    final span = c.view.span;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(900, 500)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
    await tester.pumpAndSettle(const Duration(milliseconds: 7));
    expect(c.view.span, lessThan(span));
    expect(c.view.mag, 1);
    final zoomed = c.view.span;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -240)));
    await tester.pumpAndSettle(const Duration(milliseconds: 7));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(c.view.mag, greaterThan(1.4));
    expect(c.view.ppm, closeTo((1920 - 240) / zoomed, 1e-12), reason: '돋보기는 1분의 폭을 바꾸지 않는다'); // 왼쪽 칸 240(리메이크 2부)
    // 배율 알약은 앱 틀(shell/mag_pill.dart)로 옮겼다 — 여기서는 조종부가 배율을 알리는 데까지만 본다.
    expect(c.magnification.value, c.view.mag);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('끌지 않고 사건의 점을 누르면 그 사건을 알린다', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scene = makeScene(withEvents: true);
    addTearDown(scene.dispose);
    final hits = <Hit>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimelineView(scene: scene, onHit: hits.add))));
    scene.controller.showAll();
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    final out = scene.labelOutput!, input = scene.labelBatch!.input;
    expect(out.shownCount, greaterThan(0));
    final c = out.shownCandidate[0];
    final at = Offset(scene.controller.view.xOf(input.at[c]), lineCenter(scene.controller.view, scene.layout, input.row[c], out.shownLine[0]));
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(hits.single.kind, HitKind.event);
    expect(hits.single.eventId, input.eventId[c]);
    // 끌고 나서 놓은 것은 누른 것이 아니다.
    final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(hits.length, 1);
    // 오른쪽 버튼은 누름이 아니다 — 메뉴만 뜬다(전에는 오른쪽 클릭이 왼쪽 클릭까지 함께 해서 상세 창이 같이 열렸다).
    final right = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await right.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(hits.length, 1, reason: '오른쪽 클릭은 알리지 않는다');
    // 오른쪽 버튼으로 끌어도 보기가 움직이지 않는다.
    final lo = scene.controller.view.lo;
    final drag = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await drag.moveBy(const Offset(-60, 0));
    await drag.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(scene.controller.view.lo, lo);
  });

  testWidgets('끌면 보기가 손을 따라온다', (tester) async {
    final scene = await pumpView(tester, const Size(1920, 1080));
    final c = scene.controller;
    // 전체 보기에서는 옮길 곳이 없으니 먼저 확대한다.
    c.showRange(-1.0e9, -0.9e9);
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    final lo = c.view.lo;
    final gesture = await tester.startGesture(const Offset(900, 500), kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(-10, 0));
    await gesture.moveBy(const Offset(-200, 0));
    expect(c.view.lo, closeTo(lo + 200 / c.view.ppm, 1));
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('터치 화면: 두 손가락을 벌리면 기간이 좁아지고 가운데의 시각은 제자리다 — 뗀 손가락은 누름이 아니다', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scene = makeScene(withEvents: true);
    addTearDown(scene.dispose);
    final hits = <Hit>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimelineView(scene: scene, onHit: hits.add))));
    final c = scene.controller;
    c.showRange(-1.0e9, -0.9e9);
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    final span = c.view.span, middle = c.view.minuteAt(1000);
    final one = await tester.startGesture(const Offset(900, 500), kind: PointerDeviceKind.touch, pointer: 11);
    final two = await tester.startGesture(const Offset(1100, 500), kind: PointerDeviceKind.touch, pointer: 12);
    expect(c.pinching, isTrue);
    await one.moveTo(const Offset(800, 500));
    await two.moveTo(const Offset(1200, 500));
    // 두 손가락 거리 200 → 400: 기간이 절반으로. 가운데(x = 1000)의 시각은 그대로.
    expect(c.view.span, closeTo(span / 2, span * .001));
    expect(c.view.minuteAt(1000), closeTo(middle, span * .001));
    await one.up();
    expect(c.pinching, isFalse);
    // 남은 손가락을 움직여도 장면이 튀지 않고, 떼어도 누름으로 치지 않는다.
    final lo = c.view.lo;
    await two.moveTo(const Offset(1300, 520));
    expect(c.view.lo, lo);
    await two.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(hits, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('머리 단 고정(리메이크 4단계 과제 3 걸음 4): 붙은 문화권 머리 단은 그 밑으로 지나가는 띠보다 누름 · 올림 · 차림표 맞히기를 먼저 받는다', (tester) async {
    tester.view.physicalSize = const Size(1920, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TimelineController()..setExtent(-2.0e9, 3.0e7);
    // 문화권 하나(시대 줄 하나 — 머리 단 상자 20 + 14 + 2 = 36) 밑에 줄 열둘 — 줄마다 그림판 끝까지 띠.
    final layout = SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
      'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'sphere': 'ember', 'rows': [for (int i = 0; i < 12; i++) foldRow(i)]}],
      'epochs': [],
      'spheres': [{'id': 'ember', 'name': '등불 분지권', 'count': 12, 'default': true}],
      'sphereLines': [{'kind': 2, 'sphere': 'ember', 'start': -2000000000, 'end': 0, 'name': '등불 시대', 'uid': 'ep-1'}],
    })..reduceMotion = true;
    controller.setContentHeight(layout.totalHeight);
    final scene = TimelineScene(
      controller: controller,
      layout: layout,
      labelCompute: (input) async => placeLabels(input),
      fetchTile: (level, x, chunk, packs) async {
        final span = 256.0 * (1 << (2 * level));
        final tile = TileBuilder(level: level, x: x, chunk: chunk);
        for (int r = chunk * 8; r < chunk * 8 + 8 && r < 12; r++) {
          tile.band(100 + r, r, 0, span, '별여울국 $r', flags: 3);
        }
        return tile.build();
      },
    );
    addTearDown(scene.dispose);
    final hits = <Hit>[];
    final gutterHits = <GutterHit>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimelineView(scene: scene, onHit: hits.add, onGutterHit: gutterHits.add))));
    controller.showAll();
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    final v = controller.view;
    expect(layout.totalHeight, greaterThan(v.bodyHeight + 120), reason: '내려 볼 만큼 키가 크다');
    controller.scrollTo(120);
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    final box = layout.sphereHeadBox(0, v)!;
    expect((box.top, box.height, box.stuck), (v.head, 36.0, true));
    final view = tester.state<TimelineViewState>(find.byType(TimelineView));
    // 붙은 상자 안(그림판 몫) — 그 밑에는 띠가 지나가지만 머리 단이 받는다.
    final onHead = Offset(900, v.head + 18);
    expect(bandAt(scene, onHead.dx, onHead.dy), isNot(0), reason: '상자 밑으로 띠가 지나간다');
    expect(view.hitAt(onHead).kind, HitKind.none);
    expect(view.scopeAt(onHead), isNull);
    await tester.tapAt(onHead, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect([for (final g in gutterHits) (g.kind, g.uid)], [(GutterHitKind.sphere, 'ember')]);
    expect(hits, isEmpty);
    // 상자 아래는 그대로 띠.
    final below = Offset(900, v.head + 36 + 60);
    final band = bandAt(scene, below.dx, below.dy);
    expect(band, isNot(0));
    expect(view.hitAt(below).kind, HitKind.band);
    await tester.tapAt(below, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(hits.single.bandId, band);
    expect(gutterHits, hasLength(1));
  });

  testWidgets('사람 띠(리메이크 4단계 과제 4 걸음 3): 그림판 몫의 사람 띠를 누르면 그 사람(GutterHitKind.person)이 앱 틀로 · 띠 밖의 상자는 접기 · 몸통 맞히기 · 차림표는 머리 단으로 친다', (tester) async {
    tester.view.physicalSize = const Size(1920, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TimelineController()..setExtent(-2.0e9, 3.0e7);
    // 문화권 하나 · 사람 띠 하나(자료 범위 가운데 −15억 ~ −5억 분 · 인물 uid fig-1) — 머리 단 상자 20 + 16 + 2 = 38.
    final layout = SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
      'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'sphere': 'ember', 'rows': [for (int i = 0; i < 3; i++) foldRow(i)]}],
      'epochs': [],
      'spheres': [{'id': 'ember', 'name': '등불 분지권', 'count': 3, 'default': true}],
      'sphereLines': [{'kind': 1, 'sphere': 'ember', 'start': -1500000000, 'end': -500000000, 'name': '은 하림', 'uid': 'fig-1', 'data': '[{"uid":"band-a","cell":0}]'}],
    })..reduceMotion = true;
    controller.setContentHeight(layout.totalHeight);
    final scene = TimelineScene(
      controller: controller,
      layout: layout,
      labelCompute: (input) async => placeLabels(input),
      fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
    );
    addTearDown(scene.dispose);
    final hits = <Hit>[];
    final gutterHits = <GutterHit>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimelineView(scene: scene, onHit: hits.add, onGutterHit: gutterHits.add))));
    controller.showAll();
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    final v = controller.view;
    final box = layout.sphereHeadBox(0, v)!;
    expect(box.height, 38);
    final view = tester.state<TimelineViewState>(find.byType(TimelineView));
    // 띠 가운데(−10억 분) · 띠 줄(머리 단 위 + 20 ~ + 36).
    final onBand = Offset(v.xOf(-1.0e9), box.top + 28);
    expect(view.hitAt(onBand).kind, HitKind.none);
    expect(view.scopeAt(onBand), isNull);
    await tester.tapAt(onBand, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect([for (final g in gutterHits) (g.kind, g.uid, g.cell)], [(GutterHitKind.person, 'fig-1', '')]);
    // 같은 줄의 띠 밖(−2억 분)은 그대로 문화권 접기.
    await tester.tapAt(Offset(v.xOf(-2.0e8), box.top + 28), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect([for (final g in gutterHits.skip(1)) (g.kind, g.uid)], [(GutterHitKind.sphere, 'ember')]);
    expect(hits, isEmpty);
  });

  testWidgets('터치 화면: 길게 누른 손가락은 떼어도 고르지 않는다(메뉴만 뜬다) · 짧게 누르면 고른다', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scene = makeScene(withEvents: true);
    addTearDown(scene.dispose);
    final hits = <Hit>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimelineView(scene: scene, onHit: hits.add))));
    scene.controller.showAll();
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    final out = scene.labelOutput!, input = scene.labelBatch!.input;
    final k = out.shownCandidate[0];
    final at = Offset(scene.controller.view.xOf(input.at[k]), lineCenter(scene.controller.view, scene.layout, input.row[k], out.shownLine[0]));
    final long = await tester.startGesture(at, kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 1000));
    await long.up(timeStamp: const Duration(milliseconds: 1000));
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(hits, isEmpty);
    await tester.tapAt(at, kind: PointerDeviceKind.touch);
    await tester.pump();
    expect(hits.single.kind, HitKind.event);
  });
}

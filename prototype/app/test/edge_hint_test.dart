import 'package:archive_prototype/scene/viewport.dart';
import 'package:archive_prototype/shell/parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/edge_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';

// 가장자리 안내 검사(명세 06의 4-3).
// 앞쪽은 밀려난 것을 셈하는 순수 함수 — 화면을 재지 않고 줄 배치(모델)의 자리만으로 센다.
// 뒤쪽은 알약: 뜨는 모습 · 칩 넷과 '외 n' · 6초 뒤 스스로 물러남 · 내용이 그대로면 다시 등장하지 않음 · 누르면 그 줄로.
// 견본의 이름은 모두 가상이다(Dart는 이름에 한글을 쓰지 못해 변수 이름만 로마자다).

HintUnit track(int id, String name) => HintUnit(key: 't:$id', kind: HintKind.track, name: name, trackId: id);

HintUnit people(int id, String key, String name, {required int first, required int count}) =>
    HintUnit(key: 'g:$id|$key', kind: HintKind.people, name: name, trackId: id, trackName: '$id번 갈래', groupFirst: first, groupCount: count);

HintUnit polity(int id, String uid, String name, {required int row}) =>
    HintUnit(key: 'p:$uid', kind: HintKind.polity, name: name, trackId: id, trackName: '$id번 갈래', uid: uid, row: row);

/// 줄 하나를 높이 100으로 잡은 배치.
HintPlacement at(HintUnit unit, double top, [double height = 100]) => HintPlacement(unit, top, height);

void main() {
  group('밀려난 것 셈하기(순수 함수)', () {
    test('보이던 것이 화면 아래로 나가면 아래 목록에 선다', () {
      final one = polity(1, 'p-star', '별여울국', row: 0);
      final report = pushedOut(before: {one.key}, after: [at(one, 900)], viewTop: 0, viewHeight: 400);
      expect(report.down.map((u) => u.name), ['별여울국']);
      expect(report.up, isEmpty);
    });

    test('그 시기에 그릴 것이 없어 사라진 줄은 밀려난 것이 아니다', () {
      final one = polity(1, 'p-star', '별여울국', row: 0);
      // 멎은 뒤의 배치에 자리가 없다(after에 넣지 않는다) → 알리지 않는다.
      expect(pushedOut(before: {one.key}, after: const [], viewTop: 0, viewHeight: 400).isEmpty, isTrue);
    });

    test('아직 보이는 것은 세지 않는다 — 문턱은 겹친 높이 > min(24, 높이/2)', () {
      final one = polity(1, 'p-star', '별여울국', row: 0);
      // 높이 100인 줄이 25px 남았으면 아직 보이는 것(25 > 24), 23px이면 밀려났다.
      expect(pushedOut(before: {one.key}, after: [at(one, 375)], viewTop: 0, viewHeight: 400).isEmpty, isTrue);
      expect(pushedOut(before: {one.key}, after: [at(one, 377)], viewTop: 0, viewHeight: 400).down.length, 1);
      // 높이 20인 줄은 절반인 10을 넘게 보여야 한다.
      final small = polity(1, 'p-small', '작은나라', row: 1);
      expect(pushedOut(before: {small.key}, after: [at(small, 389, 20)], viewTop: 0, viewHeight: 400).isEmpty, isTrue);
      expect(pushedOut(before: {small.key}, after: [at(small, 391, 20)], viewTop: 0, viewHeight: 400).down.length, 1);
    });

    test('트랙이 통째로 밀렸으면 그 트랙의 정권 · 민족은 빼고 트랙 하나로', () {
      final units = [
        at(track(1, '첫째 갈래'), 900, 300),
        at(people(1, 'g1', '해솔족', first: 0, count: 3), 900, 300),
        for (int i = 0; i < 3; i++) at(polity(1, 'p$i', '나라$i', row: i), 900 + i * 100),
      ];
      final report = pushedOut(before: {for (final p in units) p.unit.key}, after: units, viewTop: 0, viewHeight: 400);
      expect(report.down.map((u) => u.name), ['첫째 갈래']);
    });

    test('민족 묶음 안의 정권이 셋 이상이면 민족 하나로, 둘이면 정권 이름 그대로', () {
      final three = [
        at(people(1, 'g1', '해솔족', first: 0, count: 3), 900, 300),
        for (int i = 0; i < 3; i++) at(polity(1, 'p$i', '나라$i', row: i), 900 + i * 100),
      ];
      final a = pushedOut(before: {for (final p in three) p.unit.key}, after: three, viewTop: 0, viewHeight: 400);
      expect(a.down.map((u) => u.name), ['해솔족']);
      expect(a.down.single.small, '민족 · 3', reason: '칩의 작은 글은 민족 · 정권 수');

      final two = [
        at(people(2, 'g2', '은빛족', first: 0, count: 2), 900, 200),
        for (int i = 0; i < 2; i++) at(polity(2, 'q$i', '두나라$i', row: i), 900 + i * 100),
      ];
      final b = pushedOut(before: {for (final p in two) p.unit.key}, after: two, viewTop: 0, viewHeight: 400);
      expect(b.down.map((u) => u.name), ['두나라0', '두나라1']);
    });

    test('민족 안의 민족이 함께 밀렸으면 큰 쪽만', () {
      final units = [
        at(people(1, 'big', '큰해솔', first: 0, count: 6), 900, 400),
        at(people(1, 'small', '작은해솔', first: 0, count: 3), 900, 300),
        for (int i = 0; i < 4; i++) at(polity(1, 'p$i', '나라$i', row: i), 900 + i * 100),
      ];
      final report = pushedOut(before: {for (final p in units) p.unit.key}, after: units, viewTop: 0, viewHeight: 400);
      expect(report.down.map((u) => u.name), ['큰해솔']);
      expect(report.down.single.count, 4);
    });

    test('위 · 아래로 나누고 가까운 순으로 늘어놓는다', () {
      final units = [
        at(polity(1, 'u1', '위쪽 가까움', row: 0), 800),
        at(polity(1, 'u2', '위쪽 멂', row: 1), 600),
        at(polity(1, 'd1', '아래 가까움', row: 2), 1400),
        at(polity(1, 'd2', '아래 멂', row: 3), 1700),
      ];
      final report = pushedOut(before: {for (final p in units) p.unit.key}, after: units, viewTop: 1000, viewHeight: 400);
      expect(report.up.map((u) => u.name), ['위쪽 가까움', '위쪽 멂']);
      expect(report.down.map((u) => u.name), ['아래 가까움', '아래 멂']);
    });

    test('화면이 아니라 모델로 센다 — 같은 before라도 다 흐른 뒤의 자리로 답이 갈린다', () {
      final one = polity(1, 'p-star', '별여울국', row: 0);
      final before = {one.key};
      // 접히는 중의 자리(아직 아래)로 세면 밀려난 것이지만,
      expect(pushedOut(before: before, after: [at(one, 900)], viewTop: 0, viewHeight: 400).down.length, 1);
      // 다 접힌 뒤의 자리로 세면 화면 안이라 알리지 않는다.
      expect(pushedOut(before: before, after: [at(one, 100)], viewTop: 0, viewHeight: 400).isEmpty, isTrue);
    });

    test('보이는 단위 찍기 — 움직이기 전의 before는 이 함수로 만든다', () {
      final units = [
        at(polity(1, 'a', '가', row: 0), 0),
        at(polity(1, 'b', '나', row: 1), 350),
        at(polity(1, 'c', '다', row: 2), 500),
      ];
      expect(visibleUnits(units, 0, 400), {'p:a', 'p:b'});
    });
  });

  group('안내 알약', () {
    Future<(AppBus, EdgeHintReport)> pumpHint(WidgetTester tester, {int chips = 2}) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (scene, _, _) = makePackScene();
      addTearDown(scene.dispose);
      final bus = AppBus(ask: (q) async => <String, dynamic>{}, controller: scene.controller, scene: scene);
      addTearDown(bus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: Stack(children: [Positioned.fill(child: EdgeHint(bus: bus))])),
        ),
      );
      return (bus, EdgeHintReport(down: [for (int i = 0; i < chips; i++) polity(1, 'p$i', '나라$i', row: i)]));
    }

    testWidgets('보고가 오면 아래 알약이 떠오르고, 칩에 이름과 작은 글이 든다', (tester) async {
      final (bus, report) = await pumpHint(tester);
      bus.slot(EdgeHint.slot).value = report;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('아래로 밀려남'), findsOneWidget);
      expect(find.text('나라0'), findsOneWidget);
      expect(find.text('1번 갈래'), findsNWidgets(2), reason: '정권 칩의 작은 글은 트랙 이름');
      expect(find.text('↓'), findsOneWidget);
      // 바닥에서 16px 위.
      final pill = tester.renderObject<RenderBox>(find.byType(GlassCard).first);
      expect(1080 - (pill.localToGlobal(Offset.zero).dy + pill.size.height), closeTo(EdgeHint.below, .01));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('칩은 넷까지 보이고 나머지는 외 n', (tester) async {
      final (bus, report) = await pumpHint(tester, chips: 7);
      bus.slot(EdgeHint.slot).value = report;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('나라3'), findsOneWidget);
      expect(find.text('나라4'), findsNothing);
      expect(find.text('외 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('6초 뒤 스스로 물러난다', (tester) async {
      final (bus, report) = await pumpHint(tester);
      bus.slot(EdgeHint.slot).value = report;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('나라0'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('나라0'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('내용이 그대로면 다시 등장하지 않는다', (tester) async {
      final (bus, report) = await pumpHint(tester);
      bus.slot(EdgeHint.slot).value = report;
      await tester.pump();
      await tester.pumpAndSettle();
      double opacity() => tester.widgetList<Opacity>(find.descendant(of: find.byType(EdgeHint), matching: find.byType(Opacity))).first.opacity;
      expect(opacity(), 1);

      // 같은 내용(다른 객체)을 다시 알려도 제자리에 그대로 — 다시 떠오르지 않는다.
      bus.slot(EdgeHint.slot).value = EdgeHintReport(down: [...report.down]);
      await tester.pump();
      expect(opacity(), 1, reason: '다시 등장하면 이 순간 투명도가 0이다');

      // 내용이 바뀌어도 이미 떠 있던 알약은 제자리에서 내용만 바뀐다.
      bus.slot(EdgeHint.slot).value = EdgeHintReport(down: [...report.down, polity(1, 'p9', '아홉나라', row: 9)]);
      await tester.pump();
      expect(opacity(), 1);
      expect(find.text('아홉나라'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('칩을 누르면 보던 기간은 그대로 두고 그 줄로 가며 고리를 싣는다', (tester) async {
      final (bus, report) = await pumpHint(tester);
      bus.slot(EdgeHint.slot).value = report;
      await tester.pump();
      await tester.pumpAndSettle();
      final view = bus.controller.view;
      final (lo, span) = (view.lo, view.span);
      await tester.tap(find.text('나라1'));
      await tester.pump();
      final go = bus.go.value!;
      expect(go.row, 1);
      expect(go.ring, 'p1');
      expect(go.fly, isFalse);
      expect(go.lo, closeTo(lo, .001));
      expect(go.hi - go.lo, closeTo(span, .001), reason: '가로는 보던 그대로');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('✕를 누르면 물러난다', (tester) async {
      final (bus, report) = await pumpHint(tester);
      bus.slot(EdgeHint.slot).value = report;
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('✕'));
      await tester.pump();
      expect(find.text('나라0').hitTestable(), findsNothing, reason: '물러나는 동안 입력은 즉시 막는다');
      await tester.pumpAndSettle();
      expect(find.text('나라0'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('물러나는 도중 같은 보고가 오면 지금 밝기에서 다시 돌아온다', (tester) async {
      final (bus, report) = await pumpHint(tester);
      bus.slot(EdgeHint.slot).value = report;
      await tester.pumpAndSettle();
      await tester.tap(find.text('✕'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      double opacity() => tester.widgetList<Opacity>(find.descendant(of: find.byType(EdgeHint), matching: find.byType(Opacity))).first.opacity;
      final before = opacity();
      expect(before, inExclusiveRange(0, 1));
      bus.slot(EdgeHint.slot).value = EdgeHintReport(down: [...report.down]);
      await tester.pump();
      expect(opacity(), closeTo(before, .001), reason: '다시 열 때 밝기를 처음부터 세지 않는다');
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(find.text('나라0').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('위쪽 알약은 날짜 칸 아래 10px에 선다', (tester) async {
      final (bus, _) = await pumpHint(tester);
      bus.slot(EdgeHint.slot).value = EdgeHintReport(up: [polity(1, 'p0', '나라0', row: 0)]);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('위로 밀려남'), findsOneWidget);
      final pill = tester.renderObject<RenderBox>(find.byType(GlassCard).first);
      expect(pill.localToGlobal(Offset.zero).dy, closeTo(SceneView.rulerHeight + EdgeHint.above, .01));
      await tester.pumpWidget(const SizedBox());
    });
  });
}

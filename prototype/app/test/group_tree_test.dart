import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/ruler.dart' show minuteOfYear;
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/app_shell.dart';
import 'package:archive_prototype/shell/detail_panel.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/mag_pill.dart';
import 'package:archive_prototype/shell/zoom_buttons.dart';
import 'package:archive_prototype/timeline_view.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/detail_format3.dart';
import 'package:archive_prototype/ui/detail_group.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/group_tree.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';

// 단체 계보 창 · 법의 내력 · 의석 막대(설계 D5 결정 4 A · 7 A — docs/설계-10건/7-8-단체와-렌즈.md 9절)의 새 앱 몫.
// 고정 자료 test/fixtures/d5-windows.json은 견본 sample-groups + sample-lens를 내보내기(prototype/scripts/export/entities.mjs의
// groupWindowRefs — 웹 js/group-tree.js의 HT.groupTreeLayout을 그대로 부른 셈)로 낸 항목 기록이다. 이름은 모두 가상이다.

final _store = <String, Map<String, dynamic>>{
  for (final one in jsonDecode(File('test/fixtures/d5-windows.json').readAsStringSync()) as List) (one as Map)['uid'] as String: one.cast<String, dynamic>(),
};

Map<String, dynamic> rec(String uid) => (jsonDecode(_store[uid]!['json'] as String) as Map).cast<String, dynamic>();

const kap = 'sample-groups/gr-kap', east = 'sample-groups/gr-east', old = 'sample-groups/gr-old', newer = 'sample-groups/gr-new';

/// 항목 기록 + `ids_of`에 답하는 검사용 길. 보기는 740 ~ 1000년.
AppBus makeBus() {
  final controller = TimelineController()
    ..resize(1920, 1000)
    ..setExtent(minuteOfYear(0), minuteOfYear(2000))
    ..showRange(minuteOfYear(740), minuteOfYear(1000));
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [
        {'id': 1, 'name': '단체 견본', 'events': 3},
      ],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('계보 창 검사는 타일을 읽지 않는다'),
  );
  return AppBus(
    ask: (query) async {
      switch (query['op']) {
        case 'entity':
          final row = _store[query['uid']];
          if (row == null) throw StateError('없는 항목');
          return row;
        case 'ids_of':
          return {'bands': const [], 'events': const []};
      }
      return const {};
    },
    controller: controller,
    scene: scene,
  );
}

/// 연표 자리(1920×1000)에 계보 창 층만 띄운다. [detail]을 주면 왼쪽에 상세 창 뼈대도.
Future<void> mount(WidgetTester tester, AppBus bus, {bool layer = true, Widget? detail, bool keys = false}) async {
  tester.view.physicalSize = const Size(1920 + 380, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget body = Row(
    children: [
      SizedBox(width: 380, child: detail ?? const SizedBox()),
      SizedBox(
        width: 1920,
        child: Stack(children: [if (layer) Positioned.fill(child: GroupTreeLayer(bus: bus))]),
      ),
    ],
  );
  if (keys) body = ShellKeys(bus: bus, windowOpen: () => bus.selection.value != null, child: body);
  await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: Ui.bg, body: body)));
}

GroupTreeLayerState layerOf(WidgetTester tester) => tester.state<GroupTreeLayerState>(find.byType(GroupTreeLayer));

/// 나무 그림(CustomPaint)의 왼쪽 위 — 막대 자리(그림 영역 안 px)를 화면 자리로 옮길 때.
Offset plotOrigin(WidgetTester tester) => tester.getTopLeft(find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null && w.painter.runtimeType.toString() == '_GroupTreePainter'));

GroupTreeGeometry geoOf(WidgetTester tester) {
  final s = layerOf(tester);
  return GroupTreeGeometry.of(s.data!, s.xOf, width: s.plotOf().width);
}

void main() {
  group('자료 · 자리 셈', () {
    final data = GroupTreeData.parse(kap, rec(kap)['x_groupTree'])!;

    test('나라 기록의 x_groupTree — 웹 HT.groupTreeLayout과 같은 줄 · 이음', () {
      expect(data.polityName, '갑 왕국');
      expect(data.rows, 6);
      expect([for (final n in data.nodes) '${n.name}@${n.row}'], ['옛 무리@0', '동쪽 무리@1', '서쪽 무리@2', '남쪽 무리@3', '새 무리@4', '검은 장막@5', '곧은 길 모임@4']);
      expect([for (final e in data.edges) '${data.nodes[e.from].name}→${data.nodes[e.to].name}:${e.kind}${e.same ? '=' : ''}'], [
        '옛 무리→동쪽 무리:split',
        '옛 무리→서쪽 무리:split',
        '옛 무리→남쪽 무리:blank',
        '서쪽 무리→새 무리:merge',
        '남쪽 무리→새 무리:merge',
        '새 무리→곧은 길 모임:rename=',
      ]);
      final e = data.nodes[data.indexOf(east)];
      expect(e.count, '집권 1번 · 연정 1번');
      expect([for (final s in e.segs) s.kind], [GroupSegKind.power, GroupSegKind.coal]);
      expect(e.tip, '동쪽 무리 · 붕당·파벌 · 842년 ~ 905년 · 집권 1번 · 연정 1번 — 누르면 연표에 조명 · 두 번 누르면 단체 창');
      expect(data.edges.first.ev, 'sample-groups/gr-e-split');
      expect(data.edges.first.tip, '갈라짐 — 옛 무리 → 동쪽 무리 · 842 · 누르면 그 사건');
      // 단체 기록은 같은 나무를 다시 싣지 않고 나라를 가리킨다.
      expect(groupTreeHolder(rec(east), east), kap);
      expect(groupTreeHolder(rec(kap), kap), kap);
      expect(groupTreeHolder(rec('sample-groups/gr-pact'), 'sample-groups/gr-pact'), isNull, reason: '연합(있던 나라 · 앞뒤 단체 없음)은 웹도 단추가 없다');
    });

    test('막대 x는 연표와 같은 자리 · 이음선이 막대를 가로지르지 않음 · 매듭 · 적지 않음은 옅은 선', () {
      final k = 1600 / (data.hi - data.lo);
      double x(double m) => (m - data.lo) * k;
      final geo = GroupTreeGeometry.of(data, x, width: 1700);
      // 앞선 단체가 없는 막대(옛 무리 · 검은 장막)의 머리는 연표와 같은 x(들여 쓰지 않음)
      expect(geo.bars[0].x1, x(data.nodes[0].lo));
      expect(geo.bars[5].x1, x(data.nodes[5].lo));
      // 앞선 단체가 있으면 머리를 5px 들임, 이름 바꿈으로 이어 쓰면 4px
      expect(geo.bars[1].x1, x(data.nodes[1].lo) + 5);
      expect(geo.bars[6].x1, x(data.nodes[6].lo) + 4);
      expect(geo.bars[6].row, geo.bars[4].row, reason: '이름 바꿈은 같은 줄에 이어 씀');
      // 세로 줄기는 사이 줄의 막대 안을 지나지 않는다
      for (final l in geo.lines) {
        for (int i = 0; i + 1 < l.points.length; i++) {
          final a = l.points[i], b = l.points[i + 1];
          if (a.dx != b.dx) continue;
          final y0 = a.dy < b.dy ? a.dy : b.dy, y1 = a.dy < b.dy ? b.dy : a.dy;
          for (final bar in geo.bars) {
            final crossing = bar.cy > y0 && bar.cy < y1 && a.dx > bar.x1 + 1 && a.dx < bar.x2 - 1;
            expect(crossing, isFalse, reason: '세로 줄기 x=${a.dx}가 줄 ${bar.row}의 막대를 가로지름');
          }
        }
      }
      expect(geo.knots, hasLength(3), reason: '합쳐짐 네모 하나 + 이름 바꿈 다리 양쪽 둘');
      expect(geo.lines.where((l) => l.style == GroupLineStyle.faint), hasLength(2), reason: '방식을 적지 않은 갈래 하나 — 앞 막대 끝에서 옆으로 + 세로 줄기(웹 path의 두 토막)');
      expect(geo.lines.where((l) => l.style == GroupLineStyle.dotted), isEmpty);
      expect(geo.hows, isEmpty);
      expect(geo.hits.where((h) => h.edge.ev.isNotEmpty), hasLength(3), reason: '사건이 있는 이음(갈라짐 하나 · 합쳐짐 둘)만 누름');
    });

    test('방식 미상 — 2px 점선 + 글(그 자리에 들어갈 때만)', () {
      final unknown = GroupTreeData(
        holder: kap,
        lo: data.lo,
        hi: data.hi,
        rows: data.rows,
        nodes: data.nodes,
        edges: [for (final e in data.edges) e.kind == 'blank' ? GroupTreeEdge(from: e.from, to: e.to, kind: 'unknown', after: e.after) : e],
      );
      final k = 1600 / (data.hi - data.lo);
      final geo = GroupTreeGeometry.of(unknown, (m) => (m - data.lo) * k, width: 1700);
      expect(geo.lines.where((l) => l.style == GroupLineStyle.dotted), hasLength(2));
      expect(geo.lines.where((l) => l.style == GroupLineStyle.faint), isEmpty);
      expect(geo.hows, hasLength(1));
      final tight = GroupTreeGeometry.of(unknown, (m) => (m - data.lo) * k, width: 1700, howWidth: 100000);
      expect(tight.hows, isEmpty, reason: '글이 들어갈 자리가 없으면 글을 두지 않음(돌출 없음)');
    });

    test('막대 이름 — 이름 + 기간 → 이름 → 첫 글자 → 없음', () {
      final g = data.nodes[1];
      double w(String t, TextStyle s) => t.length * 10.0;
      expect(groupBarLabel(g, 0, 200, w), (name: '동쪽 무리', range: '842–905'));
      expect(groupBarLabel(g, 0, 70, w), (name: '동쪽 무리', range: ''));
      expect(groupBarLabel(g, 0, 30, w), (name: '동', range: ''));
      expect(groupBarLabel(g, 0, 20, w), isNull);
    });
  });

  group('창', () {
    testWidgets('단체 창의 단추가 연 것처럼 — 나라 나무를 그 단체를 고른 채로 · 조명 · 크기 · 머리글', (tester) async {
      final bus = makeBus();
      await mount(tester, bus);
      openGroupTree(bus, east, group: east);
      await tester.pumpAndSettle();
      final s = layerOf(tester);
      expect(s.data!.holder, kap, reason: 'x_treeAt으로 나라 나무를 읽음');
      expect(s.data!.nodes[s.selected].uid, east);
      expect(bus.slot('spots').value, s.data!.nodes[s.selected].spots, reason: '그 나라 띠에 집권 덩이마다 조명');
      expect((bus.slot('spots').value as List).length, 2);
      final sheet = tester.getRect(find.byKey(groupTreeKey));
      expect(sheet.height, 525, reason: 'min(525px, 56%) — 1000의 56%는 560');
      expect(sheet.width, 1920);
      expect(sheet.bottom, 1000);
      expect(find.text('단체 계보'), findsWidgets);
      expect(find.text('갑 왕국 · 단체 7 · 연도 눈금은 연표와 같은 자리'), findsOneWidget);
      for (final w in const ['갈라짐', '합쳐짐', '이름 바꿈', '방식 미상', '적지 않음', '집권', '연정', '있던 기간']) {
        expect(find.text(w), findsOneWidget, reason: '선 견본 $w');
      }
      expect(find.text('842년 ~ 905년\n집권 1번 · 연정 1번'), findsOneWidget);
      expect(find.text('◀ 나라 상세'), findsOneWidget);
      // 그림 영역은 연표의 이름 칸 오른쪽 · 연표의 그림 영역 폭
      final v = bus.controller.view;
      expect(plotOrigin(tester).dx - sheet.left, v.left * v.mag);
      expect(s.plotOf().width, v.plotWidth * v.mag);
      // 막대 x = 위 연표의 같은 해 x(그림 영역 기준)
      final geo = geoOf(tester);
      expect(geo.bars[0].x1, closeTo((v.xOf(s.data!.nodes[0].lo) - v.left) * v.mag, 1e-6));
    });

    testWidgets('막대를 누르면 고름 · 두 번 누르면 단체 창 · 이음선은 그 사건 · 닫으면 제 조명만 걷음', (tester) async {
      final bus = makeBus();
      await mount(tester, bus);
      openGroupTree(bus, kap);
      await tester.pumpAndSettle();
      final s = layerOf(tester);
      expect(s.selected, -1);
      expect(find.textContaining('막대를 누르면 위 연표의'), findsOneWidget);
      final origin = plotOrigin(tester);
      var geo = geoOf(tester);
      final i = s.data!.indexOf(newer);
      await tester.tapAt(origin + geo.bars[i].rect.center);
      await tester.pump();
      expect(s.selected, i, reason: '손을 떼면 곧바로 고름(두 번 누름을 기다리지 않음)');
      expect(bus.slot('spots').value, s.data!.nodes[i].spots);
      // 고른 단체는 위 연표의 집권 단에서 그 단체의 칸만 진하게(웹 setGroupFocus) — 장면의 표시 상태에 uid와 색을 적는다
      final marks = SceneMarks.of(bus.scene);
      expect(marks.groupFocus, newer);
      expect(marks.groupFocusColor, s.data!.nodes[i].color.toARGB32() & 0xffffff);
      expect(bus.selection.value, isNull);
      await tester.pump(const Duration(milliseconds: 400));
      // 두 번 누름 → 단체 창
      await tester.tapAt(origin + geo.bars[i].rect.center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(origin + geo.bars[i].rect.center);
      await tester.pumpAndSettle();
      expect(bus.selection.value?.uid, newer);
      expect(bus.selection.value?.kind, 'group');
      // 사건이 있는 이음선(옛 무리 → 동쪽 무리 갈라짐)
      bus.clearSelection();
      geo = geoOf(tester);
      final hit = geo.hits.firstWhere((h) => h.edge.ev == 'sample-groups/gr-e-split');
      final mid = Offset.lerp(hit.points[hit.points.length - 2], hit.points.last, .5)!;
      await tester.tapAt(origin + mid);
      await tester.pump(const Duration(milliseconds: 400));
      expect(bus.selection.value?.uid, 'sample-groups/gr-e-split');
      // 다른 창이 조명을 걷으면 고른 단체의 조명이 되살아남(웹 restoreSpot)
      bus.slot('spots').value = null;
      await tester.pump();
      expect(bus.slot('spots').value, s.data!.nodes[i].spots);
      // 다른 창이 제 조명을 켠 뒤 닫으면 남의 조명은 그대로
      final other = [
        {'uid': 'x', 'start': 0, 'end': 1},
      ];
      bus.slot('spots').value = other;
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(s.isOpen, isFalse);
      expect(bus.slot('spots').value, same(other));
      expect(marks.groupFocus, isNull, reason: '창을 닫으면 고름도 풀린다');
      expect(find.byKey(groupTreeKey), findsNothing);
    });

    // 리메이크 2부(목업 서고) — 확대 묶음은 맨 위 줄로 옮겼으니 비키지 않는다. 연표 위 오른쪽 아래에 떠서 비키는 것은 배율 알약 · 상세 칸.
    testWidgets('앱 틀: 계보 창이 떠 있는 동안 배율 알약과 상세 칸이 창 높이만큼 위로 비켜 창과 겹치지 않는다(확대 묶음은 맨 위 줄 그대로)', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (scene, _, _) = makePackScene();
      addTearDown(scene.dispose);
      final query = TextEditingController();
      addTearDown(query.dispose);
      Widget shell({required bool sheet}) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: AppShell(
            controller: scene.controller,
            timeline: TimelineView(scene: scene),
            searchController: query,
            detail: const Text('고른 항목의 상세'),
            stageBottomInset: sheet ? GroupTreeLayerState.sheetHeight : null,
          ),
        ),
      );
      double below(Type what) => 1080 - tester.getRect(find.byType(what)).bottom;
      await tester.pumpWidget(shell(sheet: false));
      await tester.pump(const Duration(milliseconds: 500));
      final zoom = tester.getRect(find.byType(ZoomButtons));
      expect(zoom.bottom, lessThanOrEqualTo(Ui.top), reason: '확대 묶음은 맨 위 줄 안');
      expect(below(MagPill), closeTo(Ui.zoomBottom, .01));
      expect(below(DetailPanel), closeTo(Ui.detailBottom, .01));
      await tester.pumpWidget(shell(sheet: true));
      await tester.pump(const Duration(milliseconds: 500));
      final h = GroupTreeLayerState.sheetHeight(1080 - Ui.top);
      expect(h, 525, reason: '연표 영역 1020의 56%는 571 — 525까지');
      expect(below(MagPill), closeTo(Ui.zoomBottom + h, .01), reason: '배율 알약은 창 위 16');
      expect(below(DetailPanel), closeTo(Ui.detailBottom + h, .01), reason: '상세 칸은 창 위까지만');
      expect(tester.getRect(find.byType(ZoomButtons)), zoom, reason: '맨 위 줄의 확대 묶음은 계보 창과 겹치지 않아 그대로');
    });

    testWidgets('Esc — 상세 창이 먼저(단축키 부품이 닫음), 그다음 이 창', (tester) async {
      final bus = makeBus();
      // 앱 틀(app_glue)처럼 Esc 명령이면 고른 것을 거둔다 — 계보 창 층보다 먼저 듣는다
      bus.slot(slotCommand).addListener(() {
        final c = bus.slot(slotCommand).value;
        if (c is AppCommand && c.name == Cmd.close) bus.clearSelection();
      });
      await mount(tester, bus, keys: true);
      openGroupTree(bus, kap, group: old);
      await tester.pumpAndSettle();
      bus.select(east, kind: 'group');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(bus.selection.value, isNull, reason: '첫 Esc는 상세 창');
      expect(layerOf(tester).isOpen, isTrue, reason: '같은 누름에 계보 창까지 닫지 않음');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(layerOf(tester).isOpen, isFalse, reason: '둘째 Esc는 계보 창');
      expect(bus.slot('spots').value, isNull, reason: '이 창이 켠 조명을 걷음');
    });

    testWidgets('Esc — 단축키 부품이 같은 누름에 렌즈를 끄면 이 창은 그대로(한 번에 하나)', (tester) async {
      final bus = makeBus();
      // 렌즈 부품의 Esc 갈래(단축키 부품 — 계보 창 층보다 먼저 키를 듣는다)를 흉내: 렌즈가 켜져 있으면 끈다
      bool lensOff(KeyEvent e) {
        if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) return false;
        final lens = bus.slot('themeLens').value;
        if (lens is String && lens.isNotEmpty) {
          bus.slot('themeLens').value = null;
          return true;
        }
        return false;
      }

      HardwareKeyboard.instance.addHandler(lensOff);
      addTearDown(() => HardwareKeyboard.instance.removeHandler(lensOff));
      await mount(tester, bus);
      bus.slot('themeLens').value = 'faction';
      openGroupTree(bus, kap);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(bus.slot('themeLens').value, isNull);
      expect(layerOf(tester).isOpen, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(layerOf(tester).isOpen, isFalse);
    });

    testWidgets('연표가 배치 도중(LayoutBuilder 안)에 크기를 알려도 다음 장면에 같은 x로 다시 그림', (tester) async {
      final bus = makeBus();
      tester.view.physicalSize = const Size(1920, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // 연표(timeline_view.dart)처럼 배치 도중에 조종부 크기를 알린다
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      bus.controller.resize(box.maxWidth, box.maxHeight);
                      return const SizedBox();
                    },
                  ),
                ),
                Positioned.fill(child: GroupTreeLayer(bus: bus)),
              ],
            ),
          ),
        ),
      );
      openGroupTree(bus, kap);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1600, 900);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump();
      final s = layerOf(tester);
      final v = bus.controller.view;
      expect(s.plotOf().width, v.plotWidth * v.mag, reason: '크기가 바뀐 뒤의 그림 영역 폭');
      expect(tester.getRect(find.byKey(groupTreeKey)).height, closeTo(900 * .56, 1e-9), reason: '900의 56% = 504 < 525');
    });

    testWidgets('나무가 보기 범위 밖이면 나무 전체가 들어오게 간다', (tester) async {
      final bus = makeBus();
      bus.controller.showRange(minuteOfYear(1500), minuteOfYear(1600));
      await mount(tester, bus);
      openGroupTree(bus, kap);
      await tester.pumpAndSettle();
      final go = bus.go.value!;
      final d = layerOf(tester).data!;
      expect(go.lo, lessThan(d.lo));
      expect(go.hi, greaterThan(d.hi));
    });

    // 2026-10-14 고침: 전에는 나무 전체가 보기 밖일 때만 옮겨, 고른 단체의 막대와 위 연표의 조명이 화면 밖에 남았다(왼쪽 칸은 '연표에 조명 중').
    testWidgets('나무는 보이지만 고른 단체가 보기 밖이면 그 단체의 기간으로 간다 — 이 시기로와 같은 틀(앞뒤 15% · 적어도 2년)', (tester) async {
      final bus = makeBus();
      bus.controller.showRange(minuteOfYear(900), minuteOfYear(1000)); // 새 무리 · 곧은 길 모임 …은 보이고 옛 무리(760~842)는 밖
      await mount(tester, bus);
      openGroupTree(bus, old, group: old);
      await tester.pumpAndSettle();
      final s = layerOf(tester);
      final g = s.data!.nodes[s.selected];
      expect(g.uid, old);
      final go = bus.go.value!;
      final pad = (g.hi - g.lo) * .15;
      expect(go.lo, closeTo(g.lo - pad, 1e-6));
      expect(go.hi, closeTo(g.hi + pad, 1e-6));
      expect(bus.slot('spots').value, g.spots, reason: '고른 단체의 조명');
    });

    testWidgets('고른 단체가 조금이라도 보이면 보기를 옮기지 않는다', (tester) async {
      final bus = makeBus();
      bus.controller.showRange(minuteOfYear(830), minuteOfYear(1000)); // 옛 무리의 830~842가 보임
      await mount(tester, bus);
      openGroupTree(bus, old, group: old);
      await tester.pumpAndSettle();
      expect(layerOf(tester).data!.nodes[layerOf(tester).selected].uid, old);
      expect(bus.go.value, isNull);
    });

    testWidgets('단추 — 계보 창 층이 붙어 있을 때만 단체 창 · 나라 상세에 선다', (tester) async {
      registerGroupDetail();
      final bus = makeBus();
      await mount(tester, bus, layer: false, detail: DetailHost(bus: bus, framed: false));
      bus.select(east, kind: 'group');
      await tester.pumpAndSettle();
      expect(find.text('단체 계보'), findsNothing, reason: '층이 없으면 누를 곳 없는 단추를 두지 않음');

      final bus2 = makeBus();
      await mount(tester, bus2, detail: DetailHost(bus: bus2, framed: false));
      bus2.select(east, kind: 'group');
      await tester.pumpAndSettle();
      final button = find.widgetWithText(DetailSmallButton, '단체 계보');
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(bus2.slot(groupTreeSlot).value, const GroupTreeRequest(kap, group: east), reason: '단체 기록의 x_treeAt — 그 나라의 나무를 그 단체를 고른 채로');
      expect(layerOf(tester).data!.nodes[layerOf(tester).selected].uid, east);
      for (final k in detailKinds) {
        DetailHost.unregister(k.id);
      }
    });
  });

  group('법의 내력 · 결과(의석 막대)', () {
    Future<void> show(WidgetTester tester, List<Widget> children) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Ui.bg,
          body: SizedBox(width: Ui.detailWidth, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))),
        ),
      ),
    );
    final opened = <(String, String)>[];
    void open(String uid, {String kind = '', String? cell}) => opened.add((uid, kind));
    List<String> boxes(WidgetTester tester) => [for (final b in tester.widgetList<DetailBox>(find.byType(DetailBox))) '${b.title}${b.small == null ? '' : ' (${b.small})'}'];

    testWidgets('법의 내력 — 같은 이름의 법을 날짜 차례로 · 사이 간격 · 이 사건 · 폐지 기록 없음', (tester) async {
      final x = rec('sample-lens/ln-e-amend');
      final h = DetailLawHistory(x, open: open);
      expect(h.rowTexts, ['제정760년 새 법전 반포', '개정830년 이 사건70년 뒤', '폐지기록 없음 — 나라가 끝날 때까지 쓴 것으로 봄']);
      await show(tester, [h]);
      expect(boxes(tester), ['법의 내력 (2)']);
      await tester.tap(find.textContaining('760년', findRichText: true));
      expect(opened.last, ('sample-lens/ln-e-enact', ''));
      final one = DetailLawHistory(rec('sample-lens/ln-e-repeal'), open: open);
      expect(one.rowTexts, ['폐지905년 이 사건']);
      await show(tester, [one]);
      expect(boxes(tester), ['법의 내력']);
    });

    testWidgets('아래 묶음 — 제자리 셋을 아직 부르지 않으면 법 이름 · 내력 · 결과도 맨 앞, 부르면 조항 · 관련만', (tester) async {
      final law = rec('sample-lens/ln-e-amend');
      await show(tester, detailLensBottom(law, open));
      expect(find.text('법 이름 새 법전'), findsOneWidget);
      expect(boxes(tester), ['법의 내력 (2)', '조항 (1)', '관련']);
      expect(find.text('개정'), findsWidgets, reason: '개정 사건의 조항 줄마다 개정 딱지');
      await show(tester, detailLensBottom(law, open, topsPlaced: true));
      expect(boxes(tester), ['조항 (1)', '관련']);
      expect(find.text('법 이름 새 법전'), findsNothing);
      // 관련 — 그때의 법률(제도 창) · 앞 고침(사건 창)
      await tester.tap(find.text('새 법전 반포'));
      expect(opened.last, ('sample-lens/ln-e-enact', ''));
      await tester.tap(find.text('새 법전').last);
      expect(opened.last, ('sample-lens/ln-i-law', 'institution'));

      final vote = rec('sample-lens/ln-e-vote1');
      await show(tester, detailLensBottom(vote, open));
      expect(boxes(tester), ['결과 (의석 80)', '관련']);
      expect(find.text('뽑은 자리 의회'), findsOneWidget);
      await show(tester, [...detailLensAka(vote), ...detailElectionTop(vote, open), ...detailLensBottom(vote, open, topsPlaced: true)]);
      expect(boxes(tester), ['결과 (의석 80)', '관련']);
    });

    testWidgets('의석 막대 — 의석만큼 나눔 · 과반 글 · 결과 표 · 득표만 적은 선거', (tester) async {
      final vote = rec('sample-lens/ln-e-vote1');
      await show(tester, detailElectionTop(vote, open));
      expect(find.text('과반 41석 — 푸른 모임 41석'), findsOneWidget);
      final bar = tester.getSize(find.byType(DetailSeatBar));
      expect(bar.height, DetailSeatBar.height);
      final widths = DetailSeatBar.widthsOf(const [41, 33, 6], bar.width);
      expect(widths[0] / widths[1], closeTo(41 / 33, 1e-9));
      expect(widths.reduce((a, b) => a + b) + 2 * DetailSeatBar.gap, closeTo(bar.width, 1e-9));
      expect(find.text('41석'), findsOneWidget);
      expect(find.text('당선'), findsOneWidget);
      expect(find.text('12,034'), findsOneWidget);

      final v2 = rec('sample-lens/ln-e-vote2');
      await show(tester, detailElectionTop(v2, open));
      expect(boxes(tester), ['결과 (득표 30,190)']);
      expect(find.text('가장 많은 표 — 붉은 모임의 사람 50.4%'), findsOneWidget);
      expect(find.text('의석'), findsNothing, reason: '의석을 적지 않은 선거는 의석 열이 없음');
      // 가장 좁아도 3px
      expect(DetailSeatBar.widthsOf(const [1000, 1], 100), [95.0, 3.0]);
    });

    testWidgets('모임이 단체면 막대 조각 · 이름을 누르면 단체 창', (tester) async {
      const vote = {
        'by': 'seats',
        'total': 10,
        'linked': 1,
        'rows': [
          {'who': '동쪽 무리', 'color': '#dab195', 'uid': east, 'seats': 6, 'won': 1, 'part': '동쪽 무리 6석'},
          {'who': '그 밖', 'color': '#9dbea8', 'seats': 4, 'part': '그 밖 4석'},
        ],
        'cap': '과반 6석 — 동쪽 무리 6석',
      };
      opened.clear();
      await show(tester, [const DetailVoteBox(vote, open: _noOpen)]);
      expect(boxes(tester), ['결과 (의석 10 · 누르면 그 모임)']);
      await show(tester, [DetailVoteBox(vote, open: open)]);
      await tester.tap(find.bySemanticsLabel('동쪽 무리 6석 — 단체 창'));
      expect(opened.last, (east, 'group'));
      await tester.tap(find.text('동쪽 무리'));
      expect(opened.last, (east, 'group'));
    });

    test('딱지 — 법 · 선거는 마름모(주제 색) · 뽑은 자리', () {
      final badges = detailLensBadges(rec('sample-lens/ln-e-vote1')).whereType<DetailBadge>().toList();
      final v = badges.firstWhere((b) => b.diamond && b.text.startsWith('선거'));
      expect(v.text, '선거 · 의회');
      expect(v.diamond, isTrue);
      expect(v.color, detailVoteColor);
      final l = detailLensBadges(rec('sample-lens/ln-e-amend')).whereType<DetailBadge>().firstWhere((b) => b.diamond);
      expect(l.text, '법 · 개정');
      expect(l.color, detailLawColor);
    });
  });
}

void _noOpen(String uid, {String kind = '', String? cell}) {}

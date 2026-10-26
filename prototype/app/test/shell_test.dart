import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/app_menu.dart';
import 'package:archive_prototype/shell/app_shell.dart';
import 'package:archive_prototype/shell/dock.dart';
import 'package:archive_prototype/shell/detail_panel.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/mag_pill.dart';
import 'package:archive_prototype/shell/search_results.dart';
import 'package:archive_prototype/shell/sheet_look.dart';
import 'package:archive_prototype/shell/zoom_buttons.dart';
import 'package:archive_prototype/timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';

// 앱 틀 검사: 자료 처리부 없이 가짜 장면 하나로 돌린다.
// 확인하는 것 — 처음에는 상세 창이 없고 연표가 창 폭 전체 · 고르면 상세 창이 열리고 오른쪽 아래 배율 알약이 비킴
// (확대 묶음은 리메이크 2부부터 맨 위 줄 안이라 비키지 않는다) · 알약 창의 기간 글이 보기와 함께(글이 바뀔 때만) 바뀜 ·
// 확대 단추가 조종부를 부름 · `⋯` 메뉴의 줄.

/// 검사가 세우는 틀. [detail]이 있으면 상세 창이 열린 꼴이다.
class _Host extends StatefulWidget {
  const _Host({required this.scene, this.startDetail = false, this.results, this.menuItems = const <AppMenuItem>[]});
  final TimelineScene scene;
  final bool startDetail;
  final Widget? results;
  final List<AppMenuItem> menuItems;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final query = TextEditingController();
  late bool open = widget.startDetail;
  late Widget? results = widget.results;
  bool reduce = false;

  /// 검사가 '사건을 골랐다'고 알리는 길.
  void openDetail() => setState(() => open = true);
  void reduceMotion() => setState(() => reduce = true);

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduce), child: child!),
    home: Scaffold(
      body: AppShell(
        controller: widget.scene.controller,
        timeline: TimelineView(scene: widget.scene),
        searchController: query,
        searchResults: results,
        onCloseResults: () => setState(() => results = null),
        detail: open ? const Text('고른 사건의 상세') : null,
        onCloseDetail: () => setState(() => open = false),
        menuItems: widget.menuItems,
      ),
    ),
  );
}

Future<(TimelineScene, _HostState)> pumpShell(
  WidgetTester tester, {
  bool detail = false,
  Widget? results,
  List<AppMenuItem> menuItems = const <AppMenuItem>[],
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final (scene, _, _) = makePackScene();
  addTearDown(scene.dispose);
  await tester.pumpWidget(_Host(scene: scene, startDetail: detail, results: results, menuItems: menuItems));
  await tester.pumpAndSettle(const Duration(milliseconds: 20));
  return (scene, tester.state<_HostState>(find.byType(_Host)));
}

/// 오른쪽 아래 배율 알약의 화면 자리(오른쪽 끝이 창 오른쪽에서 얼마나 떨어져 있는가). 100%일 때는 투명하지만 자리는 차지한다.
/// 리메이크 2부(목업 서고) — 확대 묶음은 맨 위 줄로 옮겼고, 상세 창을 따라 비키는 것은 이 알약만 남았다.
double magRightOf(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(find.byType(MagPill));
  return 1920 - (box.localToGlobal(Offset.zero).dx + box.size.width);
}

/// 확대 묶음(− + ⤢ 조감)의 화면 자리 — 맨 위 줄(알약 창) 안의 가로 묶음.
Rect zoomRectOf(WidgetTester tester) => tester.getRect(find.byType(ZoomButtons));

void main() {
  testWidgets('상세 칸을 닫는 순간 안쪽 단추의 키보드 실행도 차단한다', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var open = true;
    var activations = 0;
    late StateSetter change;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return SizedBox(
                width: Ui.detailWidth,
                height: 400,
                child: DetailPanel(
                  open: open,
                  bare: true,
                  child: TextButton(
                    focusNode: focus,
                    onPressed: () => activations++,
                    child: const Text('별여울로 가기'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activations, 1);

    change(() => open = false);
    await tester.pump();
    expect(find.text('별여울로 가기'), findsOneWidget, reason: '내용을 보관하는 bare 경로도 닫히면 입력을 받지 않는다');
    expect(focus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(focus.hasFocus, isFalse);
    expect(activations, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('움직이는 도중 줄이기를 켜면 상세 칸과 배율 알약이 같은 목표에 바로 도착한다', (tester) async {
    final (_, host) = await pumpShell(tester);
    final zoom = zoomRectOf(tester);
    host.openDetail();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(magRightOf(tester), greaterThan(Ui.zoomRight));
    expect(magRightOf(tester), lessThan(Ui.zoomRightOpen));
    expect(zoomRectOf(tester), zoom, reason: '맨 위 줄의 확대 묶음은 상세 창을 따라 움직이지 않는다');
    host.reduceMotion();
    await tester.pump();
    expect(magRightOf(tester), closeTo(Ui.zoomRightOpen, .01));
    final panel = tester.renderObject<RenderBox>(find.byType(DetailPanel));
    expect(1920 - (panel.localToGlobal(Offset.zero).dx + panel.size.width), closeTo(Ui.detailInset, .01));
  });

  testWidgets('처음에는 상세 창이 없고 연표가 창 폭 전체를 쓴다', (tester) async {
    await pumpShell(tester);
    expect(find.byType(DetailPanel), findsNothing);
    final timeline = tester.renderObject<RenderBox>(find.byType(TimelineView));
    expect(timeline.size.width, 1920, reason: '연표는 창 폭 전체');
    expect(timeline.localToGlobal(Offset.zero).dy, Ui.top, reason: '맨 위 60px 바탕 띠 바로 아래가 연표(맨 위 1px 선은 날짜 칸이 제 높이 안에 그린다)');
    expect(magRightOf(tester), closeTo(Ui.zoomRight, .01));
    expect(1080 - tester.getRect(find.byType(MagPill)).bottom, closeTo(Ui.zoomBottom, .01), reason: '배율 알약은 오른쪽 아래 16');
    // 알약 창(맨 위 줄)은 왼쪽 위 (dockLeft, dockTop)에 맨 위 줄 높이로 붙어 있다.
    final dock = tester.renderObject<RenderBox>(find.byType(DockBar));
    expect(dock.localToGlobal(Offset.zero), const Offset(Ui.dockLeft, Ui.dockTop));
    expect(dock.size.height, Ui.dockHeight);
    // 확대 묶음은 맨 위 줄 안(리메이크 2부 — 목업 서고 frame): 검색 칸 뒤 · 필터 단추 앞에 가로로 선다.
    expect(find.descendant(of: find.byType(DockBar), matching: find.byType(ZoomButtons)), findsOneWidget);
    expect(tester.widget<ZoomButtons>(find.byType(ZoomButtons)).horizontal, isTrue);
    final zoom = zoomRectOf(tester), dockRect = tester.getRect(find.byType(DockBar));
    expect(zoom.top, greaterThanOrEqualTo(dockRect.top));
    expect(zoom.bottom, lessThanOrEqualTo(dockRect.bottom));
    expect(zoom.right, lessThan(tester.getRect(find.byTooltip('필터 (F)')).left), reason: '확대 묶음은 기호 단추들 앞');
    expect(zoom.left, greaterThan(tester.getRect(find.byType(TextField)).right), reason: '검색 칸 뒤');
    expect(find.byTooltip('필터 (F)'), findsOneWidget);
    expect(find.byTooltip('더 보기'), findsOneWidget);
  });

  testWidgets('고르면 상세 창이 열리며 배율 알약이 396으로 비키고(확대 묶음은 맨 위 줄 그대로), 닫으면 되돌아간다', (tester) async {
    final (_, host) = await pumpShell(tester);
    final zoom = zoomRectOf(tester);
    host.openDetail();
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(find.byType(DetailPanel), findsOneWidget);
    expect(find.text('고른 사건의 상세'), findsOneWidget);
    final panel = tester.renderObject<RenderBox>(find.byType(DetailPanel));
    expect(panel.size.width, Ui.detailWidth);
    expect(1920 - (panel.localToGlobal(Offset.zero).dx + panel.size.width), closeTo(Ui.detailInset, .01));
    expect(magRightOf(tester), closeTo(Ui.zoomRightOpen, .01), reason: '열려 있는 동안 배율 알약이 비킨다');
    expect(zoomRectOf(tester), zoom, reason: '확대 묶음은 맨 위 줄이라 상세 창과 겹치지 않아 비키지 않는다');

    // 닫기 단추(✕)로 닫으면 연표가 다시 창 폭 전체를 쓴다.
    await tester.tap(find.text('✕'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DetailPanel), findsNothing);
    expect(magRightOf(tester), closeTo(Ui.zoomRight, .01));
  });

  testWidgets('Esc로도 상세 창이 닫힌다', (tester) async {
    final (_, host) = await pumpShell(tester, detail: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DetailPanel), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(host.open, isFalse);
    expect(find.byType(DetailPanel), findsNothing);
  });

  testWidgets('알약 창의 기간 글은 보기와 함께 바뀌고, 글이 그대로면 다시 짓지 않는다', (tester) async {
    final (scene, _) = await pumpShell(tester);
    final c = scene.controller;
    c.showRange(DateTime.utc(240).millisecondsSinceEpoch / 60000, DateTime.utc(340).millisecondsSinceEpoch / 60000);
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '240년 ~ 340년'), findsOneWidget);

    // 같은 글이 나오는 잔 움직임에서는 글을 다시 짓지 않는다(움직이는 장면마다 부품을 새로 만들지 않게).
    final before = DockRange.builds;
    for (int i = 0; i < 30; i++) {
      c.scrollTo(i.toDouble());
      await tester.pump();
    }
    expect(DockRange.builds, before, reason: '글이 그대로면 다시 짓지 않는다');

    c.showRange(DateTime.utc(900).millisecondsSinceEpoch / 60000, DateTime.utc(1000).millisecondsSinceEpoch / 60000);
    await tester.pump();
    expect(DockRange.builds, greaterThan(before));
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '900년 ~ 1000년'), findsOneWidget);
  });

  testWidgets('＋ － ⤢가 조종부를 부른다', (tester) async {
    final (scene, _) = await pumpShell(tester);
    final c = scene.controller;
    final span = c.view.span;

    await tester.tap(find.byTooltip('확대 (+)'));
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(c.view.span, lessThan(span), reason: '＋는 wheel로 기간을 좁힌다');
    final narrow = c.view.span;

    await tester.tap(find.byTooltip('축소 (-)'));
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(c.view.span, greaterThan(narrow), reason: '－는 wheel로 기간을 넓힌다');

    c.showRange(0, 1000000);
    await tester.pump();
    await tester.tap(find.byTooltip('전체 보기 (0)'));
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(c.view.span, closeTo(c.maxSpan, 1), reason: '⤢는 showAll');

    // 조감 단추는 부르는 쪽이 onBird를 줄 때만 일한다(여기서는 주지 않았다 — 눌러도 보기가 그대로).
    final all = c.view.span;
    await tester.tap(find.byTooltip('조감 (V)'));
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(c.view.span, all);
  });

  testWidgets('0 키는 전체 보기, / 키는 검색 칸으로 간다', (tester) async {
    final (scene, _) = await pumpShell(tester);
    final c = scene.controller;
    c.showRange(0, 1000000);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(c.view.span, closeTo(c.maxSpan, 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus, isTrue);
  });

  testWidgets('⋯ 메뉴에 측정 · 자료집 · 전체 보기가 있다', (tester) async {
    final chosen = <String>[];
    await pumpShell(
      tester,
      menuItems: [
        AppMenuItem('측정', onSelected: () => chosen.add('측정')),
        AppMenuItem('자료집', onSelected: () => chosen.add('자료집')),
        AppMenuItem('전체 보기', onSelected: () => chosen.add('전체 보기')),
      ],
    );
    await tester.tap(find.byTooltip('더 보기'));
    await tester.pumpAndSettle();
    for (final label in ['측정', '자료집', '전체 보기']) {
      expect(find.text(label), findsOneWidget, reason: '메뉴에 $label');
    }
    await tester.tap(find.text('전체 보기'));
    await tester.pumpAndSettle();
    expect(chosen, ['전체 보기']);
  });

  testWidgets('검색 결과는 알약 창 아래로 내려오고 Esc로 접힌다', (tester) async {
    final picked = <String>[];
    final results = SearchResultsPanel(
      title: '찾음 · 기록',
      count: '2',
      boxes: [
        ResultBox(label: '사건 · 조약', items: [
          ResultRow(title: '별여울의 첫 기록', when: '240년 3월 1일', onTap: () => picked.add('첫')),
          ResultRow(title: '해솔의 두 번째 기록', when: '250년 5월 2일', onTap: () => picked.add('둘')),
        ]),
      ],
    );
    final (_, host) = await pumpShell(tester, results: results);
    expect(find.text('별여울의 첫 기록'), findsOneWidget);
    final list = tester.renderObject<RenderBox>(find.byType(SearchResultsPanel));
    final search = tester.renderObject<RenderBox>(find.byType(TextField));
    final at = list.localToGlobal(Offset.zero), searchAt = search.localToGlobal(Offset.zero);
    expect(list.size.width, SheetLook.searchWidth, reason: '서고 폴더 폭 480(감독 고름 G5 #9)');
    expect(at.dx, closeTo(searchAt.dx + Ui.resultsOffset.dx, .01), reason: '검색 칸 기준 왼쪽 −60');
    expect(at.dy, closeTo(searchAt.dy + search.size.height + Ui.resultsOffset.dy, .01), reason: '검색 칸 아래 +10');

    await tester.tap(find.text('해솔의 두 번째 기록'));
    await tester.pump();
    expect(picked, ['둘']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(host.results, isNull);
    expect(find.text('둘').hitTestable(), findsNothing, reason: '퇴장 중인 결과도 다시 누를 수 없다');
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(find.text('둘'), findsNothing, reason: '퇴장이 끝나면 결과 내용이 사라진다');
  });

  testWidgets('☰ 필터는 빈 시트를 여닫는다(바깥을 누르면 접힘)', (tester) async {
    await pumpShell(tester);
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    expect(shell.filterOpen, isFalse);
    await tester.tap(find.byTooltip('필터 (F)'));
    await tester.pumpAndSettle();
    expect(shell.filterOpen, isTrue);
    // 시트 바깥(오른쪽 아래 빈 곳)을 누르면 접힌다.
    await tester.tapAt(const Offset(1500, 900));
    await tester.pumpAndSettle();
    expect(shell.filterOpen, isFalse);
  });
}

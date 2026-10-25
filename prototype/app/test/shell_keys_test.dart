import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/context_menu.dart';
import 'package:archive_prototype/ui/doc_window.dart' show docFrontKey;
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 단축키 · 메뉴 · 집중 모드 검사 — 명세 06의 8-1 · 8-2 · 8-3.
// 자료 처리부 없이 돈다: 항목 기록은 test/fixtures/entities-menu.json(월흔해 견본에서 뽑은 일곱 개)으로 가짜 ask를 만든다.

const _uidPolity = 'moonwake-chronicle/p-coast-6'; // 시대 '은륜 제국' — 품은 대범위 둘
const _uidEvent = 'moonwake-chronicle/p-coast-0-chronicle-0-0'; // 사건 — 이름이 20자보다 길다
const _uidScope = 'moonwake-chronicle/scope-warlords'; // 대범위 '빈 왕좌의 할거'

double _year(int year) => DateTime.utc(year).millisecondsSinceEpoch / 60000;

/// 검사용 AppBus — 항목 기록은 견본에서 꺼내 주고, 보기는 [span]년 폭으로 잡는다.
({AppBus bus, List<AppCommand> commands}) makeBus({int from = 200, int to = 300}) {
  final store = <String, Map<String, dynamic>>{};
  for (final one in jsonDecode(File('test/fixtures/entities-menu.json').readAsStringSync()) as List) {
    final row = (one as Map).cast<String, dynamic>();
    store[row['uid'] as String] = row;
  }
  final controller = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(_year(-3000), _year(3000))
    ..showRange(_year(from), _year(to));
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [
        {'id': 1, 'name': '견본 기록집', 'events': 3},
      ],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('단축키 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(
    ask: (query) async {
      if (query['op'] == 'entity') return store[query['uid']] ?? const {};
      return const {};
    },
    controller: controller,
    scene: scene,
  );
  final commands = <AppCommand>[];
  bus.slot(slotCommand).addListener(() {
    final one = bus.slot(slotCommand).value;
    if (one is AppCommand) commands.add(one);
  });
  return (bus: bus, commands: commands);
}

final _dockKey = GlobalKey(debugLabel: '알약 창'), _menuButtonKey = GlobalKey(debugLabel: '⋯ 단추');

/// 연표 자리 — `0 + − ← → Esc`를 제가 처리하고 삼킨다(지금 연표와 같다).
class _FakeTimeline extends StatelessWidget {
  const _FakeTimeline({required this.taken});
  final List<String> taken;

  static final _mine = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.equal,
    LogicalKeyboardKey.minus,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.escape,
  ];

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent && _mine.contains(event.logicalKey)) {
        taken.add(event.logicalKey.keyLabel);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: const SizedBox.expand(),
  );
}

class _Host extends StatefulWidget {
  const _Host({required this.bus, this.spot = const MenuSpot(), this.flags = const MenuFlags(), this.hasMap = false, this.blocked});
  final AppBus bus;
  final MenuSpot spot;
  final MenuFlags flags;
  final bool hasMap;

  /// 위에 뜬 부품의 자리 — 여기서는 메뉴를 열지 않는다.
  final Rect? blocked;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final search = TextEditingController();
  final searchFocus = FocusNode(debugLabel: '검색');

  /// 연표가 이미 처리한 키.
  final taken = <String>[];

  @override
  void dispose() {
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Ui.bg,
      body: ShellKeys(
        bus: widget.bus,
        hasMap: widget.hasMap,
        child: Stack(
          children: [
            Positioned.fill(
              child: ContextMenuArea(
                bus: widget.bus,
                probe: (local) async => widget.spot,
                flagsOf: () => widget.flags,
                blocked: (at) => widget.blocked?.contains(at) ?? false,
                child: _FakeTimeline(taken: taken),
              ),
            ),
            Positioned(
              left: 12,
              top: 10,
              child: ZenHide(
                bus: widget.bus,
                child: Container(
                  key: _dockKey,
                  width: 260,
                  height: 40,
                  color: Ui.surface,
                  child: Center(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: search,
                        focusNode: searchFocus,
                        decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(left: 8, top: 8, child: ZenExitButton(bus: widget.bus)),
            Positioned(
              right: 12,
              top: 10,
              child: Builder(
                builder: (context) => GestureDetector(
                  onTap: () => showDockMenu(context, bus: widget.bus, flags: widget.flags),
                  child: SizedBox(key: _menuButtonKey, width: 44, height: 32, child: const Center(child: Text('⋯'))),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<_HostState> _pumpKeys(WidgetTester tester, AppBus bus, {MenuSpot spot = const MenuSpot(), MenuFlags flags = const MenuFlags(), bool hasMap = false, Rect? blocked}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_Host(bus: bus, spot: spot, flags: flags, hasMap: hasMap, blocked: blocked));
  await tester.pump();
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  group('단축키', () {
    testWidgets('글자 키가 저마다의 명령이 된다', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus);
      for (final key in [
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.keyY,
        LogicalKeyboardKey.keyL,
        LogicalKeyboardKey.keyT,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyP,
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.slash,
      ]) {
        await tester.sendKeyEvent(key);
      }
      expect(commands.map((c) => c.name).toList(), [
        Cmd.filter, Cmd.year, Cmd.legend, Cmd.table, Cmd.foldAll, Cmd.measure, Cmd.bird, Cmd.image, Cmd.dlc, Cmd.search,
      ]);
    });

    testWidgets('같은 키를 두 번 누르면 명령도 두 번 실린다', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      expect(commands.length, 2, reason: '같은 이름이라도 새 명령이라 듣는 쪽이 두 번 다 받는다(여닫이)');
      expect(commands[1].seq, greaterThan(commands[0].seq));
    });

    testWidgets('연표가 이미 처리한 키(0 + − ← →)는 두 번 실행되지 않는다', (tester) async {
      final (:bus, :commands) = makeBus();
      final host = await _pumpKeys(tester, bus);
      for (final key in [LogicalKeyboardKey.digit0, LogicalKeyboardKey.equal, LogicalKeyboardKey.minus, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight]) {
        await tester.sendKeyEvent(key);
      }
      expect(host.taken.length, 5, reason: '연표가 다섯 키를 모두 제가 처리했다');
      expect(commands, isEmpty, reason: '연표가 삼킨 키는 단축키까지 올라오지 않는다');
    });

    testWidgets('입력 칸에 초점이 있으면 글자 키는 건너뛴다', (tester) async {
      final (:bus, :commands) = makeBus();
      final host = await _pumpKeys(tester, bus);
      host.searchFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      expect(commands, isEmpty, reason: '글을 치는 동안 F · T · /는 단축키가 아니다');
    });

    testWidgets('Alt · Ctrl과 함께 누른 글자는 받지 않는다', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(commands, isEmpty);
    });

    testWidgets('W는 고른 항목의 문서다 — 고른 것이 없으면 uid 없는 명령(문서 창이 대문으로 받는다)', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      expect(commands.single.name, Cmd.wiki);
      expect(commands.single.uid, isNull);
      commands.clear();
      bus.select(_uidPolity, kind: 'period');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      expect(commands.single.name, Cmd.wiki);
      expect(commands.single.uid, _uidPolity);
    });

    testWidgets('M은 지도 부품이 있을 때만 듣는다', (tester) async {
      final first = makeBus();
      await _pumpKeys(tester, first.bus);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      expect(first.commands, isEmpty);
      final second = makeBus();
      await _pumpKeys(tester, second.bus, hasMap: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      expect(second.commands.single.name, Cmd.map);
    });
  });

  group('Esc의 차례', () {
    testWidgets('메뉴가 먼저 닫히고, 그다음이 검색 칸 · 창 · 집중 모드다', (tester) async {
      final (:bus, :commands) = makeBus();
      final host = await _pumpKeys(tester, bus);

      // ① 메뉴: 열려 있으면 메뉴만 닫힌다.
      await tester.tap(find.text('⋯'));
      await tester.pumpAndSettle();
      expect(find.text('같은 해'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('같은 해'), findsNothing);
      expect(commands, isEmpty, reason: '메뉴를 닫는 Esc는 창까지 닫지 않는다');

      // ② 검색 칸: 비우고 초점을 놓는다.
      host.searchFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(commands.single.name, Cmd.searchClose);
      expect(host.searchFocus.hasFocus, isFalse);
      commands.clear();

      // ③ 창: 고른 것이 있으면 창을 닫으라는 명령.
      bus.select(_uidPolity, kind: 'period');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(commands.single.name, Cmd.close);
      commands.clear();

      // ④ 집중 모드: 창이 없을 때에만 나간다.
      bus.clearSelection();
      setZen(bus, true);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(zenOf(bus), isFalse);
      expect(commands, isEmpty);
    });
  });

  group('집중 모드', () {
    testWidgets('Z가 켜고 끄며 알약 창이 70px 물러나고, 들어갈 때 안내 한 줄이 실린다', (tester) async {
      final (:bus, commands: _) = makeBus();
      await _pumpKeys(tester, bus);
      expect(tester.getTopLeft(find.byKey(_dockKey)).dy, 10);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(zenOf(bus), isTrue);
      expect(bus.slot(slotNotice).value, zenNotice);
      expect(tester.getTopLeft(find.byKey(_dockKey)).dy, closeTo(10 - 70, .01), reason: '독은 위로 70px 물러난다');
      final dockOpacity = find.ancestor(of: find.byKey(_dockKey), matching: find.byType(Opacity)).first;
      expect(tester.renderObject<RenderOpacity>(dockOpacity).opacity, 0, reason: '집중 모드에서는 독이 완전히 투명하다');
      expect(find.bySemanticsLabel('집중 모드 나가기'), findsOneWidget, reason: '왼쪽 위 삼선 단추만 남는다');

      // ☰를 누르면 돌아온다.
      await tester.tap(find.bySemanticsLabel('집중 모드 나가기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(zenOf(bus), isFalse);
      expect(tester.getTopLeft(find.byKey(_dockKey)).dy, closeTo(10, .01));
      expect(tester.renderObject<RenderOpacity>(dockOpacity).opacity, 1, reason: '집중 모드를 나가면 독이 다시 완전히 보인다');
      expect(find.bySemanticsLabel('집중 모드 나가기'), findsNothing);
    });
  });

  group('메뉴 줄', () {
    test('빈 곳에서 연 메뉴는 명세 8-2의 스물세 줄 + 문서 대문(2026-10-16)이다', () {
      final (:bus, commands: _) = makeBus();
      final rows = buildMenuRows(bus: bus);
      expect(rows.length, 24);
      expect(rows[0].label, '같은 해');
      expect(rows[0].keyText, 'Y');
      expect(rows[1].sep, isTrue);
      expect([for (final r in rows.skip(2).take(4)) r.label], ['기간 재기', '전체 보기', '조감', '모두 접기']);
      expect([for (final r in rows.skip(7).take(5)) r.label], ['필터', '문서 대문', '범례', '표', '이미지 · 인쇄']);
      expect(rows[8].keyText, '', reason: 'W는 고른 항목의 문서가 먼저라 대문 줄에는 단축키 글이 없다');
      expect(rows[13].header, isTrue);
      expect(rows[13].label, '승계선');
      expect(rows[14].checked, isTrue, reason: '승계선의 처음 값은 모두 보기');
      expect(rows[18].label, 'DLC 관리');
      expect(rows[20].label, '집중 모드');
      expect(rows[20].keyText, 'Z');
      expect(rows[23].label, '움직임 계측');
      expect(rows.where((r) => r.sep).length, 6);
    });

    test('문서 대문 줄은 대문 열쇠로 문서 명령을 낸다', () {
      final (:bus, :commands) = makeBus();
      buildMenuRows(bus: bus).firstWhere((r) => r.label == '문서 대문').onSelected!();
      expect(commands.single.name, Cmd.wiki);
      expect(commands.single.uid, docFrontKey);
    });

    test('켜져 있는 것에 ✓가 붙고, 모두 접혀 있으면 글이 펴기로 바뀐다', () {
      final (:bus, commands: _) = makeBus();
      final rows = buildMenuRows(
        bus: bus,
        flags: const MenuFlags(measuring: true, bird: true, filterOpen: true, legend: true, allFolded: true, zen: true, motion: true, succession: Succession.direct),
      );
      String labelOf(String key) => rows.firstWhere((r) => r.keyText == key).label;
      expect(rows.firstWhere((r) => r.keyText == 'R').checked, isTrue);
      expect(rows.firstWhere((r) => r.keyText == 'V').checked, isTrue);
      expect(rows.firstWhere((r) => r.keyText == 'F').checked, isTrue);
      expect(rows.firstWhere((r) => r.keyText == 'L').checked, isTrue);
      expect(rows.firstWhere((r) => r.keyText == 'Z').checked, isTrue);
      expect(labelOf('A'), '모두 펴기');
      expect(rows.firstWhere((r) => r.label == '직접만').checked, isTrue);
      expect(rows.firstWhere((r) => r.label == '모두').checked, isFalse);
      expect(rows.last.checked, isTrue, reason: '움직임 계측이 열려 있다');
    });

    test('트랙을 누르면 접기 · 문서 줄이 붙고, 연표 위를 누르면 그때에 무슨 일이가 된다', () {
      final (:bus, :commands) = makeBus();
      final rows = buildMenuRows(bus: bus, spot: MenuSpot(trackId: 3, trackName: '유리해안', at: _year(240) + 12345));
      expect(rows[0].label, '유리해안 접기');
      expect(rows[1].label, '유리해안 문서');
      expect(rows[2].label, '240년에 무슨 일이', reason: '100년을 보고 있으니 해 단위');
      rows[2].onSelected!();
      expect(commands.single.at, _year(240), reason: '누른 자리를 그 해의 처음으로 맞춰 싣는다');
      rows[0].onSelected!();
      expect(commands.last.trackId, 3);

      final folded = buildMenuRows(bus: bus, spot: const MenuSpot(trackId: 3, trackName: '유리해안', folded: true));
      expect(folded[0].label, '유리해안 펴기');
    });

    test('좁게 보고 있으면 그때가 달 · 날까지 적힌다', () {
      final (:bus, commands: _) = makeBus(from: 240, to: 241); // 한 해 폭 → 달
      expect(buildMenuRows(bus: bus, spot: MenuSpot(at: _year(240) + 40 * 24 * 60)).first.label, '240년 2월에 무슨 일이');
    });

    test('항목 위에서 열면 그 항목의 자세히 보기가 맨 위이고, 품은 대범위가 함께 온다', () async {
      final (:bus, :commands) = makeBus();
      final item = await askEntity(bus, _uidPolity);
      final rows = buildMenuRows(bus: bus, item: item, flags: const MenuFlags(scopesOn: {_uidScope: true}));
      expect(rows[0].header, isTrue);
      expect(rows[0].label, '시대 · 은륜 제국');
      expect(rows[1].label, '자세히 보기');
      expect(rows[2].label, '문서');
      expect(rows[2].keyText, 'W');
      expect(rows[3].label, '여기로 확대');
      expect(rows[4].header, isTrue, reason: '대범위 모아 보기는 머리에 한 번(건의 8의 3번)');
      expect(rows[4].label, '대범위 모아 보기');
      expect(rows[5].label, '빈 왕좌의 할거');
      expect(rows[5].checked, isTrue, reason: '이미 모아 보고 있으면 ✓');
      expect(rows[6].label, '은륜 부흥 운동');
      expect(rows[6].checked, isFalse);
      expect(rows[7].sep, isTrue);
      rows[1].onSelected!();
      expect(commands.single.name, Cmd.detail);
      expect(commands.single.uid, _uidPolity);
    });

    test('이름이 스무 자를 넘으면 줄여 적는다', () async {
      final (:bus, commands: _) = makeBus();
      final item = await askEntity(bus, _uidEvent);
      expect(item!.word, '사건');
      expect(buildMenuRows(bus: bus, item: item).first.label, '사건 · ${cutName(item.name)}');
      expect(cutName(item.name).length, 21, reason: '스무 자 + 말줄임표');
    });

    test('자료 처리부가 항목을 모르면 항목 줄 없이 연다', () async {
      final (:bus, commands: _) = makeBus();
      expect(await askEntity(bus, '없는 항목'), isNull);
      expect(buildMenuRows(bus: bus, item: null).first.label, '같은 해');
    });
  });

  group('메뉴 열기', () {
    testWidgets('⋯ 단추의 메뉴는 단추 오른쪽 끝에서 230px 왼쪽에 서고, 고른 줄이 명령이 된다', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus);
      final button = tester.getTopRight(find.byKey(_menuButtonKey));
      await tester.tap(find.text('⋯'));
      await tester.pumpAndSettle();
      final card = tester.getRect(find.ancestor(of: find.text('같은 해'), matching: find.byType(GlassCard)));
      expect(card.width, greaterThanOrEqualTo(230), reason: '메뉴의 최소 폭은 230');
      expect(card.left, closeTo(math.min(button.dx - 230, 1920 - card.width - 4), .01), reason: '단추 오른쪽 끝에서 230px 왼쪽 · 화면 밖으로는 나가지 않게 4px 안으로');
      expect(card.top, greaterThanOrEqualTo(4), reason: '위로 펼치되 화면 위를 넘지 않는다');
      expect(find.text('범례'), findsOneWidget);
      expect(find.text('승계선'), findsOneWidget);

      await tester.tap(find.text('표'));
      await tester.pumpAndSettle();
      expect(commands.single.name, Cmd.table);
      expect(find.text('표'), findsNothing, reason: '고르면 메뉴가 닫힌다');
    });

    testWidgets('연표 위 오른쪽 클릭은 누른 항목의 줄을 맨 위에 두고, 바깥을 누르면 닫힌다', (tester) async {
      final (:bus, :commands) = makeBus();
      await _pumpKeys(tester, bus, spot: const MenuSpot(uid: _uidPolity));
      final gesture = await tester.startGesture(const Offset(900, 700), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('시대 · 은륜 제국'), findsOneWidget);
      expect(find.text('자세히 보기'), findsOneWidget);

      await tester.tapAt(const Offset(1800, 1000));
      await tester.pumpAndSettle();
      expect(find.text('자세히 보기'), findsNothing);
      expect(commands, isEmpty);
    });

    testWidgets('위에 뜬 창(상세 · 범례)의 자리에서는 열지 않는다', (tester) async {
      final (:bus, commands: _) = makeBus();
      await _pumpKeys(tester, bus, spot: const MenuSpot(uid: _uidPolity), blocked: const Rect.fromLTWH(1528, 12, 380, 1052));
      final gesture = await tester.startGesture(const Offset(1700, 500), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('자세히 보기'), findsNothing, reason: '상세 창 위에서는 연표의 메뉴가 열리지 않는다');
    });
  });
}

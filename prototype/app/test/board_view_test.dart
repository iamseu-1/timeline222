import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/gutter.dart' show isBoardChipKey;
import 'package:archive_prototype/scene/paint/scopes.dart' show ScopeIn;
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/board_views.dart';
import 'package:archive_prototype/ui/dlc_manager.dart' show DlcCardInfo, dlcTimelineEmpty;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 집합 보기(10건 6 · 감독 선택 D4 결정 1 A · 2 A · 4 B · 5 A)의 새 앱 몫.
//
// 고정 자료 `fixtures/board-views-layout.json`은 견본 sample-views를 내보내기(`export/boards.mjs`) → 엔진 가져오기로
// 지은 저장소의 `layout` 답 그대로다: 원래 트랙 셋(id 1 · 2 · 3 — 줄 0~4)과 판 트랙 셋(id 4 · 5 · 6 — 판마다 하나 ·
// 줄 5~15). 변형 kind 3이 판 셋(`view:v-three-lands` · `view:v-16og913` · 시대 구분의 임시 판 `view:epoch:…`)이고,
// 판으로 옮겨 가는 원래 줄은 `after` −2(그 줄이 옮겨 간 판 줄 = `ord`)다.
// `fixtures/board-views-entities.json`은 같은 저장소의 판 기록(`board:<열쇠>`) 셋과 시대 구분 기록 하나.
//
// 보는 것: 판을 켜지 않으면 판 트랙은 자리가 없다 · 켜면 판 트랙이 맨 위 · 나머지 트랙은 판의 접힘(접힘 기억은 그대로) ·
// 판으로 옮겨 간 줄은 원래 트랙에서 빠진다 · 끄면 켜기 전과 줄 자리가 같다 · 판 기록 읽기 · 독 단추 · 목록 · 시대 구분 카드.

Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map);

List<Map<String, dynamic>> _entities() => [
  for (final e in jsonDecode(File('test/fixtures/board-views-entities.json').readAsStringSync()) as List) Map<String, dynamic>.from(e as Map),
];

SceneLayout _layout() => SceneLayout.fromJson(_fixture('board-views-layout.json'))..reduceMotion = true;

const threeLands = 'view:v-three-lands', overSea = 'view:v-16og913', epochKey = 'view:epoch:sample-views/ep-sv-three';

List<int> _order(SceneLayout layout) {
  final rows = [for (int r = 0; r < layout.rowCount; r++) if (layout.isVisible(r)) r];
  rows.sort((a, b) => layout.rowTop(a).compareTo(layout.rowTop(b)));
  return rows;
}

int _trackIndex(SceneLayout layout, int id) => layout.tracks.indexWhere((t) => t.id == id);

void main() {
  group('배치(layout.dart)', () {
    test('판을 켜지 않으면 판 트랙은 자리가 없고 판 줄도 보이지 않는다', () {
      final layout = _layout();
      expect(layout.boards.map((v) => v.key), [threeLands, overSea, epochKey]);
      expect([for (int i = 0; i < layout.tracks.length; i++) layout.isBoardTrack(i)], [false, false, false, true, true, true]);
      expect(layout.board, isNull);
      expect(layout.boardTrackIndex, -1);
      expect(_order(layout), [0, 1, 2, 3, 4]);
      for (int i = 3; i < 6; i++) {
        expect(layout.trackTop(i), -1, reason: '켜지 않은 판 트랙 $i는 끈 트랙처럼 자리가 없다');
      }
      expect(layout.allFolded, isFalse);
      // 판 트랙은 접힘 셈에서 빠진다 — 원래 트랙 셋을 모두 접으면 모두 접힌 것이다.
      layout.setViewState(layout.viewState.copyWith(foldedTracks: {1, 2, 3}));
      expect(layout.allFolded, isTrue);
    });

    test('판을 켜면 판 트랙이 맨 위 · 나머지는 판의 접힘 · 옮겨 간 줄은 원래 트랙에서 빠진다', () {
      final layout = _layout();
      final before = [for (int r = 0; r < layout.rowCount; r++) layout.rowTop(r)];
      final total = layout.totalHeight;
      expect(layout.setBoard(threeLands), isTrue);
      expect(layout.board?.key, threeLands);
      final bi = layout.boardTrackIndex;
      expect(layout.tracks[bi].id, 4);
      expect(layout.boardTrackId, 4);
      expect(layout.trackTop(bi), 0, reason: '판 트랙이 맨 위');
      for (int i = 0; i < 3; i++) {
        expect(layout.trackTop(i), greaterThan(0));
        expect(layout.isTrackFolded(layout.tracks[i].id), isTrue, reason: '나머지 트랙은 접힌다(결정 1 A)');
      }
      expect(layout.trackTop(4), -1, reason: '켜지 않은 다른 판 트랙은 그대로 자리가 없다');
      expect(layout.trackTop(5), -1);
      expect(layout.viewState.foldedTracks, isEmpty, reason: '접힘 기억은 건드리지 않는다');
      // 판 줄 5 · 6 · 7이 차례로 맨 위에 — 첫 줄은 판 머리(대범위 가지와 같은 탭 · 머리 16) 아래.
      final order = _order(layout);
      expect(order.take(3), [5, 6, 7]);
      expect(layout.rowTop(5), greaterThan(0));
      expect(layout.rowTop(6), greaterThan(layout.rowTop(5)));
      // 원래 트랙에서 판으로 옮겨 간 줄(0 · 2 · 3)은 빠진다(접힌 트랙이라 남은 줄도 보이지 않는다).
      for (final r in [0, 2, 3]) {
        expect(layout.isVisible(r), isFalse, reason: '줄 $r은 판으로 옮겨 갔다');
        expect(layout.boardRowOf(r), {0: 5, 2: 6, 3: 7}[r]);
      }
      expect(layout.boardRowOf(1), 1, reason: '판에 들지 않은 줄은 그대로');
      // 끄면 켜기 전과 줄 자리 · 높이가 같다.
      expect(layout.setBoard(''), isTrue);
      expect(layout.board, isNull);
      expect([for (int r = 0; r < layout.rowCount; r++) layout.rowTop(r)], before);
      expect(layout.totalHeight, total);
      expect(layout.setBoard(''), isFalse, reason: '이미 꺼져 있다');
      expect(layout.setBoard('view:없는-판'), isFalse, reason: '저장소에 없는 판은 켜지 않는다');
    });

    test('판을 켠 동안 트랙을 펴면 판의 접힘만 바뀌고 판으로 옮겨 간 줄은 여전히 빠져 있다', () {
      final layout = _layout()..setBoard(threeLands);
      expect(layout.foldTrack(1, false), isTrue);
      expect(layout.isTrackFolded(1), isFalse);
      expect(layout.viewState.foldedTracks, isEmpty);
      expect(layout.viewState.boardOpen, contains(1));
      expect(layout.isVisible(1), isTrue, reason: '판에 들지 않은 줄 1은 편 트랙에 남는다');
      expect(layout.isVisible(0), isFalse, reason: '줄 0은 판으로 옮겨 갔다');
      // 판 트랙 자체도 접힌다(판의 접힘).
      final bi = layout.boardTrackIndex;
      expect(layout.foldTrack(4, true), isTrue);
      expect(layout.isTrackFolded(4), isTrue);
      expect(layout.isVisible(5), isFalse);
      expect(layout.trackTop(bi), 0);
      // 모두 펴기 — 판의 접힘으로(기억은 그대로).
      expect(layout.foldAll(false), isTrue);
      for (final t in [1, 2, 3, 4]) {
        expect(layout.isTrackFolded(t), isFalse);
      }
      expect(layout.viewState.foldedTracks, isEmpty);
      // 판을 끄면 판의 접힘은 사라지고 접힘 기억대로.
      layout.setBoard('');
      expect(layout.viewState.boardOpen, isEmpty);
      expect(layout.viewState.boardFolded, isFalse);
      expect([for (final t in [1, 2, 3]) layout.isTrackFolded(t)], [false, false, false]);
    });

    test('접힘 기억이 있던 트랙도 판을 켜면 접히고, 끄면 기억대로 돌아온다', () {
      final layout = _layout();
      layout.setViewState(layout.viewState.copyWith(foldedTracks: {2}));
      final before = [for (int r = 0; r < layout.rowCount; r++) layout.rowTop(r)];
      layout.setBoard(overSea);
      expect(layout.boardTrackId, 5);
      expect(_order(layout).take(3), [8, 9, 10]);
      expect(layout.boardRowOf(2), 8);
      expect(layout.boardRowOf(4), 9);
      expect(layout.boardRowOf(1), 10);
      layout.setBoard('');
      expect(layout.viewState.foldedTracks, {2});
      expect([for (int r = 0; r < layout.rowCount; r++) layout.rowTop(r)], before);
    });

    test('판을 바꿔 켜면 한 판만 — 앞의 판 트랙은 자리가 없어진다', () {
      final layout = _layout()..setBoard(threeLands);
      layout.setBoard(epochKey);
      expect(layout.board?.key, epochKey);
      expect(layout.trackTop(_trackIndex(layout, 4)), -1);
      expect(layout.trackTop(_trackIndex(layout, 6)), 0);
      expect(_order(layout).take(5), [11, 12, 13, 14, 15]);
      for (int r = 0; r < 5; r++) {
        expect(layout.isVisible(r), isFalse, reason: '임시 판은 원래 줄 다섯을 모두 옮긴다');
      }
    });

    test('가려는 곳 펴기: 판으로 옮겨 간 줄은 판 줄로 — 판 트랙이 접혀 있으면 판 트랙을 편다', () {
      final layout = _layout()..setBoard(threeLands);
      layout.foldTrack(4, true);
      final next = layout.revealFor(3);
      expect(next.board, threeLands);
      expect(next.boardFolded, isFalse, reason: '줄 3은 판 줄 7로 옮겨 갔으니 판 트랙을 편다');
      expect(next.foldedTracks, isEmpty);
      // 판에 들지 않은 줄은 그 트랙만 판의 접힘에서 편다.
      final other = layout.revealFor(1);
      expect(other.boardOpen, contains(1));
      expect(other.foldedTracks, isEmpty);
    });

    test('보이는 줄의 번호 범위 — 판을 켜면 위 끝(판 줄)의 번호가 아래 끝보다 크다', () {
      final layout = _layout();
      final (lo0, hi0) = layout.rowRange(0, 100000);
      expect((lo0, hi0), (0, 4));
      layout
        ..setBoard(threeLands)
        ..foldAll(false);
      final (lo, hi) = layout.rowRange(0, 100000);
      expect(lo, 1, reason: '판을 켜면 0 · 2 · 3은 빠지고 1 · 4가 남는다');
      expect(hi, 7);
      expect(layout.visibleRowsFrom(5).toList(), [5, 6, 7, 1, 4]);
    });

    test('ViewState: 판 · 판의 접힘은 같은 줄 쌓기 비교에 든다 · 판 트랙을 누른 것은 판의 접힘으로 알아본다', () {
      const a = ViewState.none;
      final b = a.withBoard(threeLands);
      expect(b.board, threeLands);
      expect(b.stacksSameAs(a), isFalse);
      expect(b.withBoard('').stacksSameAs(a), isTrue);
      final folded = b.copyWith(boardFolded: true);
      expect(ViewState.foldToggled(b, folded, boardTrack: 4), 4);
      final opened = b.withBoardTrackOpen(2, true);
      expect(ViewState.foldToggled(b, opened, boardTrack: 4), 2);
    });
  });

  group('그리기 · 둘레의 표시', () {
    test('판 둘레는 구역 23의 a 비트 8 · 왼쪽 칸 칩은 접기 단추가 아니다', () {
      ScopeIn scope(int a) => ScopeIn(1, 5, 7, 300, 520, 0, BoardInfo.butter, a, '세 땅 같은 시기 견주기', '집합 보기 · 트랙 3 · 나라 3');
      expect(scope(8).board, isTrue);
      expect(scope(8 | 4).board, isTrue, reason: '기간 없는 판은 짐작 비트 4가 함께 선다');
      expect(scope(8 | 4).guessed, isTrue);
      expect(scope(1).board, isFalse, reason: '매달린 대범위는 판이 아니다');
      expect(scope(0).board, isFalse);
      expect(ScopeIn.boardRef, '__board');
      expect(isBoardChipKey('__from:sv-east#0'), isTrue);
      expect(isBoardChipKey('__bp:people-a#1'), isTrue);
      expect(isBoardChipKey('__scope:sample-views/sc-one'), isFalse);
      expect(isBoardChipKey(''), isFalse);
    });

    test('DLC 카드 · 빈 연표 셈은 판 트랙을 세지 않는다', () {
      final layout = _layout();
      final cards = DlcCardInfo.of(layout);
      expect(cards.single.tracks.map((t) => t.id), [1, 2, 3], reason: '판 트랙(4 · 5 · 6)은 담긴 트랙이 아니다');
      expect(cards.single.shared, isEmpty);
      expect(dlcTimelineEmpty(layout), isFalse);
    });
  });

  group('판 기록(BoardInfo)', () {
    test('판 기록의 JSON을 읽는다 — 이름 · 색 · 기간 · 나라 · 임시 판', () {
      final layout = _layout();
      final records = {for (final e in _entities()) if (e['kind'] == 'board') e['uid']: jsonDecode(e['json'] as String) as Map<String, dynamic>};
      final three = BoardInfo.of(layout.boards[0], records['board:$threeLands']);
      expect(three.name, '세 땅 같은 시기 견주기');
      expect(three.color, 0xd7c18e);
      expect(three.temp, isFalse);
      expect((three.start, three.end), (300.0, 520.0));
      expect(three.members.map((m) => m.name), ['솔빛 왕국', '물결 연맹', '높은 고개 나라']);
      expect(three.countText, '나라 3 · 트랙 3');
      final sea = BoardInfo.of(layout.boards[1], records['board:$overSea']);
      expect(sea.start, isNull, reason: '기간이 없는 판은 켜도 보던 시기 그대로');
      final epoch = BoardInfo.of(layout.boards[2], records['board:$epochKey']);
      expect(epoch.temp, isTrue);
      expect(epoch.epoch, 'sample-views/ep-sv-three');
      expect(epoch.members, hasLength(5));
      expect(epoch.scoped, isFalse);
      // 기록을 못 읽으면 변형의 이름 · 버터 색.
      final bare = BoardInfo.of(layout.boards[0], null);
      expect(bare.name, layout.boards[0].name);
      expect(bare.color, BoardInfo.butter);
      expect(bare.temp, isFalse);
    });
  });

  group('화면 부품(board_views.dart)', () {
    late Directory folder;
    setUp(() => folder = Directory.systemTemp.createTempSync('board-views-'));
    tearDown(() => folder.deleteSync(recursive: true));

    Future<AppMemory> openMemory(WidgetTester tester) async {
      // 화면 검사의 가상 시계에서 파일 쓰기가 시작되면 runAsync로도 그 줄을 마칠 수 없다.
      // 모아 쓰는 시각은 검사 뒤로 두고, 실제 시계에서 flush가 끝나 파일을 놓은 뒤 폴더를 지운다.
      final memory = (await tester.runAsync(() => AppMemory.open(folder: folder, delay: const Duration(days: 1))))!;
      addTearDown(() async {
        await tester.runAsync(memory.flush);
        memory.dispose();
      });
      return memory;
    }

    /// 고정 자료의 배치로 장면 · 길을 세우고 판 상태를 짓는다. 판 켜기는 앱 틀(`archive_app.dart`의 `_applyBoard`)과 같은 길.
    (AppBus, BoardViews, List<String>) build(WidgetTester tester, {Map<String, dynamic>? layoutJson, AppMemory? memory, Map<String, Map<String, dynamic>>? recordsOverride}) {
      // 움직임 줄이기 — 다시 쌓기가 흐르지 않고 바로 그 자리로(흐름은 장면 시계가 돌려야 끝난다).
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1280, 720)
        ..setExtent(0, 1000 * 525960)
        ..setContentHeight(2000);
      final scene = TimelineScene(
        controller: controller,
        layout: SceneLayout.fromJson(layoutJson ?? _fixture('board-views-layout.json'))..reduceMotion = true,
        fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      final records = recordsOverride ?? {for (final e in _entities()) e['uid']: e};
      final bus = AppBus(
        ask: (query) async {
          final hit = records[query['uid']];
          if (hit == null) throw StateError('없는 기록');
          return hit;
        },
        controller: controller,
        scene: scene,
      );
      final applied = <String>[];
      final views = BoardViews(
        bus: bus,
        memory: memory == null ? null : () => memory,
        apply: (key, hold) {
          applied.add(key);
          final ok = scene.applyViewState(scene.layout.withBoardState(key), hold: hold);
          controller.setContentHeight(scene.layout.totalHeight);
          return ok;
        },
      );
      bus.slot(BoardViews.slotName).value = views;
      addTearDown(() {
        views.dispose();
        bus.dispose();
        scene.dispose();
        controller.dispose();
      });
      return (bus, views, applied);
    }

    Finder switchOf(String label) => find.byWidgetPredicate((w) => w is BoardSwitch && w.label == label);

    Widget host(AppBus bus, BoardViews views, {Widget? body}) => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(left: 16, top: 16, child: Row(children: [BoardDockButton(views: views)])),
            if (body != null) Positioned(left: 16, top: 120, width: 400, child: body),
            Positioned.fill(child: BoardListLayer(views: views)),
          ],
        ),
      ),
    );

    testWidgets('판이 없는 저장소에서는 독 단추가 자리도 차지하지 않는다', (tester) async {
      final json = _fixture('board-views-layout.json');
      json['variants'] = const <dynamic>[];
      final (bus, views, _) = build(tester, layoutJson: json);
      await tester.pumpWidget(host(bus, views));
      expect(find.text('집합 보기'), findsNothing);
      expect(find.byTooltip('집합 보기'), findsNothing);
    });

    testWidgets('저장소를 다시 지으면 같은 판 열쇠도 이름 · 색 · 기간 · 나라를 다시 읽는다', (tester) async {
      final records = <String, Map<String, dynamic>>{for (final e in _entities()) e['uid'] as String: e};
      final (bus, views, _) = build(tester, recordsOverride: records);
      await tester.runAsync(views.load);
      expect(views.saved.first.name, '세 땅 같은 시기 견주기');
      final record = records['board:$threeLands']!;
      final changed = Map<String, dynamic>.from(jsonDecode(record['json'] as String) as Map)
        ..['name'] = '고친 두 땅 견주기'
        ..['color'] = '#91abc5'
        ..['start'] = 400
        ..['end'] = 500
        ..['present'] = 2
        ..['tracks'] = 2;
      changed['members'] = (changed['members'] as List).take(2).toList();
      records['board:$threeLands'] = {...record, 'json': jsonEncode(changed)};
      await tester.runAsync(() async {
        views.layoutChanged();
        await Future<void>.delayed(Duration.zero);
      });
      final updated = views.saved.first;
      expect(updated.name, '고친 두 땅 견주기');
      expect(updated.color, 0x91abc5);
      expect((updated.start, updated.end), (400.0, 500.0));
      expect(updated.members, hasLength(2));
      expect(updated.countText, '나라 2 · 트랙 2');
      views.turnOn(threeLands);
      expect(views.active?.name, updated.name);
      expect(bus.go.value?.lo, DateTime.utc(388).millisecondsSinceEpoch / 60000, reason: '새 기간의 양쪽 12%로 이동');
      expect(bus.go.value?.hi, DateTime.utc(512).millisecondsSinceEpoch / 60000);
    });

    testWidgets('B 독 오른쪽 단추의 목록은 화면 안과 독 아래에 선다', (tester) async {
      final (_, views, _) = build(tester);
      await tester.runAsync(views.load);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(children: [
        Positioned(right: 16, top: 12, child: BoardDockButton(views: views)),
        Positioned.fill(child: BoardListLayer(views: views)),
      ]))));
      await tester.tap(find.byTooltip('집합 보기'));
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byType(GlassCard));
      expect(menu.top, 70);
      expect(menu.right, lessThanOrEqualTo(788));
      expect(menu.left, greaterThanOrEqualTo(12));
      expect(menu.width, 440);
    });

    testWidgets('독 단추 → 목록(DLC 판 둘 · 임시 판은 목록에 없음) → 스위치로 켜고 끄기 · 기억', (tester) async {
      final memory = await openMemory(tester);
      final (bus, views, applied) = build(tester, memory: memory);
      await tester.runAsync(views.load);
      await tester.pumpWidget(host(bus, views));
      expect(find.byTooltip('집합 보기'), findsOneWidget);
      await tester.tap(find.byTooltip('집합 보기'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(views.listOpen, isTrue);
      expect(find.text('세 땅 같은 시기 견주기'), findsOneWidget);
      expect(find.text('바다 건너 교역 상대'), findsOneWidget);
      expect(find.text('세 땅 시대'), findsNothing, reason: '시대 구분의 임시 판은 켜기 전에는 목록에 없다');
      expect(find.text('나라 3 · 트랙 3'), findsNWidgets(2));
      // 첫 판의 스위치를 켠다.
      await tester.tap(switchOf('집합 보기 세 땅 같은 시기 견주기'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(applied, [threeLands]);
      expect(views.activeKey, threeLands);
      expect(bus.scene.layout.board?.key, threeLands);
      expect(memory.parts['board'], {'key': threeLands}, reason: '켠 DLC 판은 기억한다');
      expect(bus.go.value, isNotNull, reason: '판의 기간으로 날아간다');
      expect(bus.controller.view.top, 0, reason: '판의 머리가 화면 맨 위');
      // 단추의 풍선에 켠 판의 이름(단추는 기호만 — 건의 8의 1번).
      expect(find.byTooltip('집합 보기 · 세 땅 같은 시기 견주기'), findsOneWidget);
      expect(find.text('세 땅 같은 시기 견주기'), findsOneWidget);
      // Esc는 목록만 닫는다.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(views.listOpen, isFalse);
      expect(views.activeKey, threeLands);
      // 끄기 — 기억도 지운다.
      views.toggle(threeLands);
      await tester.pump(const Duration(milliseconds: 400));
      expect(views.activeKey, isEmpty);
      expect(memory.parts.containsKey('board'), isFalse);
      // 기억에서 되살리기(날아가지 않음).
      memory.parts['board'] = {'key': overSea};
      bus.go.value = null;
      views.restore();
      await tester.pump(const Duration(milliseconds: 400));
      expect(views.activeKey, overSea);
      expect(bus.go.value, isNull, reason: '되살릴 때는 보던 범위 그대로');
      // 사라진 판의 기억은 지운다.
      views.turnOff();
      memory.parts['board'] = {'key': 'view:없는-판'};
      views.restore();
      expect(views.activeKey, isEmpty);
      expect(memory.parts.containsKey('board'), isFalse);
      await tester.runAsync(memory.flush);
    });

    testWidgets('기억에서 되살리면 세로 자리를 그대로 둔다(저장소를 다시 지은 뒤에도 맨 위로 튀지 않음)', (tester) async {
      final memory = await openMemory(tester);
      final (bus, views, _) = build(tester, memory: memory);
      final layout = bus.scene.layout;
      bus.controller
        ..resize(1280, 200)
        ..setContentHeight(layout.totalHeight)
        ..scrollTo(40);
      memory.parts['board'] = {'key': threeLands};
      views.restore();
      expect(views.activeKey, threeLands);
      expect(bus.controller.view.top, 40, reason: '되살릴 때는 판의 머리로 올리지 않는다');
      await tester.runAsync(memory.flush);
    });

    testWidgets('끄면 켜기 전에 화면 맨 위에 있던 줄로 돌아온다', (tester) async {
      final (bus, views, _) = build(tester);
      final layout = bus.scene.layout;
      // 창을 낮게 — 다섯 줄짜리 견본도 세로로 넘쳐 맨 위 줄을 고를 수 있게(리메이크 2부: 꼬리표가 머리 한 줄로 낮아져 200에서는 덜 넘친다).
      bus.controller
        ..resize(1280, 150)
        ..setContentHeight(layout.totalHeight)
        ..scrollTo(layout.rowTop(2) + 5);
      final top = bus.controller.view.top;
      expect(top, layout.rowTop(2) + 5);
      views.turnOn(threeLands, fly: false);
      expect(bus.controller.view.top, 0);
      views.turnOff();
      expect(bus.controller.view.top, top);
    });

    testWidgets('시대 구분 카드: 나라 칩 다섯 · 스위치 = 임시 판(기억하지 않음) · 칩을 누르면 그 나라', (tester) async {
      final memory = await openMemory(tester);
      final (bus, views, applied) = build(tester, memory: memory);
      await tester.runAsync(views.load);
      await tester.pumpWidget(host(bus, views, body: BoardEpochCard(bus: bus, epochUid: 'sample-views/ep-sv-three')));
      // 상자 머리는 제목 · 작은 글이 한 글줄(Text.rich).
      expect(find.text('이 시대의 나라 5', findRichText: true), findsOneWidget);
      for (final name in ['솔빛 왕국', '갈대 나라', '물결 연맹']) {
        expect(find.text(name), findsOneWidget);
      }
      await tester.tap(find.text('갈대 나라'));
      expect(bus.selection.value?.uid, 'sample-views/sv-reed');
      await tester.tap(switchOf('집합 보기 세 땅 시대'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(applied, [epochKey]);
      expect(views.activeKey, epochKey);
      expect(memory.parts.containsKey('board'), isFalse, reason: '임시 판은 기억하지 않는다');
      expect(find.text('저장하지 않은 판입니다 — 끄면 사라지고 켜기 전 모습으로 돌아갑니다.'), findsOneWidget);
      // 독 단추의 풍선에 임시 판의 이름 · 목록 맨 위에 '저장하지 않은 판'.
      await tester.tap(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('집합 보기 · ')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('저장하지 않은 판'), findsOneWidget);
      // 없는 시대 구분은 카드가 없다.
      await tester.pumpWidget(host(bus, views, body: BoardEpochCard(bus: bus, epochUid: 'sample-views/없는-시대')));
      expect(find.textContaining('이 시대의 나라', findRichText: true), findsNothing);
      await tester.runAsync(memory.flush);
    });
  });
}

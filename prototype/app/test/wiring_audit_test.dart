import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/emphasis.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_glue.dart';
import 'package:archive_prototype/ui/cards.dart';
import 'package:archive_prototype/ui/context_menu.dart';
import 'package:archive_prototype/ui/detail_echo.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/edge_hint.dart';
import 'package:archive_prototype/ui/filter_state.dart';
import 'package:archive_prototype/ui/legend.dart';
import 'package:archive_prototype/ui/metro_card.dart';
import 'package:archive_prototype/ui/motion_meter.dart';
import 'package:archive_prototype/ui/search.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:archive_prototype/ui/tools_measure.dart';
import 'package:archive_prototype/ui/tools_year.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 전역 검사 ㈏ — **연결**: 누르면 무엇이 일어나야 하는데 실제로 이어져 있는가.
// 진짜 [AppBus] · 진짜 [AppGlue] · 진짜 부품(검색 머리 · 묶음 카드 머리 · 필터 값)에 가짜 다리와 가짜 자료를 끼워 돌린다.
// 지금 끊긴 자리는 `skip: '끊김 — 보고서 n번'`으로 남겨 두었다(번호는 `docs/검사-전역-연결-2026-09-22.md`의 맨 위 목록).
// 화면(위젯)이 있어야만 볼 수 있는 끊김(빈 곳 누르기 · 알약에 손 올리기 · 날짜 칸 고르기)은 보고서에만 적었다.

/// 무엇이 불렸는지만 적어 두는 다리.
class _FakeBridge implements SceneBridge {
  final gone = <GoRequest>[];
  final looks = <Look>[];
  final folds = <bool>[];
  bool canFold = true;

  @override
  void go(GoRequest request, {double insetRight = 0}) => gone.add(request);

  @override
  void emphasize(Look look) => looks.add(look);

  @override
  Future<MenuSpot> probe(Offset local) async => const MenuSpot();

  @override
  bool foldAll(bool folded) {
    folds.add(folded);
    return canFold;
  }
}

/// 가짜 자료 처리부: 물은 것을 적어 두고 `ids_of` · `search`에만 답한다.
class _FakeData {
  final asked = <Map<String, dynamic>>[];

  /// uid → (띠 번호, 줄, 시작, 끝).
  final places = <String, (int, int, double, double)>{};

  /// `search` · `search_year`가 돌려줄 줄.
  List<Map<String, dynamic>> hits = const [];

  Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async {
    asked.add(query);
    switch (query['op']) {
      case 'ids_of':
        final uids = (query['uids'] as List).cast<String>();
        return {
          'bands': [
            for (final uid in uids)
              if (places[uid] != null) {'uid': uid, 'id': places[uid]!.$1, 'row': places[uid]!.$2, 'start': places[uid]!.$3, 'end': places[uid]!.$4},
          ],
          'events': const [],
        };
      case 'search':
      case 'search_year':
        return {'items': hits};
      default:
        return const {};
    }
  }

  /// 마지막으로 그 명령에 보낸 물음.
  Map<String, dynamic>? lastOf(String op) {
    for (final one in asked.reversed) {
      if (one['op'] == op) return one;
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 트랙 하나 · 줄 둘짜리 아주 작은 장면(그리기 층은 쓰지 않는다 — 이 검사는 이어 붙이기만 본다).
  TimelineScene makeScene() {
    Map<String, dynamic> row(int id) => {
      'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
      'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
    };
    final controller = TimelineController()
      ..resize(1920, 800)
      ..setExtent(-1000000, 1000000)
      ..setContentHeight(284);
    return TimelineScene(
      controller: controller,
      layout: SceneLayout.fromJson({
        'packs': [
          {'id': 1, 'name': '별여울 기록집', 'events': 12},
        ],
        'tracks': [
          {'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'rows': [row(0), row(1)]},
        ],
        'epochs': const [],
      }),
      fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
    );
  }

  (AppBus, _FakeBridge, _FakeData) build() {
    final scene = makeScene();
    addTearDown(scene.dispose);
    addTearDown(scene.controller.dispose);
    final data = _FakeData();
    final bus = AppBus(ask: (query) async => wrapAnswer(await data.ask(query)), controller: scene.controller, scene: scene);
    addTearDown(bus.dispose);
    return (bus, _FakeBridge(), data);
  }

  AppGlue glueOf(AppBus bus, _FakeBridge bridge, {List<String>? done}) {
    final glue = AppGlue(
      bus: bus,
      bridge: bridge,
      onFilter: () => done?.add(Cmd.filter),
      onTable: () => done?.add(Cmd.table),
      onImage: () => done?.add(Cmd.image),
      onPacks: () => done?.add(Cmd.dlc),
      onSearchFocus: () => done?.add(Cmd.search),
      onSearchClose: () => done?.add(Cmd.searchClose),
      onClose: () => done?.add(Cmd.close),
      onNotice: (text) => done?.add('notice:$text'),
    )..start();
    addTearDown(glue.dispose);
    return glue;
  }

  // ────────────────────────────────────────────────────────────────────────
  //  1. 슬롯 이름이 맞물리는가 — 쓰는 쪽과 듣는 쪽이 같은 글자를 보는가
  // ────────────────────────────────────────────────────────────────────────

  group('슬롯 이름', () {
    test('부품이 쓰는 이름과 듣는 쪽의 이름이 같다', () {
      // 단축키 · 도구 · 범례가 제 파일에 적어 둔 이름.
      expect(slotCommand, 'command');
      expect(slotZen, 'zen');
      expect(slotNotice, 'notice');
      expect(yearSlot, 'yearPanel');
      expect(markerSlot, 'marker');
      expect(measureSlot, 'measure');
      expect(measureOnSlot, 'measure_on');
      expect(legendSlot, 'legend');
      expect(EdgeHint.slot, 'edge-hint');
      // 이어 붙이기가 모아 둔 이름.
      expect(slotDetail, 'detail');
      expect(slotFilters, 'filters');
      expect(slotFoldAll, 'foldAll');
      expect(slotSearchHits, 'searchHits');
      expect(slotSpots, 'spots');
      expect(slotHouse, 'house');
      expect(slotEcho, 'echo');
      expect(slotScopes, 'scopes');
      expect(slotDoc, 'doc');
    });

    test('앱 틀이 표시 상태로 옮기는 세 슬롯의 이름이 도구의 것과 같다', () {
      // archive_app.dart의 `_syncMarks`가 글자 그대로 적어 두었다 — 도구 쪽 이름이 바뀌면 조용히 끊긴다.
      expect([markerSlot, measureSlot, measureOnSlot], ['marker', 'measure', 'measure_on']);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  //  2. 명령마다 받는 쪽이 있는가
  // ────────────────────────────────────────────────────────────────────────

  group('명령', () {
    test('이어 붙이기가 맡은 명령은 모두 받는 쪽이 불린다', () async {
      final (bus, bridge, data) = build();
      final done = <String>[];
      glueOf(bus, bridge, done: done);

      for (final name in [Cmd.filter, Cmd.table, Cmd.image, Cmd.dlc, Cmd.search, Cmd.searchClose, Cmd.close]) {
        runCommand(bus, name);
      }
      expect(done, [Cmd.filter, Cmd.table, Cmd.image, Cmd.dlc, Cmd.search, Cmd.searchClose, Cmd.close]);

      bus.controller.showRange(0, 1000000);
      runCommand(bus, Cmd.fit);
      expect(bus.controller.view.span, closeTo(bus.controller.maxSpan, 1));

      runCommand(bus, Cmd.bird);
      expect(bus.conditions.value.density, 2);

      runCommand(bus, Cmd.foldAll);
      expect(bridge.folds, [true]);

      runCommand(bus, Cmd.detail, uid: '별여울/유리항');
      expect(bus.selection.value?.uid, '별여울/유리항');

      data.places['별여울/유리항'] = (100, 1, 1000, 2000);
      runCommand(bus, Cmd.focusOn, uid: '별여울/유리항');
      await Future<void>.delayed(Duration.zero);
      expect(bridge.gone.last.ring, '별여울/유리항');
    });

    test('메뉴의 `대범위 모아 보기`가 그 대범위를 켠다', () {
      final (bus, bridge, _) = build();
      glueOf(bus, bridge);
      final scopes = '별여울/삼국시대';
      runCommand(bus, Cmd.scope, uid: scopes);
      expect(bus.scene.layout.isScopeOpen(scopes), isTrue);
    }, skip: '보고서 1번 · 앱 틀(archive_app.dart)에서 이음 — 이 검사는 이어 붙이기(AppGlue)만 세워 그 길을 타지 않는다');

    test('메뉴의 승계선 세 값이 표시 상태로 간다', () {
      final (bus, bridge, _) = build();
      glueOf(bus, bridge);
      bus.slot(slotFilters).value = const FilterState();
      runCommand(bus, Cmd.succession, arg: 'direct');
      expect((bus.slot(slotFilters).value! as FilterState).showValue('succession'), 'direct');
    }, skip: '보고서 8번 · 앱 틀(archive_app.dart)에서 이음 — 이 검사는 이어 붙이기(AppGlue)만 세워 그 길을 타지 않는다');

    test('메뉴의 `접기: 〈트랙〉`이 그 트랙을 접는다', () {
      final (bus, bridge, _) = build();
      glueOf(bus, bridge);
      runCommand(bus, Cmd.fold, trackId: 1);
      expect(bus.scene.layout.isTrackFolded(1), isTrue);
    }, skip: '보고서 7번 · 앱 틀(archive_app.dart)에서 이음 — 이 검사는 이어 붙이기(AppGlue)만 세워 그 길을 타지 않는다');

    test('`📄 문서`(W · 메뉴)가 문서 슬롯에 열쇠를 싣는다', () {
      final (bus, bridge, _) = build();
      glueOf(bus, bridge);
      runCommand(bus, Cmd.wiki, uid: '별여울/유리항');
      expect(bus.slot(slotDoc).value, '별여울/유리항');
    }, skip: '문서 창(DocWindow)이 스스로 받음 — 이 검사는 이어 붙이기(AppGlue)만 세워 그 길을 타지 않는다(doc_window_test가 확인)');

    testWidgets('`◔ 움직임 계측`이 받는 쪽이 있다', (tester) async {
      // 받는 쪽은 이어 붙이기(AppGlue)가 아니라 계측 창 부품이다 — 앱 틀의 Stack에 선 채로 명령을 듣는다.
      final (bus, _, _) = build();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(children: [Positioned.fill(child: MotionMeter(bus: bus))]))));
      expect(MotionMeter.isOpen(bus), isFalse);
      runCommand(bus, Cmd.motion);
      await tester.pump();
      expect(MotionMeter.isOpen(bus), isTrue, reason: '메뉴의 ◔가 계측 창을 연다(archive_app.dart의 Stack에 선다)');
      runCommand(bus, Cmd.motion);
      await tester.pump();
      expect(MotionMeter.isOpen(bus), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('`🚇 노선도`(상세 창 · 왼쪽 칸의 노선 표시)가 받는 쪽이 있다', (tester) async {
      // 지금 연표는 노선도를 **왼쪽 줄 이름**(`GutterHitKind.cap` — 앱 틀의 `gutterHit`에서 이음)과 **상세 창의 `🚇`** 둘로만 연다(명세 06의 7-19).
      // 여기서는 그 둘이 쓰는 슬롯에 실어, 받는 부품(노선도 카드)이 실제로 그 값을 집어 가는지만 본다.
      final (bus, _, _) = build();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(children: [Positioned.fill(child: MetroCard(bus: bus))]))));
      bus.slot(metroSlot).value = const MetroRequest('별여울/유리항', pinned: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 가짜 자료에는 그 정권이 없다 — 카드가 값을 집어 가 슬롯을 비우고 안내를 띄운다(받는 쪽이 없으면 값이 그대로 남는다).
      expect(bus.slot(metroSlot).value, isNull, reason: '노선도 카드가 슬롯을 듣고 있다');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  //  3. 고르면 밝기 상태(Look)가 채워지는가
  // ────────────────────────────────────────────────────────────────────────

  group('밝기 상태', () {
    test('고르기 · 검색 강조 · 기간 조명 · 가문이 모두 다리로 간다', () async {
      final (bus, bridge, data) = build();
      data.places
        ..['별여울/유리항'] = (11, 0, 0, 10)
        ..['별여울/검색'] = (22, 1, 0, 10);
      glueOf(bus, bridge);

      bus.select('별여울/유리항', kind: 'period');
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.event, isNull, reason: '띠를 고르면 사건 번호는 비어 있다');

      bus.slot(slotSearchHits).value = ['별여울/검색'];
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.bands, {22});

      bus.slot(slotSpots).value = [
        {'uid': '별여울/유리항', 'start': 100, 'end': 200, 'cell': 'leader:3'},
      ];
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.spots.single.band, 11);
      expect(bridge.looks.last.spots.single.cell, 'leader:3');

      bus.slot(slotHouse).value = 'house:은결';
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.house, 'house:은결');
    });

    test('단체 · 제도 창을 열면 띠를 고른 밝기가 걸리지 않는다(Look.band가 null — 연표가 흐려지지 않는다)', () async {
      final (bus, bridge, data) = build();
      // 같은 uid에 띠가 있다고 답해도(있을 수 없지만) 단체 창은 그 띠를 고르지 않는다.
      data.places['별여울/동쪽 무리'] = (33, 1, 0, 10);
      glueOf(bus, bridge);
      bus.select('별여울/동쪽 무리', kind: 'group');
      bus.slot(slotDetail).value = DetailState(uid: '별여울/동쪽 무리', kind: 'group', branch: pickDetailKind(kind: 'group'), fresh: true, inset: 392);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.band, isNull);
      expect(bridge.looks.last.row, isNull);
      expect(bridge.looks.last.spots, isEmpty);
      expect(bridge.looks.last.lit, isFalse);

      bus.select('별여울/조세제도', kind: 'institution');
      bus.slot(slotDetail).value = DetailState(uid: '별여울/조세제도', kind: 'institution', branch: pickDetailKind(kind: 'institution'), fresh: true, inset: 392);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.band, isNull);

      // 견줌: 같은 자리를 기본 창으로 열면 그 띠가 밝아진다 — 위의 null은 갈래 때문이다.
      bus.select('별여울/동쪽 무리', kind: 'period');
      bus.slot(slotDetail).value = DetailState(uid: '별여울/동쪽 무리', kind: 'period', branch: pickDetailKind(kind: 'period'), fresh: true, inset: 392);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.band, 33);
    });

    test('연표에서 고른 사건은 이름이 없어도 그 점이 밝아진다', () async {
      final (bus, bridge, _) = build();
      final glue = glueOf(bus, bridge);
      await glue.pickEvent(77, row: 1);
      expect(bridge.looks.last.event, 77);
      expect(bridge.looks.last.row, 1);
    });

    test('같은 시기 타국(메아리)의 사건이 밝기 상태에 실린다', () async {
      final (bus, bridge, _) = build();
      glueOf(bus, bridge);
      // 메아리는 조명을 건 창이 있어야 있다(명세 — 스위치만으로는 실릴 것이 없다).
      bus.slot(slotDetail).value = const DetailState(uid: '별여울/유리항', kind: 'period', branch: DetailKind('dynasty', spot: true), fresh: true, inset: 392);
      bus.slot(slotEchoHits).value = const EchoHits(ownUids: [], echoIds: [7, 9]);
      bus.slot(slotEcho).value = true;
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.echo, {7, 9});
      expect(bridge.looks.last.lit, isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  //  4. 슬롯에 적었는데 듣는 이가 없는 것
  // ────────────────────────────────────────────────────────────────────────

  group('듣는 이 없는 슬롯', () {
    test('필터 시트의 `▾ 모두 접기`가 실제로 트랙을 접는다', () {
      final (bus, bridge, _) = build();
      glueOf(bus, bridge);
      // 필터 시트(filter_sheet_body.dart)는 슬롯에 바라는 값을 적기만 한다.
      bus.slot(slotFoldAll).value = true;
      expect(bridge.folds, [true]);
    }, skip: '보고서 3번 · 앱 틀(archive_app.dart)에서 이음 — 이 검사는 이어 붙이기(AppGlue)만 세워 그 길을 타지 않는다');

    test('상세 창의 모아 보기 스위치가 연표의 대범위를 켠다', () {
      final (bus, bridge, _) = build();
      glueOf(bus, bridge);
      bus.slot(slotScopes).value = {'별여울/삼국시대': true};
      expect(bus.scene.layout.isScopeOpen('별여울/삼국시대'), isTrue);
    }, skip: '보고서 1번 · 앱 틀(archive_app.dart)에서 이음 — 이 검사는 이어 붙이기(AppGlue)만 세워 그 길을 타지 않는다');
  });

  // ────────────────────────────────────────────────────────────────────────
  //  5. 필터 시트의 값이 연표의 보기 조건에 닿는가
  // ────────────────────────────────────────────────────────────────────────

  group('필터 시트 → 보기 조건', () {
    test('띠 안 단과 밀도는 보기 조건으로 간다', () {
      const state = FilterState(density: 1);
      final conditions = state.withShowing('leaders', false).toConditions();
      expect(conditions.density, 1);
      expect(conditions.leaders, isFalse);
    });

    test('조감 모양과 `축소하면 조감`도 보기 조건으로 간다', () {
      const state = FilterState(birdShape: 'c', birdAuto: true, density: 2);
      final conditions = state.toConditions();
      expect(conditions.birdShape, BirdShape.c);
      // `축소하면 조감`은 보기 조건이 아니라(그쪽의 autoBird는 '지금 걸려 있는가') 장면의 자동 조감 스위치로 간다.
      expect(conditions.autoBird, isFalse);
      final (bus, bridge, _) = build();
      glueOf(bus, bridge);
      bus.slot(slotFilters).value = const FilterState(birdAuto: true);
      expect(bus.scene.autoBird.$1, isTrue);
      bus.slot(slotFilters).value = const FilterState();
      expect(bus.scene.autoBird.$1, isFalse);
    });

    test('메아리 스위치는 필터 시트와 창이 한 값이다', () {
      final (bus, bridge, _) = build();
      glueOf(bus, bridge);
      bus.slot(slotFilters).value = const FilterState().withShowing('spotEcho', true);
      expect(bus.slot(slotEcho).value, isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  //  6. 검색 — 고르면 무엇이 실리는가
  // ────────────────────────────────────────────────────────────────────────

  group('검색', () {
    test('날짜 줄을 고르면 같은 해 보기 · 기준선 · 가기가 한 번에 실린다', () async {
      final (bus, bridge, _) = build();
      glueOf(bus, bridge);
      final search = SearchController(bus: bus);
      addTearDown(search.dispose);

      await search.setQuery('1592년');
      expect(search.hits.first.kind, 'date');
      search.activate(0);

      final request = YearRequest.of(bus.slot(yearSlot).value);
      expect(request, isNotNull, reason: '같은 해 보기 창이 열릴 부탁이 실린다');
      expect(bus.slot(markerSlot).value, isNotNull, reason: '기준선이 놓인다');
      expect(bridge.gone, isNotEmpty, reason: '창이 먼저 열리고 그다음에 옮긴다');
    });

    test('항목 줄을 고르면 그 항목을 고르고 도착 고리를 부탁한다', () async {
      final (bus, bridge, data) = build();
      glueOf(bus, bridge);
      data.hits = [
        {'kind': 'period', 'uid': '별여울/유리항', 'name': '유리항', 'start': 1000, 'end': 2000, 'row': 1},
      ];
      final search = SearchController(bus: bus);
      addTearDown(search.dispose);

      await search.setQuery('유리항');
      search.activate(0);
      expect(bus.selection.value?.uid, '별여울/유리항');
      await Future<void>.delayed(Duration.zero);
      expect(bridge.gone.last.ring, '별여울/유리항');
      expect(bridge.gone.last.row, 1);
    });

    test('하위 문서 줄은 창들과 같은 문서 슬롯에 실린다', () async {
      final (bus, bridge, data) = build();
      glueOf(bus, bridge);
      data.hits = [
        {'kind': 'doc', 'uid': '별여울/문서/유리항', 'name': '유리항 문서', 'start': 0, 'end': 0},
      ];
      final search = SearchController(bus: bus);
      addTearDown(search.dispose);

      await search.setQuery('유리항');
      search.activate(0);
      expect(bus.slot(slotDoc).value, '별여울/문서/유리항');
    });

    test('검색이 필터의 거르개를 계약 2-2의 꼴로 싣는다', () async {
      final (bus, bridge, data) = build();
      glueOf(bus, bridge);
      bus.slot(slotFilters).value = const FilterState(tracksOff: {'3'});
      final search = SearchController(bus: bus);
      addTearDown(search.dispose);

      await search.setQuery('유리항');
      final query = data.lastOf('search');
      expect(query?['filter'], isA<Map<String, dynamic>>());
      expect((query!['filter']! as Map)['tracks_off'], [3]);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  //  7. 묶음 카드 — 머리(순수)는 이어져 있다. 손 올리기를 실제로 부르는 곳이 없는 것은 보고서 2번.
  // ────────────────────────────────────────────────────────────────────────

  group('묶음 카드', () {
    test('손을 올리면 카드가 열리고, 벗어나면 닫힌다', () async {
      final (bus, _, _) = build();
      final cards = ClusterCardController(bus: bus);
      addTearDown(cards.dispose);
      const span = ClusterSpan(key: '1@0~10', row: 1, lo: 0, hi: 10, count: 3);

      cards.hover(span, anchor: const Rect.fromLTWH(10, 20, 28, 18));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(cards.cluster, span);

      cards.hover(null);
      await Future<void>.delayed(const Duration(milliseconds: 320));
      expect(cards.cluster, isNull);
    });

    test('묶인 폭이 넓은 알약은 누르면 카드가 아니라 그 구간 확대다', () {
      final (bus, bridge, _) = build();
      glueOf(bus, bridge);
      final cards = ClusterCardController(bus: bus);
      addTearDown(cards.dispose);
      const wide = ClusterSpan(key: '1@0~99999999', row: 1, lo: 0, hi: 99999999, count: 40);
      expect(wide.canZoom, isTrue);

      cards.press(wide, anchor: Rect.zero);
      expect(cards.cluster, isNull);
      expect(bus.go.value, isNotNull);
    });
  });
}

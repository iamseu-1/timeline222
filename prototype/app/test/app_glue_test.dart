import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/emphasis.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_glue.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/context_menu.dart';
import 'package:archive_prototype/ui/detail_echo.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/filter_state.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 이어 붙이기(lib/ui/app_glue.dart)의 검사. 장면 · 조종부는 가짜 다리로 바꿔 두고, 자료 처리부도 가짜다 —
// 확인하는 것: 명령마다 무엇이 불리는가 · 강조의 임자 · 답의 배열 감싸기 · 조건이 바뀌면 줄을 다시 쌓는가 ·
// 측정 모드(기억을 붙이지 않았을 때)에 기억 파일을 건드리지 않는가.

/// 무엇이 불렸는지만 적어 두는 다리.
class FakeBridge implements SceneBridge {
  final gone = <GoRequest>[];
  final insets = <double>[];
  final looks = <Look>[];
  final folds = <bool>[];
  final probed = <Offset>[];

  /// `foldAll`이 되었다고 답할 것인가.
  bool canFold = true;

  @override
  void go(GoRequest request, {double insetRight = 0}) {
    gone.add(request);
    insets.add(insetRight);
  }

  @override
  void emphasize(Look look) => looks.add(look);

  @override
  Future<MenuSpot> probe(Offset local) async {
    probed.add(local);
    return const MenuSpot();
  }

  @override
  bool foldAll(bool folded) {
    folds.add(folded);
    return canFold;
  }
}

/// 가짜 자료 처리부: 물은 것을 적어 두고 `ids_of` · `id_of`에만 답한다.
class FakeData {
  final asked = <Map<String, dynamic>>[];

  /// uid → (띠 번호, 줄, 시작, 끝).
  final places = <String, (int, int, double, double)>{};

  /// 사건의 uid → 사건 번호.
  final events = <String, int>{};

  /// `ids_of`를 모르는 자료 처리부 흉내.
  bool knowsIdsOf = true;

  Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async {
    asked.add(query);
    switch (query['op']) {
      case 'ids_of':
        if (!knowsIdsOf) throw StateError('모르는 명령입니다 — ids_of');
        final uids = (query['uids'] as List).cast<String>();
        return {
          'bands': [
            for (final uid in uids)
              if (places[uid] != null) {'uid': uid, 'id': places[uid]!.$1, 'row': places[uid]!.$2, 'start': places[uid]!.$3, 'end': places[uid]!.$4},
          ],
          'events': [
            for (final uid in uids)
              if (events[uid] != null) {'uid': uid, 'id': events[uid]},
          ],
        };
      case 'id_of':
        final one = places[query['uid']];
        if (one == null) return const {};
        return {'band': one.$1, 'row': one.$2, 'start': one.$3, 'end': one.$4};
      default:
        return const {};
    }
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
      ..resize(1920, 500)
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

  /// 가짜 장면 하나로 길 · 다리 · 이어 붙이기를 세운다.
  (AppBus, FakeBridge, FakeData) build() {
    final scene = makeScene();
    addTearDown(scene.dispose);
    addTearDown(scene.controller.dispose);
    final data = FakeData();
    final bus = AppBus(ask: (query) async => wrapAnswer(await data.ask(query)), controller: scene.controller, scene: scene);
    addTearDown(bus.dispose);
    return (bus, FakeBridge(), data);
  }

  group('명령 나누기', () {
    test('단축키 · 메뉴의 명령마다 맡은 것이 불린다', () async {
      final (bus, bridge, data) = build();
      final done = <String>[];
      final glue = AppGlue(
        bus: bus,
        bridge: bridge,
        onFilter: () => done.add('filter'),
        onTable: () => done.add('table'),
        onImage: () => done.add('image'),
        onPacks: () => done.add('dlc'),
        onSearchFocus: () => done.add('search'),
        onSearchClose: () => done.add('search.close'),
        onClose: () => done.add('close'),
      )..start();
      addTearDown(glue.dispose);

      runCommand(bus, Cmd.filter);
      runCommand(bus, Cmd.table);
      runCommand(bus, Cmd.image);
      runCommand(bus, Cmd.dlc);
      runCommand(bus, Cmd.search);
      runCommand(bus, Cmd.searchClose);
      runCommand(bus, Cmd.close);
      expect(done, ['filter', 'table', 'image', 'dlc', 'search', 'search.close', 'close']);

      // ⤢ 전체 보기는 조종부를 부른다.
      bus.controller.showRange(0, 1000000);
      runCommand(bus, Cmd.fit);
      expect(bus.controller.view.span, closeTo(bus.controller.maxSpan, 1));

      // ↕ 조감은 밀도를 2로, 한 번 더 누르면 직전 밀도로.
      runCommand(bus, Cmd.bird);
      expect(bus.conditions.value.density, 2);
      runCommand(bus, Cmd.bird);
      expect(bus.conditions.value.density, 0);

      // ▾ 모든 트랙 접기: 다리에 시키고 된 만큼을 슬롯에 되적는다.
      runCommand(bus, Cmd.foldAll);
      expect(bridge.folds, [true]);
      expect(bus.slot(slotFoldAll).value, isTrue);
      runCommand(bus, Cmd.foldAll);
      expect(bridge.folds, [true, false]);
      expect(bus.slot(slotFoldAll).value, isFalse);

      // 자세히 보기는 그 항목을 고른다.
      runCommand(bus, Cmd.detail, uid: '별여울/유리항');
      expect(bus.selection.value?.uid, '별여울/유리항');

      // 🎯 여기로 확대는 자리를 물어 데려간다(기간 × 2.2).
      data.places['별여울/유리항'] = (100, 3, 1000, 2000);
      runCommand(bus, Cmd.focusOn, uid: '별여울/유리항');
      await Future<void>.delayed(Duration.zero);
      expect(bus.go.value, isNotNull);
      expect(bus.go.value!.hi - bus.go.value!.lo, closeTo(1000 * 2.2, .001));
      expect(bus.go.value!.row, 3);
      expect(bus.go.value!.ring, '별여울/유리항');
    });

    test('그 부품이 스스로 듣는 명령과 모르는 명령은 조용히 넘어간다', () {
      final (bus, bridge, _) = build();
      final done = <String>[];
      final glue = AppGlue(bus: bus, bridge: bridge, onFilter: () => done.add('filter'), onClose: () => done.add('close'))..start();
      addTearDown(glue.dispose);
      for (final name in [Cmd.year, Cmd.legend, Cmd.measure, Cmd.wiki, Cmd.motion, Cmd.succession, '모르는 명령']) {
        runCommand(bus, name);
      }
      expect(done, isEmpty);
      expect(bridge.folds, isEmpty);
    });

    test('가기는 창이 가린 폭을 함께 넘긴다', () async {
      final (bus, bridge, _) = build();
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);

      bus.goTo(0, 100);
      expect(bridge.insets.last, 0);

      // 상세 창이 열리면 그 폭(392)만큼 비켜 간다.
      bus.slot(slotDetail).value = const DetailState(uid: 'u', kind: 'event', branch: DetailKind('item'), fresh: true, inset: 392);
      bus.goTo(0, 100);
      expect(bridge.insets.last, 392);
    });
  });

  group('강조의 임자', () {
    test('나중에 건 쪽이 이기고, 물러나면 다른 쪽이 되살아난다', () {
      final owner = HighlightOwner();
      expect(owner.owner, HiOwner.none);
      expect(owner.uids, isNull);

      owner.setSearch(['가', '나']);
      expect(owner.owner, HiOwner.search);
      expect(owner.uids, ['가', '나']);

      // 창을 열면 창이 이긴다.
      owner.setWindow(['다']);
      expect(owner.owner, HiOwner.window);
      expect(owner.uids, ['다']);

      // 창을 닫으면 검색 강조가 되살아난다.
      owner.releaseWindow();
      expect(owner.owner, HiOwner.search);
      expect(owner.uids, ['가', '나']);

      // 검색어를 비우면 아무 강조도 없다.
      owner.setSearch(null);
      expect(owner.owner, HiOwner.none);
      expect(owner.uids, isNull);

      // 빈 목록은 '없음'과 같다.
      owner.setSearch(const []);
      expect(owner.owner, HiOwner.none);
    });

    test('조명을 거는 창은 걸 것이 없어도 임자가 된다 · 값만 고칠 때는 가로채지 않는다', () {
      final owner = HighlightOwner();
      owner.setSearch(['가']);

      // 왕조 창을 메아리를 끈 채 열면 — 지금 연표처럼 검색 강조가 걷히고 아무것도 강조되지 않는다.
      owner.setWindow(null);
      expect(owner.owner, HiOwner.window);
      expect(owner.uids, isNull);

      // 메아리를 켜면(값만 고침) 창이 가진 강조가 산다.
      owner.setWindow(['창', '사건'], claim: false);
      expect(owner.owner, HiOwner.window);
      expect(owner.uids, ['창', '사건']);

      // 창이 열린 뒤에 검색어를 고치면 검색이 이기고, 늦게 온 메아리의 답은 임자를 되찾지 않는다.
      owner.setSearch(['나']);
      owner.setWindow(['창', '사건', '또 하나'], claim: false);
      expect(owner.owner, HiOwner.search);
      expect(owner.uids, ['나']);

      // 검색어를 비우면 창의 강조가 그대로 되살아난다.
      owner.setSearch(null);
      expect(owner.owner, HiOwner.window);
      expect(owner.uids, ['창', '사건', '또 하나']);
    });

    test('창이 열리면 창의 uid가, 닫히면 검색의 uid가 밝기로 간다', () async {
      final (bus, bridge, data) = build();
      data.places
        ..['검색/하나'] = (11, 0, 0, 10)
        ..['창/하나'] = (22, 1, 0, 10);
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);

      bus.slot(slotSearchHits).value = ['검색/하나'];
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.bands, {11});

      bus.slot(slotDetail).value = const DetailState(uid: '창/하나', kind: 'period', branch: DetailKind('cell', spot: true, always: true), fresh: true, inset: 392);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.bands, {22});

      bus.slot(slotDetail).value = const DetailState.closed();
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.bands, {11}, reason: '창을 닫으면 검색 강조가 되살아난다');
    });

    test('ids_of를 모르면 id_of를 하나씩 묻는다', () async {
      final (bus, bridge, data) = build();
      data.knowsIdsOf = false;
      data.places['검색/하나'] = (11, 0, 0, 10);
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);

      bus.slot(slotSearchHits).value = ['검색/하나'];
      await Future<void>.delayed(Duration.zero);
      expect(data.asked.where((q) => q['op'] == 'id_of').length, 1);
      expect(bridge.looks.last.bands, {11});
    });
  });

  group('같은 시기 타국(메아리)', () {
    /// 창 하나를 연다.
    void openWindow(AppBus bus, String uid, DetailKind branch) {
      bus.slot(slotDetail).value = DetailState(uid: uid, kind: 'period', branch: branch, fresh: true, inset: 392);
    }

    test('칸 창은 메아리를 꺼도 제 조명에 든 사건을 강조한다', () async {
      final (bus, bridge, data) = build();
      data.places['창/칸'] = (22, 1, 0, 10);
      data.events['사건/하나'] = 501;
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);

      openWindow(bus, '창/칸', const DetailKind('cell', spot: true, always: true));
      bus.slot(slotEchoHits).value = const EchoHits(ownUids: ['사건/하나'], echoIds: [7]);
      await Future<void>.delayed(Duration.zero);

      final look = bridge.looks.last;
      expect(look.bands, {22});
      expect(look.events, {501}, reason: '창이 고른 것 + ownUids가 강조에 든다');
      expect(look.layout, isTrue, reason: '칸 창의 강조는 사건 배치에도 쓴다');
      expect(look.lit, isFalse);
      expect(look.echo, isNull, reason: '메아리를 끄면 타국의 사건을 밝히지 않는다');
    });

    test('왕조 창은 메아리를 켰을 때만 강조하고, 그 강조를 사건 배치에 쓰지 않는다', () async {
      final (bus, bridge, data) = build();
      data.places['창/왕조'] = (33, 2, 0, 10);
      data.events['사건/하나'] = 501;
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);

      openWindow(bus, '창/왕조', const DetailKind('dynasty'));
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.bands, isNull, reason: '메아리를 끄면 왕조 창은 강조를 걸지 않는다');

      bus.slot(slotEchoHits).value = const EchoHits(ownUids: ['사건/하나'], echoIds: [7, 9]);
      bus.slot(slotEcho).value = true;
      await Future<void>.delayed(Duration.zero);

      final look = bridge.looks.last;
      expect(look.bands, {33});
      expect(look.events, {501});
      expect(look.echo, {7, 9});
      expect(look.lit, isTrue, reason: '흐린 띠 안의 조명 구간을 흐리지 않는다');
      expect(look.layout, isFalse, reason: '명세 9 ㈐-2 — 켜고 끌 때 이름표가 바뀌지 않게');
    });

    test('조명을 걸지 않는 창은 검색 강조를 빼앗지 않는다', () async {
      final (bus, bridge, data) = build();
      data.places['검색/하나'] = (11, 0, 0, 10);
      data.places['창/사건'] = (44, 1, 0, 10);
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);

      bus.slot(slotSearchHits).value = ['검색/하나'];
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.bands, {11});

      openWindow(bus, '창/사건', const DetailKind('item'));
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.bands, {11}, reason: '기본 상세는 조명을 걸지 않는다(js의 spotKind가 없는 창)');
    });

    test('필터 시트의 체크와 창의 스위치는 한 값이다', () {
      final (bus, bridge, _) = build();
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);
      expect(glue.echoOn, isFalse);

      bus.slot(slotFilters).value = const FilterState().withShowing('spotEcho', true);
      expect(bus.slot(slotEcho).value, isTrue);
      expect(glue.echoOn, isTrue);

      bus.slot(slotFilters).value = const FilterState().withShowing('spotEcho', false);
      expect(bus.slot(slotEcho).value, isFalse);
      expect(glue.echoOn, isFalse);
    });

    test('창이 바뀌면 앞 창이 셈해 둔 메아리는 버린다', () {
      final (bus, bridge, data) = build();
      data.places['창/칸'] = (22, 1, 0, 10);
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);

      openWindow(bus, '창/칸', const DetailKind('cell', spot: true, always: true));
      bus.slot(slotEchoHits).value = const EchoHits(ownUids: ['사건/하나']);
      openWindow(bus, '창/딴것', const DetailKind('cell', spot: true, always: true));
      expect(bus.slot(slotEchoHits).value, isNull);
    });
  });

  group('같은 사람의 칸(건의 8의 6-나)', () {
    test('칸 창이 실은 자리들이 띠 번호 열쇠로 강조에 실린다 — 띠를 모르는 자리는 빼고, 혼자면 싣지 않는다', () async {
      final (bus, bridge, data) = build();
      data.places['가상/가람'] = (31, 0, 0, 10);
      data.places['가상/포구'] = (32, 1, 0, 10);
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);

      bus.slot(slotTwins).value = [
        {'uid': '가상/가람', 'cell': 'leader:3'},
        {'uid': '가상/포구', 'cell': 'leader:1'},
      ];
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.twins, {'31|leader:3', '32|leader:1'});
      expect(bridge.looks.last.isTwin(32, 'leader:1'), isTrue);
      expect(bridge.looks.last.twinBands, {31, 32}, reason: '같은 사람이 앉은 나라는 흐리지 않는다');
      expect(bridge.looks.last.isTwin(32, 'leader:0'), isFalse);

      bus.slot(slotTwins).value = [
        {'uid': '가상/가람', 'cell': 'leader:3'},
        {'uid': '가상/없음', 'cell': 'leader:0'},
      ];
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.twins, isNull);

      bus.slot(slotTwins).value = null;
      await Future<void>.delayed(Duration.zero);
      expect(bridge.looks.last.twins, isNull);
    });

    test('나라 기록의 짝 표 — x_persons의 others만 읽는다', () {
      expect(
        twinTableOf({
          'x_persons': {
            'leader:3': {
              'others': [
                {'uid': '가상/포구', 'ref': 'leader:1', 'polity': '포구 나라'},
                {'uid': '', 'ref': 'leader:9'},
              ],
            },
            'leader:0': {'children': []},
          },
        }),
        {
          'leader:3': [('가상/포구', 'leader:1')],
        },
      );
      expect(twinTableOf(null), isEmpty);
      expect(twinTableOf(const {'name': '가람 나라'}), isEmpty);
    });
  });

  group('답 다듬기', () {
    test('배열로 오는 답은 {items: …}로 감싼다', () {
      expect(wrapAnswer([1, 2, 3]), {'items': [1, 2, 3]});
      expect(wrapAnswer({'items': [1]}), {'items': [1]});
      expect(wrapAnswer(null), isEmpty);
      expect(wrapAnswer('무엇'), isEmpty);
    });

    test('ids_of · id_of의 답을 자리표로 읽는다', () {
      final many = readPlaces({
        'bands': [
          {'uid': '가', 'id': 3, 'row': 1, 'start': 10, 'end': 20},
        ],
        'events': [
          {'uid': '나', 'id': 7, 'row': 2, 'start': 30, 'end': 30},
        ],
      });
      expect(many['가']!.band, 3);
      expect(many['나']!.event, 7);
      expect(many['나']!.row, 2);

      final one = readPlaces({'band': 5, 'row': 4, 'start': 1, 'end': 2}, single: '다');
      expect(one['다']!.band, 5);
      expect(one['다']!.start, 1);
      expect(readPlaces(const {}, single: '라'), isEmpty);
    });
  });

  test('보기 조건이 바뀌면 줄을 다시 쌓는다', () {
    final (bus, bridge, _) = build();
    final glue = AppGlue(bus: bus, bridge: bridge)..start();
    addTearDown(glue.dispose);
    final layout = bus.scene.layout;

    bus.conditions.value = const ViewConditions(density: 2, leaders: false);
    // 이어 붙이기가 이미 넣었으면 같은 값을 다시 넣어도 바뀌지 않는다.
    expect(layout.setConditions(const ViewConditions(density: 2, leaders: false)), isFalse);
    expect(bus.controller.view.height, greaterThan(0));
  });

  group('기억', () {
    test('기억을 붙이지 않으면(측정 모드) 파일을 읽지도 쓰지도 않는다', () async {
      final folder = await Directory.systemTemp.createTemp('ht-glue-measure-');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/${AppMemory.fileName}');

      final (bus, bridge, _) = build();
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);
      expect(glue.memory, isNull);

      bus.controller.showRange(0, 1000000);
      bus.slot(slotFilters).value = const FilterState(density: 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(file.existsSync(), isFalse, reason: '재는 동안에는 기억을 건드리지 않는다');
    });

    test('기억을 붙이면 보기와 필터가 파일로 간다', () async {
      final folder = await Directory.systemTemp.createTemp('ht-glue-memory-');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/${AppMemory.fileName}');

      final (bus, bridge, _) = build();
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);
      final memory = await AppMemory.open(folder: folder, delay: const Duration(milliseconds: 1));
      glue.attachMemory(memory);
      expect(glue.memory, same(memory));

      bus.slot(slotFilters).value = const FilterState(density: 1, filterOpen: true);
      bus.controller.showRange(1000, 2000);
      await memory.flush();
      expect(file.existsSync(), isTrue);
      expect(memory.parts['filters']?['density'], 1);
      expect(memory.ui.filterOpen, isTrue);
      expect(memory.view, isNotNull);
    });

    test('기억에 담긴 필터가 보기 조건으로 간다', () async {
      final folder = await Directory.systemTemp.createTemp('ht-glue-load-');
      addTearDown(() => folder.delete(recursive: true));

      final (bus, bridge, _) = build();
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      addTearDown(glue.dispose);
      final memory = await AppMemory.open(folder: folder, delay: const Duration(milliseconds: 1));
      // 붙이는 순간 기억한 필터가 보기 조건으로 가면서 모아 쓰기가 하나 미뤄진다 — 닫고 그 쓰기가 끝난 뒤에 폴더를 치운다
      // (그냥 두면 검사가 끝난 뒤에 쓰여, 지운 폴더가 다시 생기거나 폴더 지우기와 겹쳐 '다른 프로세스가 파일을 사용 중'으로 걸린다).
      addTearDown(() async {
        memory.dispose();
        await memory.written;
      });
      memory.parts['filters'] = const FilterState(density: 1).withShowing('leaders', false).toJson();
      glue.attachMemory(memory);

      expect(glue.filters.density, 1);
      expect(bus.conditions.value.density, 1);
      expect(bus.conditions.value.leaders, isFalse);
    });

    test('필터 값이 없는 기억으로 시트를 처음 열면 지금 보기 조건에서 시작한 값을 적는다 — 다음 실행에도 조감 · 끈 단이 남는다(0.1.1)', () async {
      final folder = await Directory.systemTemp.createTemp('ht-glue-seed-');
      addTearDown(() => folder.delete(recursive: true));

      // 옛 기억(필터 칸 없음): V · ↕로 조감에 들었고(그 전 밀도 '빽빽하게') 지도자 단을 껐다 — 보기 조건은 기억(bindConditions)이 넣는다.
      final memory = await AppMemory.open(folder: folder, delay: const Duration(milliseconds: 1));
      memory.ui
        ..density = 2
        ..birdFrom = 1
        ..show['leaders'] = false;
      final (bus, bridge, _) = build();
      final glue = AppGlue(bus: bus, bridge: bridge)..start();
      glue.attachMemory(memory);
      expect(memory.parts['filters'], isNull);
      expect([bus.conditions.value.density, bus.conditions.value.leaders], [2, false]);
      // 아직 슬롯에 값이 없어도 읽는 값은 지금 보기 조건(예전에는 기본값 — 메뉴 ✓도 그것을 읽었다).
      expect([glue.filters.density, glue.filters.birdFrom, glue.filters.showing('leaders')], [2, 1, false]);

      // 시트를 연다(앱 틀 → setFilterOpen): 슬롯에 처음 적는 값 — 예전에는 기본값(밀도 0 · 단 모두 켬)이 기억에 남았다.
      glue.setFilterOpen(true);
      expect([bus.conditions.value.density, bus.conditions.value.leaders], [2, false], reason: '시트를 연 것만으로 보기 조건이 바뀌지 않는다');
      await memory.flush();
      expect([memory.parts['filters']?['density'], memory.parts['filters']?['birdFrom'], memory.parts['filters']?['show']?['leaders']], [2, 1, false]);
      glue.dispose();
      memory.dispose();
      await memory.written;

      // 다음 실행: 기억의 필터 값이 보기 조건을 덮어도(attachMemory) 조감 · 끈 단 그대로.
      final again = await AppMemory.open(folder: folder, delay: const Duration(milliseconds: 1));
      final (bus2, bridge2, _) = build();
      final glue2 = AppGlue(bus: bus2, bridge: bridge2)..start();
      addTearDown(() async {
        glue2.dispose();
        again.dispose();
        await again.written;
      });
      glue2.attachMemory(again);
      expect([bus2.conditions.value.density, bus2.conditions.value.leaders], [2, false]);
      expect(glue2.filters.filterOpen, isTrue);
    });
  });

  test('시트의 여닫기는 필터 값과 한 값이다', () {
    final (bus, bridge, _) = build();
    final glue = AppGlue(bus: bus, bridge: bridge)..start();
    addTearDown(glue.dispose);
    expect(glue.filters.filterOpen, isFalse);
    glue.setFilterOpen(true);
    expect(glue.filters.filterOpen, isTrue);
    expect(glue.menuFlags().filterOpen, isTrue);
  });

  test('보기 폭에 맞는 날짜의 자세함', () {
    const year = 525960.0;
    expect(viewPrecision(100 * year), 0);
    expect(viewPrecision(2 * year), 1);
    expect(viewPrecision(10 * 1440), 2);
    expect(viewPrecision(1440), 3);
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/ui/dlc_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';
import 'support/tile_builder.dart';

// DLC 관리 창(`lib/ui/dlc_manager.dart`) 검사.
//
// 두 갈래로 나눠 둔다:
//   ㈎ 가짜 장면(`support/pack_scene.dart`)으로 스위치 · 찾기 · 모두 켜기/끄기 · 말(모두 `DLC`)을 굳힌다.
//   ㈏ **진짜 자료 처리부(DLL) + 진짜 저장소**(가상 100만 `data/v3b-1m` — DLC 여덟)로
//      "엔진이 준 값이 그대로 카드가 되는가"와 "창이 낸 조합을 엔진이 받아 주는가"를 굳힌다.
//      DLL이나 저장소가 없으면 그 갈래만 건너뛴다.

Future<void> pumpManager(WidgetTester tester, TimelineScene scene, {void Function(Set<int> packs)? onChanged, Size size = const Size(1300, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: DlcManager(scene: scene, onChanged: onChanged))));
}

List<bool> switchValues(WidgetTester tester) => tester.widgetList<DlcSwitch>(find.byType(DlcSwitch)).map((s) => s.value).toList();

Finder switchOf(String name) => find.descendant(of: find.ancestor(of: find.text(name), matching: find.byType(Row)).first, matching: find.byType(DlcSwitch));

void main() {
  group('가짜 장면', () {
    testWidgets('카드는 이름 · 담긴 것을 보이고 스위치로 켜고 끈다', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene);
      expect(find.text('DLC 관리'), findsOneWidget);
      expect(find.text('별여울 기록집'), findsWidgets, reason: '고른 카드의 이름은 자세히에도 선다');
      expect(find.text('사건 1,250건 · 트랙 1개 · 줄 2개'), findsWidgets, reason: '건수는 세 자리마다 쉼표 · 트랙과 줄은 layout의 값');
      expect(find.text('사건 1건 · 트랙 없음'), findsOneWidget, reason: '남의 줄에 사건만 덧붙이는 DLC');
      expect(switchValues(tester), [true, true, true, true]);

      await tester.tap(switchOf('해솔 기록집'));
      await tester.pump();
      expect(scene.layout.isPackEnabled(2), isFalse);
      expect(scene.layout.flowing, isTrue, reason: '켜고 끄기는 흐른다(4단계 1걸음)');
      scene.layout.finishFlow();
      expect(scene.layout.isVisible(2), isFalse, reason: '그 DLC의 줄이 빠진다');
      expect(switchValues(tester), [true, false, true, true]);

      await tester.tap(switchOf('해솔 기록집'));
      await tester.pump();
      expect(scene.layout.enabledPacks, [1, 2, 3, 8]);
    });

    testWidgets('마지막 하나도 끌 수 있다 — 다 끄면 빈 조합을 알린다', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.setPacks({3});
      final calls = <Set<int>>[];
      await pumpManager(tester, scene, onChanged: calls.add);
      expect(switchValues(tester), [false, false, true, false]);

      await tester.tap(switchOf('은빛 나루 기록집'));
      await tester.pump();
      expect(scene.layout.enabledPacks, isEmpty, reason: '2단계의 창은 마지막 하나를 막았다 — 이제 막지 않는다');
      expect(calls, [<int>{}]);
      expect(dlcTimelineEmpty(scene.layout), isTrue, reason: '연표 자리에 안내를 세울 값');
      expect(find.textContaining(dlcEmptyText), findsOneWidget, reason: '창의 아래 줄이 같은 안내를 적는다');

      await tester.tap(switchOf('은빛 나루 기록집'));
      await tester.pump();
      expect(scene.layout.enabledPacks, [3]);
      expect(calls.last, {3});
      expect(dlcTimelineEmpty(scene.layout), isFalse);
    });

    testWidgets('트랙 없는 DLC만 켜 두어도 연표는 빈 것이다', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene);
      await tester.tap(find.text('모두 끄기'));
      await tester.pump();
      await tester.tap(switchOf('덧붙인 기록집'));
      await tester.pump();
      expect(scene.layout.enabledPacks, [8]);
      expect(dlcTimelineEmpty(scene.layout), isTrue, reason: '트랙을 데려오는 DLC가 하나도 없다 — 지금 연표의 `model.tracks.length`와 같은 잣대');
    });

    testWidgets('모두 켜기 · 모두 끄기', (tester) async {
      final (scene, _, _) = makePackScene();
      final calls = <Set<int>>[];
      await pumpManager(tester, scene, onChanged: calls.add);
      await tester.tap(find.text('모두 끄기'));
      await tester.pump();
      expect(scene.layout.enabledPacks, isEmpty);
      expect(switchValues(tester), [false, false, false, false]);
      expect(calls.last, isEmpty);

      await tester.tap(find.text('모두 켜기'));
      await tester.pump();
      expect(scene.layout.enabledPacks, [1, 2, 3, 8]);
      expect(calls.last, {1, 2, 3, 8});
    });

    testWidgets('찾기 — 이름(트랙 이름도)으로 카드를 거른다', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene);
      await tester.enterText(find.byType(TextField), '해솔');
      await tester.pump();
      expect(find.text('해솔 기록집'), findsWidgets);
      expect(find.text('별여울 기록집'), findsNothing);
      expect(switchValues(tester).length, 1, reason: '걸러진 카드만 남는다');

      await tester.enterText(find.byType(TextField), '없는 이름');
      await tester.pump();
      expect(find.text('맞는 DLC가 없습니다.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '별여울 갈래'); // 트랙 이름
      await tester.pump();
      expect(find.text('별여울 기록집'), findsWidgets);
      expect(switchValues(tester).length, 1);
    });

    testWidgets('화면에 보이는 말은 모두 DLC다', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene);
      expect(find.textContaining('자료집'), findsNothing, reason: '지금 연표의 말은 DLC다(코드의 이름 · 측정 구간 이름은 그대로 둔다)');
      expect(find.textContaining('켜 둔 DLC 4개'), findsOneWidget);
      expect(find.textContaining('불러오는 차례: 별여울 기록집 → 해솔 기록집'), findsOneWidget);
    });

    testWidgets('고른 카드의 자세히가 트랙 목록을 적는다', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene);
      expect(find.text('별여울 갈래'), findsWidgets, reason: '처음에는 첫 카드가 골라져 있다(자세히에 트랙 한 줄)');
      await tester.tap(find.text('덧붙인 기록집'));
      await tester.pump();
      expect(find.text('트랙 없음 — 다른 DLC의 줄에 사건만 덧붙입니다.'), findsOneWidget);
    });

    testWidgets('1배 자리 — 지금 연표의 실측(results/dom-dlc13)과 맞댄다', (tester) async {
      final (scene, _, _) = makePackScene();
      // 지금 연표를 1920×1080으로 띄워 뜬 값: 창 1180 · 모눈 760 · 카드 245.33×(표지 137.98) · 자세히 360 · 스위치 40×22.
      // 창의 폭은 min(1180, 화면 − 24)이라 화면을 1204로 두면 같은 1180이 된다.
      await pumpManager(tester, scene, size: const Size(1204, 900));
      expect(tester.getSize(find.byKey(const ValueKey('dlc-card-1'))).width, closeTo(245.33, .01));
      expect(tester.getSize(find.byKey(const Key('dlc-detail'))).width, 360);
      expect(tester.getSize(find.byType(DlcSwitch).first), const Size(42, 24));
      // 표지는 16:9 — 245.33 폭이면 138.0(브라우저의 137.98은 소수 자리 반올림 차이).
      expect(tester.getSize(find.byType(AspectRatio).first).height, closeTo(137.98, .05));
    });

    test('카드 모눈의 칸 수는 css의 auto-fill minmax(220px, 1fr)과 같다', () {
      // 지금 연표의 1배 실측(results/dom-dlc13): 모눈 760px · 3칸 · 칸 폭 245.33px.
      expect(dlcGridColumns(760), 3);
      expect((760 - 12 * 2) / 3, closeTo(245.33, .01));
      expect(dlcGridColumns(1136), 4, reason: '자세히를 접은 폭');
      expect(dlcGridColumns(219), 1);
      expect(dlcGridColumns(232), 1);
      expect(dlcGridColumns(452), 2);
    });
  });

  group('진짜 엔진 · 진짜 저장소(가상 100만 · DLC 여덟)', () {
    final dll = File('../engine/target/release/archive_engine.dll');
    final db = File('../data/v3b-1m/archive.db');
    final ready = dll.existsSync() && db.existsSync();
    const noData = '자료 처리부 DLL 또는 data/v3b-1m 저장소가 없습니다';
    ArchiveEngine? engine;
    Map<String, dynamic>? layoutAnswer;

    setUpAll(() async {
      if (!ready) return;
      engine = ArchiveEngine(libraryPath: dll.absolute.path);
      await engine!.start(db.absolute.path);
      final answer = await engine!.call({'op': 'layout'});
      layoutAnswer = Map<String, dynamic>.from(answer['data'] as Map);
    });

    tearDownAll(() => engine?.close());

    testWidgets('여덟 DLC가 엔진의 답 그대로 카드가 된다', (tester) async {
      if (!ready) return markTestSkipped(noData);
      final layout = SceneLayout.fromJson(layoutAnswer!);
      final packs = [
        for (final p in layoutAnswer!['packs'] as List) Map<String, dynamic>.from(p as Map),
      ];
      expect(packs.length, 8);
      final cards = DlcCardInfo.of(layout);
      expect(cards.length, 8);
      for (int i = 0; i < 8; i++) {
        expect(cards[i].id, packs[i]['id'], reason: '카드의 번호는 엔진이 준 번호');
        expect(cards[i].name, packs[i]['name'], reason: '카드의 이름은 엔진이 준 이름(만들어 넣지 않는다)');
        expect(cards[i].events, (packs[i]['events'] as num).toInt());
      }
      // 여덟째는 트랙 없이 남의 줄에 사건만 덧붙이는 DLC다.
      expect(cards.last.tracks, isEmpty);
      expect(cards.last.contents, '사건 ${formatCount(cards.last.events)}건 · 트랙 없음');
      expect(cards.first.tracks.length, 8);
      expect(cards.first.contents, '사건 125,001건 · 트랙 8개 · 줄 36개');

      final scene = realScene(layout);
      addTearDown(scene.dispose);
      await pumpManager(tester, scene, size: const Size(1600, 1000));
      expect(find.byType(DlcSwitch), findsNWidgets(8));
      for (final card in cards) {
        expect(find.text(card.name), findsWidgets, reason: '여덟 장 모두 제 이름으로 선다');
      }
      expect(find.textContaining('켜 둔 DLC 8개'), findsOneWidget);
      expect(switchValues(tester), List.filled(8, true));
    });

    // 창이 스위치로 실제로 낸 조합. 아래의 검사가 이 조합 그대로 진짜 엔진에 묻는다
    // (위젯 검사 안에서는 진짜 FFI의 답을 기다릴 수 없다 — 가짜 시계가 돌기 때문).
    final made = <String, List<int>>{};

    testWidgets('스위치가 낸 조합 — 여덟 · 일곱 · 빈 목록', (tester) async {
      if (!ready) return markTestSkipped(noData);
      final layout = SceneLayout.fromJson(layoutAnswer!);
      final scene = realScene(layout);
      addTearDown(scene.dispose);
      final calls = <Set<int>>[];
      await pumpManager(tester, scene, onChanged: calls.add, size: const Size(1600, 1000));
      made['all'] = scene.layout.enabledPacks;
      expect(made['all']!.length, 8);

      // ① 첫 DLC를 끈다.
      await tester.tap(switchOf(DlcCardInfo.of(layout).first.name));
      await tester.pump();
      made['without'] = scene.layout.enabledPacks;
      expect(made['without']!.length, 7);
      expect(calls.last.length, 7);

      // ② 모두 끈다 — 막히지 않는다.
      await tester.tap(find.text('모두 끄기'));
      await tester.pump();
      made['none'] = scene.layout.enabledPacks;
      expect(made['none'], isEmpty);
      expect(calls.last, isEmpty);
      expect(dlcTimelineEmpty(scene.layout), isTrue);

      // ③ 다시 모두 켜면 처음 조합으로 돌아온다.
      await tester.tap(find.text('모두 켜기'));
      await tester.pump();
      expect(scene.layout.enabledPacks, made['all']);
    });

    test('그 조합을 진짜 엔진이 그대로 받는다(빈 목록까지)', () async {
      if (!ready) return markTestSkipped(noData);
      expect(made.keys, containsAll(<String>['all', 'without', 'none']), reason: '앞 검사가 스위치로 낸 조합');
      // 단계 12 · 첫 줄 묶음(줄 0~7)은 첫 DLC의 줄이다.
      expect(await bandsOf(engine!, made['all']!), greaterThan(0));
      expect(await bandsOf(engine!, made['without']!), 0, reason: '첫 DLC를 끄면 이 타일의 띠가 통째로 빠진다');
      expect(await bandsOf(engine!, made['none']!), 0, reason: '빈 목록도 거절하지 않고 빈 타일을 준다');
    });
  });
}

/// 진짜 저장소의 배치로 세운 장면. 타일은 이 검사에서 쓰지 않으므로 빈 것을 돌려준다
/// (조합을 엔진에 묻는 길은 [bandsOf]가 따로 굳힌다 — 위젯 검사 안에서 진짜 FFI를 기다리지 않게).
TimelineScene realScene(SceneLayout layout) {
  final controller = TimelineController()
    ..resize(1920, 1000)
    ..setExtent(-1872000000, 314641400)
    ..setContentHeight(layout.totalHeight);
  return TimelineScene(
    controller: controller,
    layout: layout,
    fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
}

/// 그 조합으로 진짜 엔진에 타일 하나를 물어 띠의 수를 센다(가상 100만의 첫 줄 묶음 · 단계 12).
Future<int> bandsOf(ArchiveEngine engine, List<int> packs) async {
  final Uint8List bytes = await engine.tile(12, -1, 0, packs);
  if (bytes.isEmpty) return 0;
  return Tile.decode(bytes).bandCount;
}

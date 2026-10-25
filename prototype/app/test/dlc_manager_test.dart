import 'dart:io';
import 'dart:typed_data';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/shell/sheet_look.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:archive_prototype/ui/dlc_add.dart';
import 'package:archive_prototype/ui/dlc_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pack_scene.dart';
import 'support/tile_builder.dart';

// DLC 관리 창(`lib/ui/dlc_manager.dart`) 검사.
//
// 두 갈래로 나눠 둔다:
//   ㈎ 가짜 장면(`support/pack_scene.dart`)으로 끄기 · 켜기 · 찾기 · 모두 켜기/끄기 · 말(모두 `DLC`)과 서고 꼴(리메이크 4단계 과제 9 걸음 1 —
//      다듬기 판 sm-dlc: 폴더 'DLC 관리 {수}' · 켠 DLC = 불러오는 차례대로 실에 꿴 줄 · 보관함 = 흰 종이 + 먹 25 실선 · 얹은 트랙만 점선 ·
//      고른 테 1.5 · 줄 끝의 끄기 · 켜기 · 삭제)을 굳힌다.
//   ㈏ **진짜 자료 처리부(DLL) + 진짜 저장소**(가상 100만 `data/v3b-1m` — DLC 여덟)로
//      "엔진이 준 값이 그대로 줄이 되는가"와 "창이 낸 조합을 엔진이 받아 주는가"를 굳힌다.
//      DLL이나 저장소가 없으면 그 갈래만 건너뛴다.

Future<void> pumpManager(
  WidgetTester tester,
  TimelineScene scene, {
  void Function(Set<int> packs)? onChanged,
  Size size = const Size(1300, 900),
  DlcJob? job,
  Future<void> Function(DlcCardInfo card)? onRemove,
  Future<void> Function(List<DlcCardInfo> cards, bool on)? onToggle,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: DlcManager(scene: scene, onChanged: onChanged, job: job, onRemove: onRemove, onToggle: onToggle))));
}

/// 줄마다 켜졌는가(이름 → 켬).
Map<String, bool> states(WidgetTester tester) => {for (final r in tester.widgetList<DlcRow>(find.byType(DlcRow))) r.card.name: r.on};

List<bool> switchValues(WidgetTester tester) => tester.widgetList<DlcSwitch>(find.byType(DlcSwitch)).map((s) => s.value).toList();

Finder rowOf(int id) => find.byKey(ValueKey('dlc-card-$id'));

/// 그 이름의 줄의 끄기 · 켜기 단추(자세히의 이름은 줄 밖이라 걸리지 않는다).
Finder switchOf(String name) => find.descendant(of: find.ancestor(of: find.text(name), matching: find.byType(DlcRow)).first, matching: find.byType(DlcSwitch));

/// 줄이 든 상자의 이름(뚜껑의 흰 라벨).
String boxOf(WidgetTester tester, int id) => tester.widget<SheetBox>(find.ancestor(of: rowOf(id), matching: find.byType(SheetBox)).first).label;

/// 줄 꼬리표(줄의 맨 바깥 꼬리표)의 꼴.
SheetShape rowShape(WidgetTester tester, int id) => tester.widget<SheetTag>(find.descendant(of: rowOf(id), matching: find.byType(SheetTag)).first).shape;

/// 줄의 작은 트랙 꼬리표(키 14)의 꼴 — 줄에 선 차례대로.
List<SheetShape> miniShapes(WidgetTester tester, int id) => [
  for (final t in tester.widgetList<SheetTag>(find.descendant(of: rowOf(id), matching: find.byType(SheetTag))))
    if (t.height == SheetLook.dlcMini) t.shape,
];

/// 남의 트랙에 얹은 DLC가 든 뼈대(제 트랙 · 얹은 트랙 · 트랙 없음).
SceneLayout sharedLayout() => SceneLayout.fromJson({
  'packs': [
    {'id': 1, 'name': '별여울 기록집', 'events': 214, 'key': 'east-asia-base', 'periods': 84},
    {'id': 2, 'name': '동방의 기록집', 'events': 3, 'key': 'tigers', 'periods': 52, 'touches': [1]},
    {'id': 3, 'name': '해솔 기록집', 'events': 2, 'key': 'haesol', 'touches': [1]},
  ],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'key': 'starbrook', 'color': 0x9ab0c0, 'rows': [packRow(0), packRow(1)]},
    {'id': 2, 'pack': 2, 'ord': 1, 'name': '동방 갈래', 'key': 'east', 'color': 0xd8a0a0, 'rows': [packRow(2)]},
    {'id': 3, 'pack': 3, 'ord': 2, 'name': '해솔 갈래', 'key': 'haesol', 'color': 0xa0c8a0, 'rows': [packRow(3), packRow(4), packRow(5)]},
  ],
  'epochs': [],
});

void main() {
  group('가짜 장면', () {
    testWidgets('폴더 DLC 관리 {수} · 줄은 이름 · 담긴 것을 보이고 끄기 · 켜기로 켜고 끈다 — 끈 줄은 보관함으로 내려간다', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene);
      final folder = tester.widget<SheetFolder>(find.byType(SheetFolder));
      expect((folder.label, folder.count), ('DLC 관리', '4'), reason: '폴더 탭은 맨 글 + DLC 수');
      expect(find.text('DLC 관리'), findsOneWidget);
      expect(find.text('별여울 기록집'), findsWidgets, reason: '고른 줄의 이름은 자세히에도 선다');
      expect(find.text('사건 1,250건 · 트랙 1개 · 줄 2개'), findsWidgets, reason: '건수는 세 자리마다 쉼표 · 트랙과 줄은 layout의 값');
      expect(find.text('사건 1건 · 트랙 없음'), findsOneWidget, reason: '남의 줄에 사건만 덧붙이는 DLC');
      expect(switchValues(tester), [true, true, true, true]);
      expect(find.text('끄기'), findsNWidgets(4), reason: '켠 줄의 단추는 끄기');
      expect(find.text('보관함 · 꺼 둔 DLC'), findsNothing, reason: '꺼 둔 DLC가 없으면 보관함 상자는 서지 않는다');

      await tester.tap(switchOf('해솔 기록집'));
      await tester.pump();
      expect(scene.layout.isPackEnabled(2), isFalse);
      expect(scene.layout.flowing, isTrue, reason: '켜고 끄기는 흐른다(4단계 1걸음)');
      scene.layout.finishFlow();
      expect(scene.layout.isVisible(2), isFalse, reason: '그 DLC의 줄이 빠진다');
      expect(states(tester), {'별여울 기록집': true, '은빛 나루 기록집': true, '덧붙인 기록집': true, '해솔 기록집': false}, reason: '켠 줄 다음 보관함 줄');
      expect(boxOf(tester, 2), '보관함 · 꺼 둔 DLC');
      expect(boxOf(tester, 1), '켠 DLC');
      expect(find.descendant(of: rowOf(2), matching: find.text('켜기')), findsOneWidget, reason: '보관함 줄의 단추는 켜기');

      await tester.tap(switchOf('해솔 기록집'));
      await tester.pump();
      expect(scene.layout.enabledPacks, [1, 2, 3, 8]);
      expect(boxOf(tester, 2), '켠 DLC');
    });

    testWidgets('마지막 하나도 끌 수 있다 — 다 끄면 빈 조합을 알린다', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.setPacks({3});
      final calls = <Set<int>>[];
      await pumpManager(tester, scene, onChanged: calls.add);
      expect(states(tester), {'은빛 나루 기록집': true, '별여울 기록집': false, '해솔 기록집': false, '덧붙인 기록집': false});

      await tester.tap(switchOf('은빛 나루 기록집'));
      await tester.pump();
      expect(scene.layout.enabledPacks, isEmpty, reason: '2단계의 창은 마지막 하나를 막았다 — 이제 막지 않는다');
      expect(calls, [<int>{}]);
      expect(dlcTimelineEmpty(scene.layout), isTrue, reason: '연표 자리에 안내를 세울 값');
      expect(find.textContaining(dlcEmptyText), findsOneWidget, reason: '창의 아래 줄이 같은 안내를 적는다');
      expect(find.text('켠 DLC가 없습니다.'), findsOneWidget, reason: '켠 DLC 상자는 비어도 선다');

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
      expect(find.text('켜기'), findsNWidgets(4));

      await tester.tap(find.text('모두 켜기'));
      await tester.pump();
      expect(scene.layout.enabledPacks, [1, 2, 3, 8]);
      expect(calls.last, {1, 2, 3, 8});
    });

    testWidgets('찾기 — 이름(트랙 이름도)으로 줄을 거른다', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene);
      await tester.enterText(find.byType(TextField), '해솔');
      await tester.pump();
      expect(find.text('해솔 기록집'), findsWidgets);
      expect(find.text('별여울 기록집'), findsNothing);
      expect(switchValues(tester).length, 1, reason: '걸러진 줄만 남는다');
      expect(find.descendant(of: rowOf(2), matching: find.text('2')), findsOneWidget, reason: '걸러도 차례 번호는 불러오는 차례 그대로');

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

    testWidgets('고른 줄의 자세히가 트랙 목록을 적는다', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene);
      expect(find.text('별여울 갈래'), findsWidgets, reason: '처음에는 첫 줄이 골라져 있다(자세히에 트랙 한 줄)');
      expect(find.text('번호 1'), findsOneWidget, reason: '자세히 맨 아래 번호(글자 id 없는 옛 뼈대)');
      await tester.tap(find.text('덧붙인 기록집'));
      await tester.pump();
      expect(find.text('트랙 없음 — 다른 DLC의 줄에 사건만 덧붙입니다.'), findsOneWidget);
    });

    testWidgets('켠 줄의 차례 = 불러오는 차례 — 실에 꿰고 번호를 단다 · 보관함 줄은 실에서 내려 번호가 없다', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.setPacks({1, 3, 8});
      await pumpManager(tester, scene);
      expect(find.textContaining('불러오는 차례: 별여울 기록집 → 은빛 나루 기록집 → 덧붙인 기록집'), findsOneWidget);
      // 켠 DLC 상자의 실 기둥이 꿴 줄 — 위에서 아래로 불러오는 차례대로, 번호 1 · 2 · 3.
      final thread = find.byType(SheetThreadColumn);
      expect(thread, findsOneWidget, reason: '실은 켠 DLC 상자에만(보관함은 실에서 내림)');
      final threaded = [for (final r in tester.widgetList<DlcRow>(find.descendant(of: thread, matching: find.byType(DlcRow)))) r.card.id];
      expect(threaded, [1, 3, 8]);
      final tops = [for (final id in threaded) tester.getRect(rowOf(id)).top];
      expect(tops, orderedEquals([...tops]..sort()));
      expect([for (final id in threaded) tester.widget<DlcRow>(rowOf(id)).order], [1, 2, 3]);
      for (final (i, id) in threaded.indexed) {
        expect(find.descendant(of: rowOf(id), matching: find.text('${i + 1}')), findsOneWidget);
      }
      expect(tester.widget<DlcRow>(rowOf(2)).order, 0);
      expect(boxOf(tester, 2), '보관함 · 꺼 둔 DLC');
      expect(find.descendant(of: find.ancestor(of: rowOf(2), matching: find.byType(SheetBox)), matching: find.byType(SheetThreadColumn)), findsNothing);
      // 상자의 수 · 뚜껑 오른쪽 안내.
      final on = tester.widget<SheetBox>(find.ancestor(of: rowOf(1), matching: find.byType(SheetBox)).first);
      expect((on.count, on.hint), ('3', '불러오는 차례'));
      expect(tester.widget<SheetBox>(find.ancestor(of: rowOf(2), matching: find.byType(SheetBox)).first).count, '1');
    });

    testWidgets('보관함 줄은 흰 종이 + 먹 25 실선 · 글 옅게 — 켠 줄은 테 먹 45', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.setPacks({1});
      await pumpManager(tester, scene);
      final off = rowShape(tester, 2), on = rowShape(tester, 1);
      expect(off, DlcLook.row(on: false));
      expect((off.fill, off.stroke, off.dash, off.holeStroke), (SheetLook.paper, SheetLook.ink25, null, SheetLook.ink25), reason: '꺼 둔 줄은 점선이 아니라 실선');
      expect((on.fill, on.stroke, on.dash), (SheetLook.paper, SheetLook.ink45, null));
      Color inkOf(int id, String text) => tester.widget<Text>(find.descendant(of: rowOf(id), matching: find.text(text))).style!.color!;
      expect(inkOf(2, '해솔 기록집'), SheetLook.ink60, reason: '꺼 둔 줄의 이름은 옅게');
      expect(inkOf(1, '별여울 기록집'), SheetLook.ink85);
      expect(inkOf(2, '사건 2건 · 트랙 1개 · 줄 2개'), SheetLook.ink45);
      // 뼈대에 색이 없으면 트랙 색은 0xc27a45(layout.dart의 기본).
      expect(miniShapes(tester, 2).single, DlcLook.mini(const Color(0xffc27a45), DlcTrackMode.off), reason: '꺼 둔 줄의 트랙 꼬리표도 흰 종이 · 먹 25');
      expect((miniShapes(tester, 2).single.fill, miniShapes(tester, 2).single.stroke, miniShapes(tester, 2).single.dash), (SheetLook.paper, SheetLook.ink25, null));
      expect(miniShapes(tester, 1).single, DlcLook.mini(const Color(0xffc27a45), DlcTrackMode.own));
      // 올리면 칠 먹 4(테는 그대로).
      expect(DlcLook.row(on: false, hover: true).fill, SheetLook.ink4);
    });

    testWidgets('얹은 트랙만 점선 — 제 트랙 · 꺼 둔 DLC의 얹은 트랙은 실선 · 자세히의 얹은 트랙은 점선 3 2 + 주인 DLC', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.layout.replaceWith(sharedLayout());
      scene.setPacks({1, 2});
      await pumpManager(tester, scene);
      // 동방(켬): 제 트랙(동방 갈래) 실선 · 얹은 트랙(별여울 갈래) 점선 2 2.
      final east = miniShapes(tester, 2);
      expect([for (final s in east) s.dash], [null, SheetLook.dlcSharedDash]);
      expect(east.first.fill, SheetLook.tagFill(const Color(0xffd8a0a0)), reason: '제 트랙은 제 색 칠');
      expect((east.last.fill, east.last.stroke), (SheetLook.paper, SheetLook.tagEdge(const Color(0xff9ab0c0))), reason: '얹은 트랙은 흰 종이 · 그 트랙 색 테');
      // 해솔(끔): 얹은 트랙이어도 실선 먹 25.
      expect([for (final s in miniShapes(tester, 3)) (s.dash, s.stroke)], [(null, SheetLook.ink25), (null, SheetLook.ink25)]);
      // 창 전체에서 점선 테는 얹은 트랙뿐.
      final dashed = [for (final t in tester.widgetList<SheetTag>(find.byType(SheetTag))) if (t.shape.dash != null) t];
      expect(dashed, hasLength(1), reason: '켠 줄의 얹은 트랙 하나(자세히는 별여울 — 얹은 트랙 없음)');
      // 동방을 고르면 자세히의 얹은 트랙 줄: 흰 종이 점선 3 2 · '〈트랙〉에 얹음' · 주인 DLC.
      await tester.tap(find.text('동방의 기록집'));
      await tester.pump();
      final shared = find.byKey(const ValueKey('dlc-shared-1'));
      expect(shared, findsOneWidget);
      final tag = tester.widget<SheetTag>(find.descendant(of: shared, matching: find.byType(SheetTag)).first);
      expect((tag.shape.dash, tag.shape.fill, tag.height), (SheetLook.dlcSharedDashWide, SheetLook.paper, SheetLook.dlcTrack));
      expect(find.descendant(of: shared, matching: find.text('별여울 갈래에 얹음')), findsOneWidget);
      expect(find.descendant(of: shared, matching: find.text('별여울 기록집')), findsOneWidget, reason: '얹은 트랙의 주인 DLC');
      // 표지: 제 트랙 먼저 · 얹은 트랙(갈래) · 넷까지.
      final cover = tester.widget<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is DlcCoverPainter));
      final painter = cover.painter! as DlcCoverPainter;
      expect([for (final (t, m) in DlcCoverPainter.tracksOf(painter.card, on: painter.on)) (t.name, m)], [('동방 갈래', DlcTrackMode.own), ('별여울 갈래', DlcTrackMode.shared)]);
    });

    testWidgets('고른 줄은 고른 테(먹 100 · 1.5) — 하나뿐이고 누르면 옮겨 간다', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene);
      List<int> ringed() => [
        for (final r in tester.widgetList<DlcRow>(find.byType(DlcRow)))
          if (tester.widget<SheetPickRing>(find.descendant(of: rowOf(r.card.id), matching: find.byType(SheetPickRing)).first).on) r.card.id,
      ];
      expect(ringed(), [1]);
      expect((SheetLook.pickWidth, SheetLook.pickInk), (1.5, const Color(0xff000000)));
      await tester.tap(find.text('은빛 나루 기록집').first);
      await tester.pump();
      expect(ringed(), [3]);
      expect(find.text('은빛 나루 갈래'), findsWidgets, reason: '자세히가 따라온다');
    });

    testWidgets('끄기 · 켜기 · 삭제는 예전과 같은 콜백(onToggle · onRemove) — 삭제는 줄 끝에서 확인을 거친다', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.layout.replaceWith(SceneLayout.fromJson({
        'packs': [
          {'id': 1, 'name': '별여울 기록집', 'events': 1250, 'key': 'east-asia-base'},
          {'id': 2, 'name': '해솔 기록집', 'events': 2, 'key': 'haesol'},
          {'id': 3, 'name': '은빛 나루 기록집', 'events': 2, 'key': 'silverbay'},
        ],
        'tracks': [
          {'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'rows': [packRow(0), packRow(1)]},
          {'id': 2, 'pack': 2, 'ord': 1, 'name': '해솔 갈래', 'rows': [packRow(2), packRow(3)]},
          {'id': 3, 'pack': 3, 'ord': 2, 'name': '은빛 나루 갈래', 'rows': [packRow(4), packRow(5)]},
        ],
        'epochs': [],
      }));
      final job = DlcJob()
        ..hidden = DlcHidden.fromJson(const {
          'off': ['moonbay'],
          'cards': {'moonbay': {'name': '달물결 기록집', 'version': '2.0.0', 'tracks': [{'key': 'tide', 'name': '물결 갈래', 'color': 0xabb3c9, 'rows': 2}]}},
        });
      final toggled = <String>[], removed = <String>[];
      await pumpManager(tester, scene, job: job, onRemove: (card) async => removed.add(card.key), onToggle: (cards, on) async => toggled.add('${[for (final c in cards) c.key].join(',')}:${on ? '켬' : '끔'}'));
      expect(boxOf(tester, -1), '보관함 · 꺼 둔 DLC', reason: '저장소에서 뺀 DLC는 보관함에');
      expect([tester.widget<DlcRow>(rowOf(1)).selected, tester.widget<DlcRow>(rowOf(-1)).selected], [true, false],
          reason: '아직 고르지 않았으면 첫 DLC — 저장소에서 뺀 DLC의 번호(-1)가 "고르지 않음" 표시와 겹쳐 골라지지 않게(걸음 5 실제 앱)');
      await tester.tap(find.descendant(of: rowOf(2), matching: find.text('끄기')));
      await tester.pump();
      await tester.tap(find.descendant(of: rowOf(-1), matching: find.text('켜기')));
      await tester.pump();
      expect(toggled, ['haesol:끔', 'moonbay:켬']);
      // 고르지 않은 줄(은빛 나루)의 삭제 — 그 줄을 고르고 확인을 띄운다.
      await tester.tap(find.byKey(const ValueKey('dlc-remove-3')));
      await tester.pumpAndSettle();
      expect(find.text('"은빛 나루 기록집" DLC를 삭제할까요?'), findsOneWidget);
      expect(tester.widget<DlcRow>(rowOf(3)).selected, isTrue);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(removed, ['silverbay']);
      // 보관함 줄도 줄 끝에서 지운다.
      await tester.tap(find.byKey(const ValueKey('dlc-remove--1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(removed, ['silverbay', 'moonbay']);
      expect(find.descendant(of: rowOf(1), matching: find.text('DLC 삭제')), findsOneWidget, reason: '바탕 줄은 자리만(보이지 않는 단추로 폭을 지킴)');
      expect(tester.widget<Visibility>(find.ancestor(of: find.descendant(of: rowOf(1), matching: find.text('DLC 삭제')), matching: find.byType(Visibility))).visible, isFalse);
    });

    testWidgets('1배 자리 — 다듬기 판(sm-dlc)의 자리와 맞댄다', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene, size: const Size(1920, 1080));
      final folder = tester.getRect(find.byType(SheetFolder));
      expect(folder.width, SheetLook.dlcWidth, reason: '폴더 몸 1180(가운데)');
      expect(folder.center.dx, 960);
      final detail = tester.getRect(find.byKey(const Key('dlc-detail')));
      expect(detail.width, SheetLook.dlcDetail);
      expect(folder.right - detail.right, SheetLook.dlcPad);
      final onBox = tester.getRect(find.ancestor(of: rowOf(1), matching: find.byType(SheetBox)).first);
      expect(onBox.width, SheetLook.dlcWidth - 2 * SheetLook.dlcPad - SheetLook.dlcDetail - SheetLook.dlcColumnGap, reason: '목록 776');
      expect(detail.left - onBox.right, SheetLook.dlcColumnGap);
      expect(detail.top, onBox.top, reason: '자세히는 목록과 같은 높이에서');
      expect(detail.bottom, greaterThan(onBox.bottom), reason: '줄 넷이면 자세히가 더 길다(목록 칸 밑이 빈다)');
      expect(tester.getSize(rowOf(1)).height, SheetLook.dlcRow);
      expect(tester.getRect(rowOf(2)).top - tester.getRect(rowOf(1)).bottom, SheetLook.dlcRowGap);
      expect(tester.getRect(rowOf(1)).left - onBox.left, SheetLook.boxInset);
      // 위 칸: 찾기 240 × 28 · 단추 28 · 닫기는 오른쪽 끝.
      final find0 = tester.getRect(find.ancestor(of: find.byType(TextField), matching: find.byType(SheetTag)).first);
      expect(find0.size, const Size(SheetLook.dlcFind, SheetLook.dlcTop));
      expect(find0.left - folder.left, SheetLook.dlcPad);
      expect(onBox.top - find0.bottom, SheetLook.dlcGap);
      final close = tester.getRect(find.ancestor(of: find.text('닫기'), matching: find.byType(SheetTag)).first);
      expect((close.height, folder.right - close.right), (SheetLook.dlcTop, SheetLook.dlcPad));
      expect(tester.getSize(find.ancestor(of: find.text('모두 끄기'), matching: find.byType(SheetTag)).first).height, SheetLook.dlcTop);
      // 줄 안: 이름 30부터 · 끄기 단추 24는 가운데 · 오른쪽 12 안(삭제 길이 없으면 끄기가 끝).
      final row = tester.getRect(rowOf(1));
      expect(tester.getRect(find.descendant(of: rowOf(1), matching: find.text('별여울 기록집'))).left - row.left, SheetLook.dlcLead);
      final toggle = tester.getRect(find.descendant(of: find.descendant(of: rowOf(1), matching: find.byType(DlcSwitch)), matching: find.byType(SheetTag)).first);
      expect(toggle.height, SheetLook.chip);
      expect(toggle.center.dy, row.center.dy);
      expect(row.right - toggle.right, SheetLook.dlcButtonRight);

      // 목록이 자세히보다 길면 자세히가 목록 바닥까지 — 표지가 남는 키를 갖는다(아래에 빈 자리가 뜨지 않게 · 목업과 같은 셈).
      scene.layout.replaceWith(SceneLayout.fromJson({
        'packs': [for (var i = 1; i <= 9; i++) {'id': i, 'name': '기록집 $i', 'events': i}],
        'tracks': [for (var i = 1; i <= 9; i++) {'id': i, 'pack': i, 'ord': i - 1, 'name': '갈래 $i', 'rows': [packRow(i - 1)]}],
        'epochs': [],
      }));
      scene.setPacks({1, 2, 3, 4, 5, 6});
      await tester.pump();
      final kept = tester.getRect(find.ancestor(of: rowOf(9), matching: find.byType(SheetBox)).first);
      final detail2 = tester.getRect(find.byKey(const Key('dlc-detail')));
      expect(tester.getRect(find.ancestor(of: rowOf(1), matching: find.byType(SheetBox)).first).bottom + SheetLook.dlcBoxGap, kept.top, reason: '상자 사이 10');
      expect(detail2.bottom, kept.bottom);
      final cover = tester.getSize(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is DlcCoverPainter));
      expect(cover.height, greaterThan(DlcCoverPainter.minHeight(DlcCardInfo.of(scene.layout).first)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('좁은 창 · 휴대폰 — 자세히가 목록 밑으로(같은 폭) · 위 칸은 두 줄', (tester) async {
      final (scene, _, _) = makePackScene();
      await pumpManager(tester, scene, size: const Size(420, 900));
      final onBox = tester.getRect(find.ancestor(of: rowOf(1), matching: find.byType(SheetBox)).first);
      final detail = tester.getRect(find.byKey(const Key('dlc-detail')));
      expect(detail.top, greaterThan(onBox.bottom));
      expect(detail.width, onBox.width);
      final field = tester.getRect(find.byType(TextField)), off = tester.getRect(find.text('모두 끄기'));
      expect(off.top, greaterThan(field.bottom), reason: '단추는 찾기 밑 줄');
      expect(tester.takeException(), isNull, reason: '넘침 없음');
    });

    testWidgets('줄의 트랙 꼬리표가 들지 않으면 그리지 않고 담긴 것이 남는 폭을 갖는다(넘침 없음)', (tester) async {
      final (scene, _, _) = makePackScene();
      scene.layout.replaceWith(SceneLayout.fromJson({
        'packs': [
          {'id': 1, 'name': '트랙 많은 기록집', 'events': 120, 'key': 'many'},
        ],
        'tracks': [
          for (var i = 0; i < 12; i++) {'id': i + 1, 'pack': 1, 'ord': i, 'name': '아주 긴 이름의 갈래 $i', 'rows': [packRow(i)]},
        ],
        'epochs': [],
      }));
      await pumpManager(tester, scene);
      expect(tester.takeException(), isNull);
      final run = tester.renderObject<RenderSheetFitRun>(find.descendant(of: rowOf(1), matching: find.byType(SheetFitRun)));
      expect(run.shown, inExclusiveRange(1, 12), reason: '앞에서부터 드는 만큼만');
      expect(find.descendant(of: rowOf(1), matching: find.text('사건 120건 · 트랙 12개 · 줄 12개')), findsOneWidget);
      final text = tester.getRect(find.descendant(of: rowOf(1), matching: find.text('사건 120건 · 트랙 12개 · 줄 12개')));
      expect(text.right, lessThanOrEqualTo(tester.getRect(find.descendant(of: rowOf(1), matching: find.byType(SheetFitRun))).right));
    });

    test('표지 — 트랙 넷까지 · 가장 작은 키', () {
      TrackInfo t(int id, String name, int rows) => TrackInfo(id, 1, name, 0, rows, color: 0x9ab0c0);
      final card = DlcCardInfo(id: 1, name: '여섯 트랙', events: 0, tracks: [for (var i = 0; i < 6; i++) t(i, '갈래 $i', i + 1)]);
      expect(DlcCoverPainter.tracksOf(card, on: true), hasLength(SheetLook.dlcCoverMax));
      expect(DlcCoverPainter.tracksOf(card, on: false).map((e) => e.$2).toSet(), {DlcTrackMode.off});
      expect(DlcCoverPainter.minHeight(card), 2 * 18 + 4 * 24 + 3 * 8);
      expect(DlcCoverPainter.minHeight(const DlcCardInfo(id: 2, name: '빈', events: 1, tracks: [])), SheetLook.dlcCoverEmpty);
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

    testWidgets('여덟 DLC가 엔진의 답 그대로 줄이 된다', (tester) async {
      if (!ready) return markTestSkipped(noData);
      final layout = SceneLayout.fromJson(layoutAnswer!);
      final packs = [
        for (final p in layoutAnswer!['packs'] as List) Map<String, dynamic>.from(p as Map),
      ];
      expect(packs.length, 8);
      final cards = DlcCardInfo.of(layout);
      expect(cards.length, 8);
      for (int i = 0; i < 8; i++) {
        expect(cards[i].id, packs[i]['id'], reason: '줄의 번호는 엔진이 준 번호');
        expect(cards[i].name, packs[i]['name'], reason: '줄의 이름은 엔진이 준 이름(만들어 넣지 않는다)');
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
        expect(find.text(card.name), findsWidgets, reason: '여덟 줄 모두 제 이름으로 선다');
      }
      expect(find.textContaining('켜 둔 DLC 8개'), findsOneWidget);
      expect(switchValues(tester), List.filled(8, true));
    });

    // 창이 끄기 · 켜기 단추로 실제로 낸 조합. 아래의 검사가 이 조합 그대로 진짜 엔진에 묻는다
    // (위젯 검사 안에서는 진짜 FFI의 답을 기다릴 수 없다 — 가짜 시계가 돌기 때문).
    final made = <String, List<int>>{};

    testWidgets('단추가 낸 조합 — 여덟 · 일곱 · 빈 목록', (tester) async {
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
      expect(made.keys, containsAll(<String>['all', 'without', 'none']), reason: '앞 검사가 단추로 낸 조합');
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

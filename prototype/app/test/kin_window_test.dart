import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_glue.dart' show houseLit;
import 'package:archive_prototype/ui/detail_cell.dart' show registerCellDetail;
import 'package:archive_prototype/ui/detail_item.dart';
import 'package:archive_prototype/ui/detail_people.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/kin/family_window.dart';
import 'package:archive_prototype/ui/kin/kin_head.dart';
import 'package:archive_prototype/ui/kin/succession_view.dart';
import 'package:archive_prototype/ui/search.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kin_view_test.dart' show garamKin, garamPolity, kinBus, settleKin, useSyncDecode;

// 세계표 떠 있는 창 · 가문 창(D1 몫) · 성씨 창 · 계보 전용 인물 창 · 기존 창(D1-N2 — 확정 설계 4 · 5-3 · 8-3 · 8-4).
// 자료는 이 파일 · kin_view_test.dart의 **손 고정 자료**(가상 이름 · D1-E 기록 꼴). D1-E의 앱 고정 자료
// (`test/fixtures/kin-sample-kin.json`)가 있으면 맨 아래 묶음이 그것으로도 돈다(없으면 건너뜀 — 결합 때 붙는다).

/// 가문 기록(D1-E ④) — 물빛 온씨: 아래 파 하나 · 세계표 · 머리 칩 · 다스린 기간 · 조명 구간 · 띠 인물 상한.
Map<String, Object?> onHouse() => {
  'id': 'h-on',
  'uid': 'house:h-on',
  'itemKind': 'house',
  'name': '물빛 온씨',
  'surname': '온',
  'seat': '물빛',
  'color': '#bea893',
  'packName': '계보 견본',
  'x_surname': {'uid': 'surname:sn-on', 'name': '온'},
  'x_members': [
    for (var i = 0; i < 3; i++) {'role': 'figure', 'uid': 'k/f$i', 'name': '구성원 $i', 'when': '1400년', 'nation': 'k/garam', 'nationName': '가람 나라'},
  ],
  'x_memberCount': 250,
  'x_kin': {
    'key': 'kin:polity:k/garam',
    'n': 6,
    'gens': 3,
    'branches': [
      {'uid': 'house:h-sol', 'name': '솔파', 'color': '#b6c398', 'n': 1},
    ],
    'lineage': 4,
  },
  'x_head': [
    {'role': 'track', 'text': '가람', 'title': '짐작 — 국성으로 삼은 나라에서', 'auto': 1},
    {'role': 'people', 'text': '누리족'},
    {'role': 'surname', 'text': '물빛 온씨', 'uid': 'surname:sn-on'},
    {'role': 'tag', 'text': '왕실'},
  ],
  'x_under': ['h-on', 'h-sol'],
  'x_eras': [
    {
      'uid': 'k/garam',
      'name': '가람 나라',
      'color': '#a0bcc5',
      'span': [-299790720, -273493440],
      'cells': [
        [-299790720, -294531264],
      ],
    },
  ],
  'x_spots': [
    {'uid': 'k/garam', 'start': -299790720, 'end': -294531264},
  ],
};

/// 성씨 기록 — 그 성의 가문(`x_houses`) · 조명 구간.
Map<String, Object?> onSurname() => {
  'id': 'sn-on',
  'uid': 'surname:sn-on',
  'itemKind': 'surname',
  'name': '온',
  'x_houses': [
    {'uid': 'house:h-on', 'name': '물빛 온씨', 'color': '#bea893'},
  ],
  'x_spots': [
    {'uid': 'k/garam', 'start': -299790720, 'end': -294531264},
  ],
};

/// 계보 전용 인물 기록(D1-E ⑤) — 본문에 lineageOnly · 뼈대 자리 x_kin · 활동 칸 없음 · 생몰 없음.
Map<String, Object?> eulSon() => {
  'id': 'eul-son',
  'uid': 'k/eul-son',
  'kind': 'figure',
  'itemKind': 'figure',
  'name': '을의 아들',
  'track': 'garam',
  'lineageOnly': true,
  'role': '대군',
  'packName': '계보 견본',
  'x_kin': {'key': 'kin:polity:k/garam', 'at': 2},
  'x_find': {'hay': '을의 아들', 'sub': '계보 전용 · 가람 왕가'},
};

Map<String, Map<String, Object?>> store() => {
  'k/garam': garamPolity(),
  'kin:polity:k/garam': garamKin(),
  'house:h-on': onHouse(),
  'surname:sn-on': onSurname(),
  'k/eul-son': eulSon(),
};

/// 1배 화면(1920 × 1080)에 상세 창(오른쪽 380)과 떠 있는 창 자리를 둔 틀.
Widget screen(AppBus bus) => MaterialApp(
  home: Scaffold(
    backgroundColor: Ui.bg,
    body: Stack(
      children: [
        Positioned(
          top: Ui.top + Ui.detailInset,
          right: Ui.detailInset,
          bottom: Ui.detailBottom,
          width: Ui.detailWidth,
          child: DetailHost(bus: bus, framed: false),
        ),
      ],
    ),
  ),
);

Future<AppBus> boot(WidgetTester tester, {Map<String, Map<String, Object?>>? data}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1920, 1080);
  addTearDown(tester.view.reset);
  final made = kinBus(data ?? store());
  registerItemDetail();
  registerPeopleDetail();
  registerKinDetail();
  await tester.pumpWidget(screen(made.bus));
  return made.bus;
}

/// 세계표를 연다(슬롯) — 뼈대가 풀리고 첫 자리가 잡힐 때까지.
Future<KinDriver> openFamily(WidgetTester tester, AppBus bus, FamilyRequest req) async {
  bus.slot(familySlot).value = req;
  await tester.pump();
  await tester.pump();
  final driver = bus.slot('kinDriver').value as KinDriver;
  await settleKin(tester, driver);
  await tester.pump();
  await tester.pumpAndSettle();
  return driver;
}

void main() {
  setUp(() {
    for (final k in detailKinds) {
      DetailHost.unregister(k.id);
    }
    useSyncDecode();
    ItemDetail.surnameBadge = false;
  });

  group('세계표 떠 있는 창(결정 2 A)', () {
    testWidgets('가문 창 왼쪽에 뜬다 — 머리 칩 · 제목 · 범례 · 전체도 · 찾기(회색 예시 글 없음)', (tester) async {
      final bus = await boot(tester);
      final driver = await openFamily(tester, bus, const FamilyRequest(kin: 'kin:polity:k/garam', house: 'house:h-on'));
      expect(driver.kind, 'family');
      expect(driver.ready, isTrue);
      expect(find.text('물빛 온씨 세계표   사람 6 · 지도자 4'), findsOneWidget);
      expect(find.text('›'), findsNWidgets(2), reason: '구분 › 민족 › 본관 성씨 · 꼬리표');
      for (final t in ['지도자(나라 색 · 대수)', '지도자 아님', '부모 → 자식', '양자(양부)', '여러 대 건너뜀(n대손)', '이름 미상']) {
        expect(find.text(t), findsOneWidget, reason: '범례 $t');
      }
      expect(find.text('찾기'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.hintText, isNull, reason: '입력 칸에 회색 예시 글이 없다');
      // 자리: 오른쪽에서 501(가문 창 380 + 확대 단추 자리) · 위 84.
      final area = driver.area!;
      expect(area.right, lessThanOrEqualTo(1920 - FamilyUi.right + 1));
      expect(area.left, greaterThan(0));
      // 200명 이하라 모두 펼친 채 — 여섯 사람 모두 카드(이름 미상 없음).
      expect(driver.visible.length, 6);
    });

    testWidgets('카드는 겹치지 않고 창 밖으로 나가지 않는다 · 누른 카드는 0px · 접으면 후손 알약', (tester) async {
      final bus = await boot(tester);
      final driver = await openFamily(tester, bus, const FamilyRequest(kin: 'kin:polity:k/garam'));
      final geo = driver as KinGeometry;
      final rects = geo.cardRects;
      for (var a = 0; a < rects.length; a++) {
        for (var b = a + 1; b < rects.length; b++) {
          expect(rects[a].overlaps(rects[b]), isFalse, reason: '카드 $a · $b 겹침');
        }
      }
      // 갑(뿌리)을 접는다 — 갑 카드는 화면에서 0px.
      final before = geo.cardRect('c:k/garam|leader:0')!;
      expect(driver.toggle('c:k/garam|leader:0'), isTrue);
      await tester.pump();
      expect(geo.cardRect('c:k/garam|leader:0'), before);
      await tester.pumpAndSettle();
      expect(geo.cardRect('c:k/garam|leader:0'), before);
      expect(driver.visible, ['c:k/garam|leader:0', 'c:k/garam|leader:4'], reason: '갑의 하위가 접혔다(정은 다른 뿌리)');
      driver.expandAll();
      await tester.pumpAndSettle();
      expect(driver.visible.length, 6);
      driver.collapseAll();
      await tester.pumpAndSettle();
      expect(driver.visible.length, 2);
    });

    testWidgets('키보드 — ↓ 첫 자식 · → 형제 · Space 접기 · Esc 닫기', (tester) async {
      final bus = await boot(tester);
      final driver = await openFamily(tester, bus, const FamilyRequest(kin: 'kin:polity:k/garam'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // 갑 → 을(첫 자식)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // 을 → 병(같은 세대 옆)
      await tester.sendKeyEvent(LogicalKeyboardKey.space); // 병 접기
      await tester.pumpAndSettle();
      expect(driver.visible.contains('f:k/byeong-girl'), isFalse, reason: '병의 딸이 접혔다');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(bus.slot(familySlot).value, isNull);
      expect(bus.slot('kinDriver').value, isNull);
    });

    testWidgets('찾기 — 이름을 치면 조상을 펴고 그 카드로', (tester) async {
      final bus = await boot(tester);
      final driver = await openFamily(tester, bus, const FamilyRequest(kin: 'kin:polity:k/garam'));
      driver.collapseAll();
      await tester.pumpAndSettle();
      expect(driver.visible.contains('f:k/eul-son'), isFalse);
      await tester.enterText(find.byType(TextField), '을의 아들');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(driver.visible.contains('f:k/eul-son'), isTrue);
    });

    testWidgets('보기 단계(건의 8의 4-가) — 아래 [보통 | 점] · V로 돈다 · 점을 누르면 보통으로, 점 단계는 12px 점으로 겹치지 않는다', (tester) async {
      final bus = await boot(tester);
      final driver = await openFamily(tester, bus, const FamilyRequest(kin: 'kin:polity:k/garam'));
      final geo = driver as KinGeometry;
      expect(find.text('보통'), findsOneWidget);
      expect(find.text('점'), findsOneWidget);
      expect(geo.cardRect('c:k/garam|leader:0')!.size, const Size(124, 42));
      await tester.tap(find.text('점'));
      await tester.pumpAndSettle();
      expect(geo.cardRect('c:k/garam|leader:0')!.size, const Size(12, 12));
      // 세그먼트로 점에 들면 한눈 보기 — 맨 위부터(목업의 '점' 그림).
      expect(geo.cardRect('c:k/garam|leader:0')!.top, lessThan(driver.area!.top + 80));
      final dots = geo.cardRects;
      expect(dots.length, 6);
      for (var a = 0; a < dots.length; a++) {
        for (var b = a + 1; b < dots.length; b++) {
          expect(dots[a].overlaps(dots[b]), isFalse, reason: '점 $a · $b 겹침');
        }
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pumpAndSettle();
      expect(geo.cardRect('c:k/garam|leader:0')!.width, 124, reason: 'V — 보통으로');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.pumpAndSettle();
      final dot = geo.cardRect('c:k/garam|leader:4')!;
      expect(dot.width, 12);
      await tester.tapAt(dot.center);
      await tester.pumpAndSettle();
      expect(geo.cardRect('c:k/garam|leader:4')!.width, 124, reason: '점을 누르면 보통으로 돌아와 그 사람에게');
    });

    testWidgets('Ctrl+휠로 단계를 바꾸면 커서 밑의 사람은 화면에서 제자리(큰 세계표)', (tester) async {
      const extra = 400;
      final kin = garamKin();
      final big = {
        ...kin,
        'n': 6 + extra,
        'par': [-1, for (var i = 0; i < extra; i++) 0, ...(kin['par'] as List).skip(1).cast<int>().map((p) => p <= 0 ? p : p + extra)],
        'size': [5 + extra, for (var i = 0; i < extra; i++) 1, ...(kin['size'] as List).skip(1).cast<int>()],
        'gen': [0, for (var i = 0; i < extra; i++) 1, ...(kin['gen'] as List).skip(1).cast<int>()],
        'bits': [33, for (var i = 0; i < extra; i++) 65, ...(kin['bits'] as List).skip(1).cast<int>()],
        'edge': List.filled(6 + extra, 0),
        'branch': [0, for (var i = 0; i < extra; i++) 0, ...(kin['branch'] as List).skip(1).cast<int>()],
        'color': [1, for (var i = 0; i < extra; i++) 0, ...(kin['color'] as List).skip(1).cast<int>()],
        'name': ['갑', for (var i = 0; i < extra; i++) '후손 $i', ...(kin['name'] as List).skip(1).cast<String>()],
        'sub': List.filled(6 + extra, ''),
        'key': ['c:k/garam|leader:0', for (var i = 0; i < extra; i++) 'f:k/d$i', ...(kin['key'] as List).skip(1).cast<String>()],
        'branches': [
          {'uid': 'house:h-garam', 'name': '가람 왕가', 'color': '#c8b193', 'at': 0, 'up': -1},
          {'uid': 'house:h-sol', 'name': '솔파', 'color': '#b6c398', 'at': 4 + extra, 'up': 0},
        ],
        'cells': <String, int>{},
      };
      final bus = await boot(tester, data: {...store(), 'kin:polity:k/garam': big});
      final driver = await openFamily(tester, bus, const FamilyRequest(kin: 'kin:polity:k/garam'));
      final geo = driver as KinGeometry;
      driver.expandAll();
      await tester.pumpAndSettle();
      driver.panBy(6000, 0);
      await tester.pumpAndSettle();
      final before = {for (final k in driver.visible) k: geo.cardRect(k)?.center};
      final at = driver.area!.center;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect((driver as KinLevels).level, 1, reason: '아래로 굴리면 점');
      final kept = [
        for (final e in before.entries)
          if (e.value != null && geo.cardRect(e.key) != null && (geo.cardRect(e.key)!.center.dx - e.value!.dx).abs() < .5) e.key,
      ];
      // 세로는 판이 창보다 낮아지면 위쪽 여백 안에서 멈춘다 — 가로 자리만 본다.
      expect(kept, isNotEmpty, reason: '커서에 가장 가까운 사람의 가로 자리가 그대로');
    });

    testWidgets('2,000명을 모두 펼쳐도 그리는 카드 ≤ 200 · 선 ≤ 300', (tester) async {
      const extra = 2000;
      final kin = garamKin();
      final big = {
        ...kin,
        'n': 6 + extra,
        'par': [-1, for (var i = 0; i < extra; i++) 0, ...(kin['par'] as List).skip(1).cast<int>().map((p) => p <= 0 ? p : p + extra)],
        'size': [5 + extra, for (var i = 0; i < extra; i++) 1, ...(kin['size'] as List).skip(1).cast<int>()],
        'gen': [0, for (var i = 0; i < extra; i++) 1, ...(kin['gen'] as List).skip(1).cast<int>()],
        'bits': [33, for (var i = 0; i < extra; i++) 65, ...(kin['bits'] as List).skip(1).cast<int>()],
        'edge': List.filled(6 + extra, 0),
        'branch': [0, for (var i = 0; i < extra; i++) 0, ...(kin['branch'] as List).skip(1).cast<int>()],
        'color': [1, for (var i = 0; i < extra; i++) 0, ...(kin['color'] as List).skip(1).cast<int>()],
        'name': ['갑', for (var i = 0; i < extra; i++) '후손 $i', ...(kin['name'] as List).skip(1).cast<String>()],
        'sub': List.filled(6 + extra, ''),
        'key': ['c:k/garam|leader:0', for (var i = 0; i < extra; i++) 'f:k/d$i', ...(kin['key'] as List).skip(1).cast<String>()],
        'branches': [
          {'uid': 'house:h-garam', 'name': '가람 왕가', 'color': '#c8b193', 'at': 0, 'up': -1},
          {'uid': 'house:h-sol', 'name': '솔파', 'color': '#b6c398', 'at': 4 + extra, 'up': 0},
        ],
        'cells': <String, int>{},
      };
      final bus = await boot(tester, data: {...store(), 'kin:polity:k/garam': big});
      final driver = await openFamily(tester, bus, const FamilyRequest(kin: 'kin:polity:k/garam'));
      driver.expandAll();
      await tester.pumpAndSettle();
      expect(driver.built, lessThanOrEqualTo(200), reason: '그린 카드 ${driver.built}');
      expect(driver.lines, lessThanOrEqualTo(300), reason: '그린 선 ${driver.lines}');
      for (var k = 0; k < 10; k++) {
        driver.panBy(4000, 0);
        await tester.pump();
      }
      expect(driver.built, lessThanOrEqualTo(200));
      expect(driver.built, greaterThan(0), reason: '밀어도 보이는 카드는 그린다');
      // 점 단계(건의 8의 4-가): 한 화면에 사람이 더 들어오므로 합격선도 따로 — 점 ≤ 800 · 선 ≤ 1,600(창 한 장 740 × 700 ÷ 점 간격 24 × 세대 줄 30).
      (driver as KinLevels).setLevel(1);
      await tester.pumpAndSettle();
      expect((driver as KinLevels).level, 1);
      expect(driver.built, inInclusiveRange(1, 800), reason: '그린 점 ${driver.built}');
      expect(driver.lines, lessThanOrEqualTo(1600), reason: '그린 선 ${driver.lines}');
    });
  });

  group('가문 창 · 성씨 창 · 계보 전용 인물 창(D1)', () {
    testWidgets('가문 창 — 다스린 기간 막대 · 세계표 단추 · 구성원 상한 · 파 포함 조명', (tester) async {
      final bus = await boot(tester);
      bus.select('house:h-on', kind: 'house');
      await tester.pumpAndSettle();
      expect(find.textContaining('다스린 기간'), findsOneWidget);
      expect(find.text('가람 나라'), findsWidgets);
      expect(find.text('247명 더 · 세계표'), findsOneWidget);
      // 계보 전용 인물 수는 x_kin.lineage(D1-E ④ 덧붙임)로 — 웹 가문 창과 같은 글. 뼈대 사람 수 n(지도자 · 띠 인물 포함)은 쓰지 않는다.
      expect(find.text('계보 전용 인물 4명 · '), findsOneWidget);
      expect(find.textContaining('세계표의 사람'), findsNothing);
      // 조명: 누른 가문 + 아래 파 · 구간은 x_spots 그대로.
      final lit = houseLit(bus.slot('house').value);
      expect(lit.house, 'h-on');
      expect(lit.houses, {'h-on', 'h-sol'});
      expect(bus.slot('spots').value, isA<List<Map<String, dynamic>>>());
      await tester.tap(find.text('세계표'));
      await tester.pump();
      expect(bus.slot(familySlot).value, const FamilyRequest(kin: 'kin:polity:k/garam', house: 'house:h-on'));
      // 창을 닫으면 조명이 꺼진다(끈 뒤 = 켜기 전).
      bus.slot(familySlot).value = null;
      bus.clearSelection();
      await tester.pumpAndSettle();
      expect(bus.slot('house').value, isNull);
      expect(bus.slot('spots').value, isNull);
    });

    testWidgets('성씨 창 — 성씨 배지 · 가문 수 · 다스린 나라 수 · 가문 칩 · 그 성의 가문 모두 조명', (tester) async {
      final bus = await boot(tester);
      bus.select('surname:sn-on', kind: 'surname');
      await tester.pumpAndSettle();
      final state = bus.slot('detail').value as DetailState;
      expect(state.branch!.id, 'surname');
      expect(state.pick, isFalse);
      expect(find.text('성씨'), findsOneWidget);
      expect(find.text('가문 1 · 다스린 나라 1'), findsOneWidget);
      expect(find.text('물빛 온씨'), findsOneWidget);
      final lit = houseLit(bus.slot('house').value);
      expect(lit.house, isNull, reason: '성씨는 누른 가문이 없다');
      expect(lit.houses, {'h-on', 'h-sol'});
      await tester.tap(find.text('물빛 온씨'));
      await tester.pumpAndSettle();
      expect(bus.selection.value!.uid, 'house:h-on');
    });

    testWidgets('계보 전용 인물 창 — 고르지 않음 · 파 · 부모 · 자식 줄 · 생몰 줄 없음 · 세계표에서 보기', (tester) async {
      final bus = await boot(tester);
      bus.select('k/eul-son', kind: 'figure');
      await tester.pumpAndSettle();
      final state = bus.slot('detail').value as DetailState;
      expect(state.branch!.id, 'lineage');
      expect(state.pick, isFalse, reason: '연표를 흐리게 하지 않는다');
      expect(state.lane, isFalse);
      expect(find.text('계보 전용 · 대군'), findsOneWidget, reason: '갈래 배지는 웹과 같은 글(계보 전용 · 역할)');
      expect(find.textContaining('미상'), findsNothing, reason: '생몰을 적지 않았으면 생몰 줄이 없다(비움 ≠ 미상)');
      expect(find.textContaining('부모 · 조상: 을'), findsOneWidget);
      await tester.tap(find.text('세계표에서 보기'));
      await tester.pump();
      expect(bus.slot(familySlot).value, const FamilyRequest(kin: 'kin:polity:k/garam', focus: 'f:k/eul-son'));
      // 승계표에서 보기 — 가장 가까운 지도자 조상(을)의 나라 승계표.
      await tester.tap(find.text('승계표에서 보기'));
      await tester.pump();
      expect(bus.selection.value!.uid, 'k/garam');
      expect(bus.selection.value!.cell, successionCell);
    });

    testWidgets('나라 상세의 지도자 상자 — 지도자 둘 이상이면 승계표 단추', (tester) async {
      final bus = await boot(tester);
      bus.select('k/garam');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('승계표'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('승계표'));
      await tester.pump();
      expect(bus.selection.value!.cell, successionCell);
    });

    testWidgets('휴대폰의 성씨 배지(결정 6 A) — 가문 배지 옆 성 · 본관', (tester) async {
      ItemDetail.surnameBadge = true;
      final polity = garamPolity()..addAll({'houseId': 'h-on', 'houseName': '물빛 온씨', 'houseColor': '#bea893'});
      final bus = await boot(tester, data: {...store(), 'k/garam': polity});
      bus.select('k/garam');
      await tester.pumpAndSettle();
      expect(find.text('성 온 · 본관 물빛'), findsOneWidget);
      await tester.tap(find.text('성 온 · 본관 물빛'));
      await tester.pumpAndSettle();
      expect(bus.selection.value!.uid, 'surname:sn-on');
    });

    // 결합(D1n)에서 더함: 지도자 칸 창에도 같은 배지(확정 설계 5-2 '지도자 칸 창 · 왕조 창의 가문 배지 옆').
    testWidgets('휴대폰의 성씨 배지 — 지도자 칸 창의 가문 배지 옆에도(컴퓨터에서는 없음)', (tester) async {
      final polity = garamPolity();
      final leaders = [for (final l in polity['leaders'] as List) {...(l as Map).cast<String, Object?>()}];
      leaders[0].addAll({'houseId': 'h-on', 'houseName': '물빛 온씨', 'houseColor': '#bea893'});
      polity['leaders'] = leaders;
      registerCellDetail();
      ItemDetail.surnameBadge = false;
      final bus = await boot(tester, data: {...store(), 'k/garam': polity});
      bus.select('k/garam', cell: 'leader:0');
      await tester.pumpAndSettle();
      expect(find.text('가문 물빛 온씨'), findsOneWidget);
      expect(find.text('성 온 · 본관 물빛'), findsNothing, reason: '컴퓨터에서는 띠 위 풍선이 같은 값을 보인다');
      ItemDetail.surnameBadge = true;
      bus.clearSelection();
      await tester.pumpAndSettle();
      bus.select('k/garam', cell: 'leader:0');
      await tester.pumpAndSettle();
      expect(find.text('성 온 · 본관 물빛'), findsOneWidget);
      await tester.tap(find.text('성 온 · 본관 물빛'));
      await tester.pumpAndSettle();
      expect(bus.selection.value!.uid, 'surname:sn-on');
    });
  });

  group('검색 — 기간 없는 결과 줄(8-4 · D1-B 검색 답 꼴)', () {
    testWidgets('계보 전용 인물 줄이 깨지지 않고, 고르면 계보 전용 인물 창이 열린다', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.reset);
      final data = store();
      final controller = TimelineController()..resize(1920, 800);
      final scene = TimelineScene(
        controller: controller,
        layout: SceneLayout.fromJson(const {'packs': [], 'tracks': [], 'epochs': []}),
        fetchTile: (level, x, chunk, packs) async => throw UnimplementedError(),
      );
      final bus = AppBus(
        ask: (q) async {
          if (q['op'] == 'search') {
            // 엔진 검색 답(D1-B): 계보 전용 인물 — kind figure · sub = x_find.sub · start · end · row null · when '미정'.
            return {
              'items': [
                {'kind': 'figure', 'uid': 'k/eul-son', 'name': '을의 아들', 'sub': '계보 전용 · 가람 왕가', 'start': null, 'end': null, 'row': null, 'track': '', 'when': '미정', 'cell': null, 'id': null},
                // 결합에서 더함: 기간 있는 띠 인물 줄 — 기간 없는 줄은 같은 갈래 묶음 안에서 이 뒤에 선다(엔진 · 웹 차례).
                {'kind': 'figure', 'uid': 'k/eul-wife', 'name': '을의 비', 'sub': '인물', 'start': 1000000, 'end': 1100000, 'row': null, 'track': '가람', 'when': '1400년', 'cell': null, 'id': null},
              ],
              'has_more': false,
            };
          }
          if (q['op'] == 'entity') {
            final body = data[q['uid']];
            if (body == null) throw StateError('없음');
            return {'uid': q['uid'], 'kind': body['kind'] ?? 'period', 'json': jsonEncode(body)};
          }
          return const {};
        },
        controller: controller,
        scene: scene,
      );
      registerPeopleDetail();
      registerKinDetail();
      final search = SearchController(bus: bus);
      addTearDown(search.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Align(alignment: Alignment.topLeft, child: SearchPanel(bus: bus, controller: search, withField: true, autofocus: true)),
                Positioned(top: 72, right: 12, bottom: 16, width: 380, child: DetailHost(bus: bus, framed: false)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), '을의');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 서고 꼴의 검색 줄(4단계 틀의 시트와 창 걸음 3): 이름 · 곁글 · 오른쪽 기간 글이 저마다 글 하나다.
      expect(find.text('을의 아들'), findsOneWidget);
      expect(find.text('계보 전용 · 가람 왕가'), findsOneWidget);
      // 해 칸은 비운다(웹 runSearch · 설계 9-2 D1-W2 6) — 엔진의 '미정'을 쓰지 않음(D1n 결합에서 고침).
      expect(find.text('미정'), findsNothing);
      expect([for (final h in search.hits) h.name], ['을의 비', '을의 아들'], reason: '기간 없는 줄은 기간 있는 줄 뒤');
      expect([for (final h in search.hits) h.timeless], [false, true]);
      final before = bus.go.value;
      search.activate(1);
      await tester.pumpAndSettle();
      final state = bus.slot('detail').value as DetailState;
      expect(state.branch!.id, 'lineage');
      expect(state.pick, isFalse);
      expect(bus.go.value, same(before), reason: '기간 없는 줄은 창만 열고 연표를 옮기지 않는다(0분 = 1970년으로 가지 않음)');
    });
  });

  // D1-E의 앱 고정 자료가 있으면(결합 뒤) 그 기록으로도 창이 선다 — 없으면 건너뛴다.
  // KIN_FIXTURES=<폴더>면 그 폴더의 것(결합 전 다른 가지의 고정 자료를 꺼내 볼 때 — kin_layout_test · kin_record_test와 같은 길).
  final real = File('${Platform.environment['KIN_FIXTURES'] ?? 'test/fixtures'}/kin-sample-kin.json');
  group('D1-E 고정 자료(sample-kin)', () {
    Map<String, Map<String, Object?>> load() => {
      for (final r in jsonDecode(real.readAsStringSync()) as List)
        (r as Map)['uid'] as String: {...(jsonDecode(r['json'] as String) as Map).cast<String, Object?>(), 'kind': r['kind']},
    };

    testWidgets('승계표 · 세계표 · 가문 창이 실제 기록으로 선다 — 한 사람 한 번 · 카드 겹침 0', (tester) async {
      final data = load();
      final bus = await boot(tester, data: data);
      bus.select('sample-kin/kin-garam', cell: successionCell);
      await tester.pump();
      await tester.pump();
      final succ = bus.slot('kinDriver').value as KinDriver;
      await settleKin(tester, succ);
      succ.expandAll();
      await tester.pumpAndSettle();
      final keys = succ.visible;
      expect(keys.toSet().length, keys.length);
      final family = await openFamily(tester, bus, const FamilyRequest(kin: 'kin:h-kin-on', house: 'house:h-kin-on'));
      final rects = (family as KinGeometry).cardRects;
      for (var a = 0; a < rects.length; a++) {
        for (var b = a + 1; b < rects.length; b++) {
          expect(rects[a].overlaps(rects[b]), isFalse);
        }
      }
      expect(find.textContaining('물빛 온씨 세계표'), findsOneWidget);
      // 가문 창의 계보 전용 인물 줄 — 실제 기록의 x_kin.lineage(D1-E ④ 덧붙임)를 웹 글 그대로.
      bus.slot(familySlot).value = null;
      bus.select('house:h-kin-on', kind: 'house');
      await tester.pumpAndSettle();
      final lineage = (data['house:h-kin-on']!['x_kin'] as Map)['lineage'];
      if (lineage is num) expect(find.text('계보 전용 인물 ${lineage.toInt()}명 · '), findsOneWidget);
    });
  }, skip: real.existsSync() ? false : 'D1-E 고정 자료가 아직 이 가지에 없다(결합 때 붙는다)');
}

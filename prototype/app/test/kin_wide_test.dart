import 'dart:convert';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/fonts.dart' show sceneFontFamily, sceneFontFallback;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart' show SceneView;
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/sheet_look.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/detail_cell.dart';
import 'package:archive_prototype/ui/detail_item.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/group_tree.dart' show GroupTreeRequest, groupTreeSlot, openGroupTree;
import 'package:archive_prototype/ui/kin/kin_head.dart' show SeamLine;
import 'package:archive_prototype/ui/kin/kin_rows.dart' show KinLevel;
import 'package:archive_prototype/ui/kin/succession_look.dart';
import 'package:archive_prototype/ui/kin/succession_view.dart';
import 'package:archive_prototype/ui/kin/succession_wide.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'load_app_fonts.dart';

// 승계표 넓은 창(화면 아래 서랍 — 리메이크 4단계 틀의 시트와 창 걸음 7 · 다듬기 판 sh-succ-wide). 자료는 **이 파일 안의 손 고정 자료**(가상 이름):
// 정권 '가람 제국'(800 ~ 1000 · 지도자 다섯 — 넷째 해만 다스린 짧은 재위 · 복위 · 정변 · 비움) · 앞 나라 둘(직접 · 간접 — 합쳐짐) ·
// 뒤 나라 둘(부분 · 부흥 — 둘째 줄). 앞 나라 '옛 칸국'만 기록이 있고(300 ~ 800 — 표 밖으로 이어져 열린 끝), 나머지는 `x_succ`의 해 글로 읽는다.

const polityUid = 'k/garam-empire';

Map<String, Object?> empire() => {
  'uid': polityUid,
  'name': '가람 제국',
  'color': '#abb3c9',
  'start': 800,
  'endY': 1000,
  'leaders': [
    {'name': '첫솔', 'ordinal': 1, 'start': 800, 'end': 840},
    {'name': '둘솔', 'ordinal': 2, 'start': 840, 'end': 900},
    {'name': '짧은눈', 'ordinal': 3, 'start': 900, 'end': 904},
    {'name': '둘솔', 'ordinal': 4, 'start': 904, 'end': 950},
    {'name': '끝솔', 'ordinal': 5, 'start': 950, 'end': 1000},
  ],
  'x_lineage': {
    'leader:0': {'kin': '본인', 'how': '칭제', 'line': 5, 'seam': '본인 · 칭제'},
    'leader:1': {'kin': '아들', 'how': '세습', 'line': 5, 'seam': '아들 · 세습'},
    'leader:2': {'kin': '사촌', 'how': '정변', 'line': 1, 'seam': '사촌 · 정변'},
    'leader:3': {'kin': '사촌', 'how': '복위', 'line': 4, 'restored': 1, 'seam': '사촌 · 복위'},
    'leader:4': {'line': 0},
  },
  'x_succ': {
    'pre': [
      {'uid': 'k/old', 'name': '옛 칸국', 'color': '#a4b1b7', 'when': '300년 ~ 800년', 'type': 'direct'},
      {'uid': 'k/east', 'name': '동쪽 나라', 'color': '#c8b193', 'when': '790년 ~ 800년', 'type': 'indirect'},
    ],
    'post': [
      {'uid': 'k/north', 'name': '북쪽 나라', 'color': '#dab195', 'when': '1000년 ~ 1200년', 'type': 'partial'},
      {'uid': 'k/south', 'name': '남쪽 나라', 'color': '#bbacc8', 'when': '1000년 ~ 1020년', 'type': 'revival'},
    ],
  },
};

Map<String, Object?> oldKhanate() => {'uid': 'k/old', 'name': '옛 칸국', 'color': '#a4b1b7', 'start': 300, 'endY': 800};

/// 엔진 `entity` 답처럼 돌려주는 길(없는 항목은 던짐 — 앞뒤 나라는 해 글로 읽는다).
AppBus wideBus({Map<String, Map<String, Object?>>? store}) {
  final records = store ?? {polityUid: empire(), 'k/old': oldKhanate()};
  final controller = TimelineController()..resize(1920, 1000);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {'packs': [], 'tracks': [], 'epochs': []}),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('창 검사는 타일을 읽지 않는다'),
  );
  return AppBus(
    ask: (query) async {
      if (query['op'] != 'entity') return const {};
      final uid = query['uid'] as String;
      final body = records[uid];
      if (body == null) throw StateError('없는 항목 $uid');
      return {'uid': uid, 'kind': 'period', 'json': jsonEncode(body)};
    },
    controller: controller,
    scene: scene,
  );
}

/// 글 폭 흉내(검사의 순수 셈) — 한 글자 = 글 크기(굵게도 같음).
double fakeMeasure(InlineSpan span) {
  var w = 0.0;
  void walk(InlineSpan s, double size) {
    final own = s.style?.fontSize ?? size;
    if (s is TextSpan) {
      w += (s.text ?? '').length * own;
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c, own);
      }
    }
  }

  walk(span, 14);
  return w;
}

SuccWideData parsed() => SuccWideData.parse(polityUid, empire().cast<String, dynamic>(), spans: {'k/old': (300.0, 800.0)})!;

/// 연표 자리(폭 [width] × 1000)에 서랍 층만 띄운다 — [left]를 주면 왼쪽에 그 위젯(상세 창 뼈대).
Future<void> mount(WidgetTester tester, AppBus bus, {double width = 1920, Widget? left, bool keys = false, VoidCallback? onInset}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width + (left == null ? 0 : 380), 1000);
  addTearDown(tester.view.reset);
  Widget body = Row(children: [
    if (left != null) SizedBox(width: 380, child: left),
    SizedBox(width: width, child: Stack(children: [Positioned.fill(child: SuccessionDrawer(bus: bus, onInset: onInset))])),
  ]);
  if (keys) body = ShellKeys(bus: bus, windowOpen: () => bus.selection.value != null, child: body);
  // 실행본과 같은 글꼴(프리텐다드)로 — 글 폭이 실제와 같아야 단추 줄 · 열쇠표의 자리를 본다.
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
    home: Scaffold(backgroundColor: Ui.bg, body: body),
  ));
}

SuccessionDrawerState drawerOf(WidgetTester tester) => tester.state<SuccessionDrawerState>(find.byType(SuccessionDrawer));

/// 띠 [i]의 꼬리표(차례 — 앞 나라 둘 · 지도자 다섯 · 뒤 나라 둘).
Finder tagAt(int i) => find.byWidgetPredicate((w) => w is SuccWideTag && w.index == i);

Future<void> openWide(WidgetTester tester, AppBus bus) async {
  openSuccessionWide(bus, polityUid);
  for (var i = 0; i < 10; i++) {
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// 같은 줄에서 겹치는 상자 짝 수.
int overlaps(List<Rect> boxes) {
  var n = 0;
  for (var i = 0; i < boxes.length; i++) {
    for (var j = i + 1; j < boxes.length; j++) {
      if (boxes[i].overlaps(boxes[j])) n++;
    }
  }
  return n;
}

void main() {
  setUpAll(loadAppFonts);

  group('자료 · 자리 셈', () {
    test('정권 기록 → 띠(앞 나라 · 지도자 · 뒤 나라) · 이음 · 쓰인 것만 범례', () {
      final d = parsed();
      expect([for (final b in d.bands) '${b.side.name}:${b.name}'], [
        'pre:옛 칸국', 'pre:동쪽 나라', //
        'leader:첫솔', 'leader:둘솔', 'leader:짧은눈', 'leader:둘솔', 'leader:끝솔',
        'post:북쪽 나라', 'post:남쪽 나라',
      ]);
      expect(d.leaders, 5);
      expect(d.sub, '800 ~ 1000년 · 지도자 5');
      expect([for (final l in d.links) '${l.from}→${l.to}:${l.line}'], [
        '2→3:${SeamLine.solid}', '3→4:${SeamLine.usurp}', '4→5:${SeamLine.restore}', '5→6:${SeamLine.blank}', //
        '0→2:${SeamLine.solid}', '1→2:${SuccLine.dashed}', '6→7:${SuccLine.thin}', '6→8:${SuccLine.dashed}',
      ]);
      expect(d.bands[5].again, isTrue, reason: '복위는 열쇠표 다시');
      expect(d.bands[1].a, 790, reason: '기록이 없는 앞 나라는 x_succ의 해 글');
      expect(d.bands[0].a, 300, reason: '받은 기록의 해');
      expect(d.legend, [
        (SuccLegendKind.seam(SeamLine.solid), '세습 · 추대 · 직접 승계'),
        (SuccLegendKind.seam(SeamLine.usurp), '찬탈 · 정변'),
        (SuccLegendKind.seam(SuccLine.dashed), '간접 승계 · 부흥'),
        (SuccLegendKind.seam(SuccLine.thin), '부분 승계'),
        (SuccLegendKind.merge, '합쳐짐'),
        (SuccLegendKind.again, '복위(같은 사람)'),
        (SuccLegendKind.key, '관계 · 방식'),
      ], reason: '비움(글 없는 옅은 실)은 범례에 없음');
      expect(succWhenSpan('기원전 200년 ~ 100년'), (-200.0, 100.0));
      expect(succWhenSpan('미정'), (null, null));
      expect(succWhenSpan('미정 ~ 1년'), (null, 1.0), reason: '해가 없는 쪽은 열린 끝');
    });

    test('줄 · 들임 · 열린 끝 · 짧은 재위 이름은 열쇠표로 · 열쇠표 겹침 0 · 실 · 매듭 · 눈금', () {
      final p = SuccWidePlan.layout(parsed(), width: 1840, measure: fakeMeasure);
      expect(p.width, 1840, reason: '서랍 폭에 맞춤(가장 짧은 재위 4년도 자리 28 이상)');
      expect(p.rows, 2, reason: '앞 · 뒤 나라 둘째는 둘째 줄');
      expect(p.rowOf, [0, 1, 0, 0, 0, 0, 0, 0, 1]);
      // 맞닿은 꼬리표 사이 4 · 갈래 실이 지나는 해(800 · 1000)는 10.
      expect(p.boxes[3].left - p.boxes[2].right, 4);
      expect(p.boxes[2].left - p.boxes[0].right, 10);
      expect(p.boxes[7].left - p.boxes[6].right, 10);
      // 열린 끝 — 앞 나라 '옛 칸국'(300 ~)은 왼끝 · 뒤 나라 둘(표 밖까지)은 오른끝.
      expect([for (var i = 0; i < 9; i++) if (p.openL[i]) i], [0]);
      expect([for (var i = 0; i < 9; i++) if (p.openR[i]) i], [7, 8]);
      expect(p.holes[0], isNull, reason: '열린 왼끝은 구멍 없음');
      expect(p.diamonds[7], isNull, reason: '나가는 실이 없는 띠는 마름모 없음');
      // 짧은 재위(4년) — 이름이 들지 않아 열쇠표로.
      expect(p.names[4], SuccWideName.key);
      expect(p.names[2], SuccWideName.full);
      final short = p.keys.singleWhere((k) => k.band == 4);
      expect(short.text.toPlainText(), '3대 짧은눈 · 사촌 · 정변');
      expect(p.keys.singleWhere((k) => k.band == 5).text.toPlainText(), '다시 · 사촌 · 복위');
      expect(p.keys.where((k) => k.band == 6), isEmpty, reason: '비움은 열쇠표 없음');
      expect(p.keys.singleWhere((k) => k.band == 7).text.toPlainText(), '부분 승계');
      // 열쇠표끼리 겹침 0 · 창 끝 안 · 띠 윗변 1 위 · 실은 띠 윗변에서 열쇠표 구멍으로.
      for (var r = 0; r < p.rows; r++) {
        expect(overlaps([for (final k in p.keys) if (p.rowOf[k.band] == r) k.box.inflate(1.5)]), 0);
      }
      for (final k in p.keys) {
        expect(k.box.left, greaterThanOrEqualTo(0));
        expect(k.box.right, lessThanOrEqualTo(p.width));
        expect(p.boxes[k.band].top - k.box.bottom, 1);
        expect(k.from.dy, p.boxes[k.band].top + .5);
        expect(k.to, k.box.topLeft + const Offset(6.5, 6.5));
      }
      // 실 — 이음 여덟 모두 · 둘째 줄 앞 나라 → 첫 지도자는 틈에서 굽음 + 합쳐짐 매듭 하나.
      expect(p.threads.length, 8);
      expect(p.threads.where((t) => !t.same).length, 2);
      expect(p.knots, hasLength(1));
      expect(p.knots.single.dy, p.holes[2]!.dy);
      // 눈금 — 25년마다(해 글은 50년마다).
      final majors = [for (final t in p.ticks) if (t.major) t.label];
      expect(majors, containsAllInOrder(['800', '850', '900', '950', '1000']));
      expect(p.ticks.where((t) => !t.major).length, greaterThan(3));
    });

    test('가장 짧은 재위가 자리 28보다 좁으면 표가 서랍보다 넓어져 가로로 끈다', () {
      final rec = empire();
      (rec['leaders']! as List)[2] = {'name': '짧은눈', 'ordinal': 3, 'start': 900, 'end': 901};
      final d = SuccWideData.parse(polityUid, rec.cast<String, dynamic>())!;
      final p = SuccWidePlan.layout(d, width: 1840, measure: fakeMeasure);
      expect(p.scale, 28, reason: '1년 = 28px');
      expect(p.width, greaterThan(1840));
      expect(p.boxes[4].width, closeTo(24, 1), reason: '들임 2 + 2를 빼고 24');
    });
  });

  group('서랍', () {
    testWidgets('열기 — 정권 색 폴더 · 제목 꼬리표 · 꼬리표 수 = 지도자 + 앞뒤 나라 · 열린 끝 옅어짐 · 열쇠표 겹침 0', (tester) async {
      final bus = wideBus();
      var insets = 0;
      await mount(tester, bus, onInset: () => insets++);
      await openWide(tester, bus);
      final s = drawerOf(tester);
      expect(s.isOpen, isTrue);
      expect(find.byKey(succWideKey), findsOneWidget);
      final folder = tester.widget<SheetFolder>(find.byType(SheetFolder));
      expect(folder.label, '승계표');
      expect(folder.color, const Color(0xffabb3c9));
      expect(find.text('가람 제국'), findsOneWidget);
      expect(find.text('800 ~ 1000년 · 지도자 5'), findsOneWidget);
      // 꼬리표 = 지도자 다섯 + 앞 나라 둘 + 뒤 나라 둘.
      expect(find.byType(SuccWideTag), findsNWidgets(5 + 2 + 2));
      // 열린 끝(옛 칸국 · 북쪽 나라 · 남쪽 나라)만 옅어짐.
      expect(find.descendant(of: find.byType(SuccWideTag), matching: find.byType(ShaderMask)), findsNWidgets(3));
      // 짧은 재위는 띠에 이름 없이 열쇠표에.
      expect(find.text('짧은눈'), findsNothing);
      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == '3대 짧은눈 · 사촌 · 정변'), findsOneWidget);
      // 열쇠표 — 화면 자리로 겹침 0 · 폴더 안.
      final keys = [for (final e in find.byType(SuccKeyLabel).evaluate()) tester.getRect(find.byWidget(e.widget))];
      final inLegend = tester.getRect(find.byKey(succWideKey)).top + 20 + 16 + 56;
      final chartKeys = [for (final k in keys) if (k.top > inLegend) k];
      expect(chartKeys, hasLength(s.plan!.keys.length));
      expect(overlaps([for (final k in chartKeys) k.deflate(.1)]), 0);
      final box = tester.getRect(find.byKey(succWideKey));
      for (final k in chartKeys) {
        expect(box.contains(k.topLeft) && box.contains(k.bottomRight), isTrue);
      }
      // 서랍 자리 — 양옆 24 · 아래 14 · 연표 비킴 몫 = 폴더 키 + 아래 14 + 흰 둘레 6.
      expect(box.left, 24);
      expect(box.right, 1920 - 24);
      expect(box.bottom, 1000 - 14);
      expect(SuccessionDrawer.insetOn(bus), box.height + 14 + 6);
      expect(insets, greaterThan(0), reason: '앱 틀을 다시 그리게 알림');
      // 범례 — 쓰인 실 갈래 · 열쇠표 · 정통성 넷(먹 25 금 앞뒤).
      for (final word in ['세습 · 추대 · 직접 승계', '찬탈 · 정변', '합쳐짐', '복위(같은 사람)', '관계 · 방식', '공동', '섭정', '명목', '주장']) {
        expect(find.text(word), findsOneWidget, reason: word);
      }
      expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == SheetLook.ink25), findsNWidgets(2));
      expect(find.widgetWithText(SheetPaperButton, '수준 ▾'), findsOneWidget);
      expect(find.widgetWithText(SheetPaperButton, '닫기'), findsOneWidget);
    });

    testWidgets('누름 — 지도자 꼬리표는 그 칸 창 · 앞뒤 나라는 그 나라 상세 · 닫기', (tester) async {
      final bus = wideBus();
      await mount(tester, bus);
      await openWide(tester, bus);
      await tester.tap(tagAt(3));
      await tester.pump();
      expect(bus.selection.value?.uid, polityUid);
      expect(bus.selection.value?.cell, 'leader:1');
      await tester.tap(tagAt(0));
      await tester.pump();
      expect(bus.selection.value?.uid, 'k/old');
      expect(bus.selection.value?.cell, isNull);
      expect(drawerOf(tester).isOpen, isTrue, reason: '누름은 서랍을 닫지 않음');
      await tester.tap(find.widgetWithText(SheetPaperButton, '닫기'));
      await tester.pumpAndSettle();
      expect(bus.slot(succWideSlot).value, isNull);
      expect(find.byKey(succWideKey), findsNothing);
      expect(SuccessionDrawer.insetOn(bus), 0);
    });

    testWidgets('Esc — 상세 창이 먼저(단축키 부품이 닫음), 그다음 이 창', (tester) async {
      final bus = wideBus();
      bus.slot(slotCommand).addListener(() {
        final c = bus.slot(slotCommand).value;
        if (c is AppCommand && c.name == Cmd.close) bus.clearSelection();
      });
      await mount(tester, bus, keys: true);
      await openWide(tester, bus);
      bus.select(polityUid);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(bus.selection.value, isNull, reason: '첫 Esc는 상세 창');
      expect(drawerOf(tester).isOpen, isTrue, reason: '같은 누름에 서랍까지 닫지 않음');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(bus.slot(succWideSlot).value, isNull, reason: '둘째 Esc는 서랍');
    });

    testWidgets('단체 계보 창과 한 자리 — 어느 쪽을 열든 다른 쪽을 닫는다', (tester) async {
      final bus = wideBus();
      await mount(tester, bus);
      bus.slot(groupTreeSlot).value = const GroupTreeRequest('k/tree');
      await openWide(tester, bus);
      expect(bus.slot(groupTreeSlot).value, isNull, reason: '서랍을 열면 계보 창은 닫힘');
      expect(drawerOf(tester).isOpen, isTrue);
      openGroupTree(bus, 'k/tree');
      await tester.pumpAndSettle();
      expect(bus.slot(succWideSlot).value, isNull, reason: '계보 창을 열면 서랍은 닫힘');
      expect(drawerOf(tester).isOpen, isFalse);
      // 대본의 slot 걸음처럼 슬롯을 바로 써도 같음.
      bus.slot(succWideSlot).value = polityUid;
      await tester.pumpAndSettle();
      expect(bus.slot(groupTreeSlot).value, isNull);
      expect(drawerOf(tester).isOpen, isTrue);
    });

    testWidgets('좁은 폭(860 아래) · 휴대폰은 서랍 없이 — 연표도 비키지 않음', (tester) async {
      final bus = wideBus();
      await mount(tester, bus, width: 800);
      await openWide(tester, bus);
      expect(find.byKey(succWideKey), findsNothing);
      expect(drawerOf(tester).hidden, isTrue);
      expect(SuccessionDrawer.insetOn(bus), 0);
      // 휴대폰.
      SceneView.phone = true;
      addTearDown(() => SceneView.phone = false);
      final other = wideBus();
      await mount(tester, other);
      await openWide(tester, other);
      expect(find.byKey(succWideKey), findsNothing);
      expect(SuccessionDrawer.insetOn(other), 0);
    });

    testWidgets("'수준 ▾' — 지도자만 그림 · 다른 수준은 서랍을 닫고 그 수준으로 좁은 창", (tester) async {
      final bus = wideBus();
      await mount(tester, bus);
      await openWide(tester, bus);
      await tester.tap(find.widgetWithText(SheetPaperButton, '수준 ▾'));
      await tester.pumpAndSettle();
      expect(find.text('지도자만'), findsOneWidget);
      await tester.tap(find.text('모두'));
      await tester.pumpAndSettle();
      expect(bus.slot(succWideSlot).value, isNull);
      expect(bus.selection.value?.uid, polityUid);
      expect(bus.selection.value?.cell, successionCell);
      expect(bus.slot(kinLevelSlot).value, {'uid': polityUid, 'level': KinLevel.all});
    });
  });

  group('좁은 창의 넓게', () {
    testWidgets("서랍 층이 붙어 있으면 바닥에 '넓게'(닫기 앞 · 여섯이 한 줄) — 누르면 서랍이 열리고 상세 칸은 나라 상세로", (tester) async {
      final bus = wideBus();
      registerItemDetail();
      registerCellDetail();
      registerKinDetail();
      await mount(tester, bus, left: DetailHost(bus: bus, framed: false));
      bus.select(polityUid, cell: successionCell);
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final papers = tester.widgetList<SheetPaperButton>(find.byType(SheetPaperButton)).map((b) => b.label).toList();
      expect(papers, ['◀ 나라 상세', '모두 펼치기', '모두 접기', '수준 ▾', '넓게', '닫기']);
      final rects = [for (final l in papers) tester.getRect(find.widgetWithText(SheetPaperButton, l))];
      expect({for (final r in rects) r.top}, hasLength(1), reason: '여섯이 한 줄');
      expect(rects.last.right, lessThanOrEqualTo(380 - 18), reason: '상세 칸 안 폭 344 안');
      await tester.tap(find.widgetWithText(SheetPaperButton, '넓게'));
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(bus.slot(succWideSlot).value, polityUid);
      expect(drawerOf(tester).isOpen, isTrue);
      expect(bus.selection.value?.uid, polityUid);
      expect(bus.selection.value?.cell, isNull, reason: '상세 칸은 나라 상세로');
    });
  });
}

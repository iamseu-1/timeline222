import 'dart:convert';
import 'dart:math' as math;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/sheet_look.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/detail_cell.dart';
import 'package:archive_prototype/ui/detail_item.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/kin/kin_head.dart';
import 'package:archive_prototype/ui/kin/kin_record.dart';
import 'package:archive_prototype/ui/kin/kin_rows.dart';
import 'package:archive_prototype/ui/kin/succession_look.dart';
import 'package:archive_prototype/ui/kin/succession_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 승계표 창(D1-N2 — 확정 설계 3절). 자료는 **이 파일 안의 손 고정 자료**다(가상 이름 · 실제 역사 이름 없음):
// 내보내기(D1-E)의 기록 꼴(8-1 · 이음새 D1-E ①②)대로 정권 기록 · 열 꼴 뼈대 기록을 지어 엔진 `entity` 답처럼 돌려준다.
// D1-E의 고정 자료(`test/fixtures/kin-*.json`)가 들어오면 결합 때 그것으로도 돌린다.

/// 열 꼴 뼈대 기록(갈래 `kin`) — 정권 '가람 나라'(지도자 다섯: 갑 · 을 · 병 · 을(다시) · 정).
///   0 갑(지도자 0) ─ 1 을(지도자 1 · 3) ─ 2 을의 아들(계보 전용)
///                 └ 3 병(지도자 2) ─ 4 병의 딸(계보 전용 · 파조 '솔파')
///   5 정(지도자 4 · 다른 뿌리 — 관계 미상)
Map<String, Object?> garamKin() => {
  'v': 1,
  'uid': 'kin:polity:k/garam',
  'n': 6,
  'gens': 3,
  'par': [-1, 0, 1, 0, 3, -1],
  'size': [5, 2, 1, 2, 1, 1],
  'gen': [0, 1, 2, 1, 2, 0],
  'bits': [33, 33, 65, 33, 81, 33],
  'edge': [0, 0, 0, 0, 0, 0],
  'branch': [0, 0, 0, 0, 1, 0],
  'color': [1, 1, 0, 1, 0, 1],
  'color2': <int>[],
  'name': ['갑', '을', '을의 아들', '병', '병의 딸', '정'],
  'sub': ['가람 나라 1대 · 1400~1410', '가람 나라 2대 · 1410~1420', '', '가람 나라 3대 · 1420~1430', '', '가람 나라 5대 · 1440~1450'],
  'key': ['c:k/garam|leader:0', 'f:k/eul', 'f:k/eul-son', 'c:k/garam|leader:2', 'f:k/byeong-girl', 'c:k/garam|leader:4'],
  'extra': <int>[],
  'colors': ['', '#a0bcc5'],
  'branches': [
    {'uid': 'house:h-garam', 'name': '가람 왕가', 'color': '#c8b193', 'at': 0, 'up': -1},
    {'uid': 'house:h-sol', 'name': '솔파', 'color': '#b6c398', 'at': 4, 'up': 0},
  ],
  'cells': {'k/garam|leader:0': 0, 'k/garam|leader:1': 1, 'k/garam|leader:2': 3, 'k/garam|leader:3': 1, 'k/garam|leader:4': 5},
  'stubs': <String, Object?>{},
  'warnings': <String>[],
};

/// 정권 기록 — 지도자 다섯 · 이음매(관계 · 방식 · 선 갈래 · 이음매 글 · 뼈대 자리) · 머리 칩.
Map<String, Object?> garamPolity() => {
  'uid': 'k/garam',
  'name': '가람 나라',
  'color': '#a0bcc5',
  'track': 'garam',
  'leaders': [
    {'name': '갑', 'start': 1400, 'end': 1410, 'ordinal': 1},
    {'name': '을', 'start': 1410, 'end': 1420, 'ordinal': 2, 'accession': {}},
    {'name': '병', 'start': 1420, 'end': 1430, 'ordinal': 3, 'accession': {}},
    {'name': '을', 'start': 1430, 'end': 1440, 'ordinal': 4, 'accession': {}},
    {'name': '정', 'start': 1440, 'end': 1450, 'ordinal': 5, 'accession': {}},
  ],
  'x_head': [
    {'role': 'track', 'text': '가람'},
    {'role': 'people', 'text': '누리족'},
    {'role': 'name', 'text': '가람 나라', 'uid': 'k/garam'},
    {'role': 'tag', 'text': '통일 왕조'},
  ],
  'x_lineage': {
    'leader:0': {'line': 0, 'kinAt': ['kin:polity:k/garam', 0]},
    'leader:1': {'kin': '아들', 'kinId': 'son', 'how': '세습', 'howId': 'hereditary', 'fromAuto': 1, 'line': 5, 'seam': '아들 · 세습', 'kinAt': ['kin:polity:k/garam', 1]},
    'leader:2': {'kin': '동생', 'kinId': 'brother', 'how': '찬탈', 'howId': 'usurpation', 'fromAuto': 1, 'line': 1, 'seam': '동생 · 찬탈', 'kinAt': ['kin:polity:k/garam', 3]},
    'leader:3': {'kin': '형', 'kinId': 'brother', 'how': '복위', 'howId': 'restoration', 'fromAuto': 1, 'restored': 1, 'line': 4, 'seam': '형 · 복위', 'kinAt': ['kin:polity:k/garam', 1]},
    'leader:4': {'kinUnknown': 1, 'how': '추대', 'howId': 'acclaim', 'line': 2, 'seam': '관계 미상 · 추대', 'kinAt': ['kin:polity:k/garam', 5]},
  },
};

/// 엔진 `entity` 답처럼 돌려주는 버스(항목 기록은 [store]에서 — 본문은 JSON 글).
({AppBus bus, List<String> asked}) kinBus(Map<String, Map<String, Object?>> store) {
  final asked = <String>[];
  final controller = TimelineController()..resize(1920, 1000);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {'packs': [], 'tracks': [], 'epochs': []}),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('창 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(
    ask: (query) async {
      if (query['op'] != 'entity') return const {};
      final uid = query['uid'] as String;
      asked.add(uid);
      final body = store[uid];
      if (body == null) throw StateError('없는 항목 $uid');
      final kind = uid.startsWith('kin:') ? 'kin' : (body['kind'] as String? ?? 'period');
      return {'uid': uid, 'kind': kind, 'json': jsonEncode(body)};
    },
    controller: controller,
    scene: scene,
  );
  return (bus: bus, asked: asked);
}

Widget frame(Widget child, {double height = 1000}) => MaterialApp(
  home: Scaffold(
    backgroundColor: Ui.bg,
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: Ui.detailWidth, height: height, child: child),
    ),
  ),
);

/// 승계표를 띄우고 뼈대가 풀릴 때까지 기다린다.
Future<({AppBus bus, List<String> asked, KinDriver driver})> openSuccession(
  WidgetTester tester, {
  Map<String, Map<String, Object?>>? store,
  String uid = 'k/garam',
  double height = 1000,
  KinFoldMemory? memory,
}) async {
  // 1배 화면(감독 화면 1920 × 1080) — 창이 [height]만큼 서도록 화면을 넉넉히.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(1920, math.max(1080, height + 40));
  addTearDown(tester.view.reset);
  final made = kinBus(store ?? {'k/garam': garamPolity(), 'kin:polity:k/garam': garamKin()});
  registerItemDetail();
  registerCellDetail();
  registerKinDetail();
  if (memory != null) made.bus.slot('kinFold').value = memory;
  await tester.pumpWidget(frame(DetailHost(bus: made.bus, framed: false), height: height));
  made.bus.select(uid, cell: successionCell);
  await tester.pump();
  await tester.pump();
  final driver = made.bus.slot('kinDriver').value as KinDriver;
  await settleKin(tester, driver);
  return (bus: made.bus, asked: made.asked, driver: driver);
}

/// 위젯 검사의 가짜 시계는 다른 isolate를 기다리지 못한다 — 뼈대 풀기를 같은 isolate로 갈아 끼운다(작업자 isolate 풀기는 N1 검사가 본다).
void useSyncDecode() => kinDecode = (json, {uid = ''}) async => kinFromMap(jsonDecode(json) as Map<String, dynamic>, uid: uid);

/// 손잡이가 뼈대를 받아 풀 때까지 장면을 돌린다.
Future<void> settleKin(WidgetTester tester, KinDriver driver) async {
  for (var i = 0; i < 30 && !driver.ready; i++) {
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// 지도자 꼬리표(그림판 꼬리표를 줄인 이름띠)를 그리는 CustomPaint.
final tagPaint = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is SuccTagPainter);

/// 목록 안 줄 글(정확히 그 글인 Text · RichText).
Finder rowText(String text) => find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == text);

/// 목록 줄의 그리개와 전역 자리 — 지도자 꼬리표([SuccTagPainter])와 실이 지나는 줄([SuccRowPainter]의 line이 있는 것), 위에서 아래로.
List<(CustomPainter, Rect)> rowPaints(WidgetTester tester) {
  final out = <(CustomPainter, Rect)>[];
  final rows = find.byWidgetPredicate((w) => w is CustomPaint && (w.painter is SuccTagPainter || (w.painter is SuccRowPainter && (w.painter! as SuccRowPainter).line != null)));
  for (final e in rows.evaluate()) {
    final box = e.renderObject! as RenderBox;
    out.add(((e.widget as CustomPaint).painter!, box.localToGlobal(Offset.zero) & box.size));
  }
  out.sort((a, b) => a.$2.top.compareTo(b.$2.top));
  return out;
}

void expectNear(Offset a, Offset b) {
  expect(a.dx, moreOrLessEquals(b.dx));
  expect(a.dy, moreOrLessEquals(b.dy));
}

void main() {
  setUp(() {
    for (final k in detailKinds) {
      DetailHost.unregister(k.id);
    }
    useSyncDecode();
  });

  group('승계표 창 — 처음 모습(결정 1 A)', () {
    testWidgets('나라를 칸 참조 succession으로 고르면 승계표가 열린다 — 갈래 · 머리 칩 · 범례', (tester) async {
      final made = await openSuccession(tester);
      final state = made.bus.slot('detail').value as DetailState;
      expect(state.branch!.id, 'succession');
      expect(state.pick, isTrue, reason: '나라 상세와 같이 그 나라를 고른 채');
      // 머리 칩: 구분 › 민족 › 국가 이름 · 꼬리표(실려 온 글 그대로).
      expect(KinChip.line(KinChip.read(garamPolity()['x_head'])), '가람 › 누리족 › 가람 나라 · 통일 왕조');
      expect(find.text('›'), findsNWidgets(2));
      expect(find.text('·'), findsOneWidget);
      expect(find.text('지도자 5'), findsOneWidget);
      for (final t in ['세습 · 추대', '선양', '찬탈 · 정변', '관계 · 방식 미상', '복위(같은 사람)', '관계 · 방식']) {
        expect(find.text(t), findsOneWidget, reason: '범례 $t');
      }
      // 승계표 전용 범례(실 갈래 · 복위 고리 · 열쇠표 견본) — 세계표가 함께 쓰는 KinLegend는 쓰지 않는다.
      expect(find.byType(SuccLegend), findsOneWidget);
      expect(find.byType(KinLegend), findsNothing);
      // 제목 꼬리표 — 정권 색 · 제목 20 굵게 + '지도자 n' 12.
      final title = tester.widget<SuccTitleTag>(find.byType(SuccTitleTag));
      expect((title.title, title.sub, title.color), ('가람 나라', '지도자 5', const Color(0xffa0bcc5)));
      final head = tester.widget<Text>(find.descendant(of: find.byType(SuccTitleTag), matching: find.text('가람 나라'))).style!;
      expect((head.fontSize, head.fontWeight, head.color), (20.0, FontWeight.w700, SheetLook.tagInk(const Color(0xffa0bcc5))));
      expect(tester.getSize(find.byType(SuccTitleTag)).height, SuccLook.title);
      expect(made.asked.where((u) => u.startsWith('kin:')).length, 1, reason: '뼈대는 창을 열 때 한 번만 받는다');
    });

    testWidgets('처음에는 지도자만 — 카드 다섯 · 이음매 넷 · 복위 다시 딱지 · 후손 알약', (tester) async {
      // 검사 글꼴(네모 글자)은 글이 넓어 머리가 높다 — 줄이 모두 보이게 창을 키운다.
      final made = await openSuccession(tester, height: 1400);
      expect(made.driver.ready, isTrue);
      expect(made.driver.visible, ['c:k/garam|leader:0', 'c:k/garam|leader:1', 'c:k/garam|leader:2', 'c:k/garam|leader:3', 'c:k/garam|leader:4'].take(made.driver.visible.length));
      expect(made.driver.visible.length, greaterThanOrEqualTo(4));
      expect(find.text('1대'), findsOneWidget);
      expect(find.text('1400 ~ 1410'), findsOneWidget);
      expect(find.text('다시'), findsOneWidget, reason: '을이 다시 오른 4대 카드');
      expect(find.text('2대에서'), findsOneWidget); // 앞의 화살(←)은 뺐다 — 화살촉은 고리의 아래 끝(건의 8의 5번 A)
      // 후손 n: 갑의 펼침 구간에서 다른 지도자(을 · 병)의 하위는 셈하지 않는다 → 0이라 알약이 없다. 을 1명 · 병 1명.
      expect(find.text('후손 1 ▸'), findsNWidgets(2));
      // 이음매 글 — 관계는 굵게(글은 실려 온 그대로) · 복위에는 '— n대와 같은 사람'.
      expect(rowText('아들 · 세습'), findsOneWidget);
      expect(rowText('동생 · 찬탈'), findsOneWidget);
      expect(rowText('형 · 복위 — 2대와 같은 사람'), findsOneWidget);
      expect(rowText('관계 미상 · 추대'), findsOneWidget);
      // '관계 미상'은 옅게(웹 `.kv-row.is-S i` — text-3), 나머지 글은 그대로.
      final unknown = tester.widget<RichText>(rowText('관계 미상 · 추대'));
      final pieces = <String, Color?>{};
      unknown.text.visitChildren((span) {
        if (span is TextSpan && (span.text ?? '').isNotEmpty) pieces[span.text!] = span.style?.color;
        return true;
      });
      expect(pieces['관계 미상'], SheetLook.ink45);
      expect(pieces[' · 추대'], isNull, reason: '나머지는 열쇠표 글의 바탕(먹 60)');
      expect(tester.widget<RichText>(rowText('관계 미상 · 추대')).text.style?.color, SheetLook.ink60);
      expect(find.ancestor(of: rowText('관계 미상 · 추대'), matching: find.byType(SuccKeyLabel)), findsOneWidget, reason: '이음매 글은 열쇠표에');
      // 사람 줄은 아직 없다.
      expect(find.text('을의 아들'), findsNothing);
      // 아래 단추 = 흰 이름 종이(글 폭만큼 — 창 폭으로 늘어나 한 줄에 하나씩 서지 않는다) · 차례 그대로.
      expect(find.byType(DetailSmallButton), findsNothing);
      final papers = tester.widgetList<SheetPaperButton>(find.byType(SheetPaperButton)).map((b) => b.label).toList();
      expect(papers, ['◀ 나라 상세', '모두 펼치기', '모두 접기', '수준 ▾', '닫기']);
      final close = tester.getRect(find.ancestor(of: find.text('닫기'), matching: find.byType(SheetPaperButton)).first);
      expect(close.width, lessThan(80));
      expect(close.height, SheetLook.chip);
      final back = tester.getRect(find.ancestor(of: find.text('◀ 나라 상세'), matching: find.byType(SheetPaperButton)).first);
      final open = tester.getRect(find.ancestor(of: find.text('모두 펼치기'), matching: find.byType(SheetPaperButton)).first);
      expect(open.top, back.top, reason: '◀ 나라 상세 옆에 모두 펼치기');
      expect(open.left, greaterThan(back.right));
    });
  });

  group('접고 펴기 — 줄 규칙 · 0px · 기억', () {
    testWidgets('모두 펼치기: 한 사람은 한 번 · 다른 지도자는 건너뛰기 줄 · 줄 수 ≤ 사람 + 지도자', (tester) async {
      final made = await openSuccession(tester, height: 1400);
      made.driver.expandAll();
      await tester.pumpAndSettle();
      final keys = made.driver.visible;
      expect(keys.toSet().length, keys.length, reason: '한 사람은 한 번만');
      // 갑 카드 아래: 을(다른 지도자) → 건너뛰기, 병 → 건너뛰기. 을 카드 아래: 을의 아들. 병 카드 아래: 병의 딸.
      expect(find.text('→ 2대 을'), findsOneWidget);
      expect(find.text('→ 3대 병'), findsOneWidget);
      expect(find.text('을의 아들'), findsOneWidget);
      expect(find.text('병의 딸'), findsOneWidget);
      expect(keys.where((k) => !k.startsWith('c:k/garam|leader:')).length, lessThanOrEqualTo(6), reason: '사람 + 지도자를 넘지 않는다');
      // 파조 알약.
      expect(find.text('솔파 · 1명'), findsOneWidget, reason: '자식 없는 파조는 펼 것이 없어 ▸ · ▾가 없다');
    });

    testWidgets('카드를 펴도 그 카드는 화면에서 0px 움직인다 · 다시 접으면 처음과 같다', (tester) async {
      final made = await openSuccession(tester);
      final card = find.text('병');
      final before = tester.getTopLeft(card.first);
      expect(made.driver.toggle('c:k/garam|leader:2'), isTrue);
      await tester.pump();
      expect(tester.getTopLeft(card.first), before, reason: '누른 줄은 0px');
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(card.first), before);
      expect(find.text('병의 딸'), findsOneWidget);
      // 아래 카드는 사람 줄 하나(28px)만큼 내려갔다.
      expect(made.driver.toggle('c:k/garam|leader:2'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('병의 딸'), findsNothing);
      expect(tester.getTopLeft(card.first), before);
    });

    testWidgets('펼친 줄은 카드와 이음매 사이에 든다 — 꼬리표 40 · 사람 줄 28 · 이음매 22', (tester) async {
      final made = await openSuccession(tester);
      made.driver.toggle('c:k/garam|leader:1');
      await tester.pumpAndSettle();
      final card = tester.getRect(find.ancestor(of: find.text('을').first, matching: tagPaint).first);
      final row = tester.getRect(find.text('을의 아들'));
      final seam = tester.getRect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == '동생 · 찬탈'));
      expect((kKinRowCard, kKinRowSeam, kKinRowLine), (40, 22, 28));
      expect(SuccLook.head + SuccLook.floor, kKinRowCard, reason: '꼬리표 = 머리 24 + 흰 층 16');
      expect(card.height, 40);
      expect(row.top, greaterThan(card.bottom - 1));
      expect(seam.top, greaterThan(row.bottom - 1), reason: '이음매(을 → 병)는 펼친 줄 아래');
    });

    testWidgets('접힘은 기억에 안정 열쇠로 남고, 다시 열면 되살아난다', (tester) async {
      final memory = KinFoldMemory();
      final made = await openSuccession(tester, memory: memory);
      made.driver.toggle('c:k/garam|leader:1');
      await tester.pumpAndSettle();
      expect(memory.read('k/garam'), {'f:k/eul'});
      made.bus.clearSelection();
      await tester.pumpAndSettle();
      final again = await openSuccession(tester, memory: memory);
      expect(find.text('을의 아들'), findsOneWidget, reason: '기억한 펼침');
      again.driver.collapseAll();
      await tester.pumpAndSettle();
      expect(memory.read('k/garam'), isEmpty);
    });

    testWidgets('복위 카드는 처음 카드에서만 펼친다', (tester) async {
      final made = await openSuccession(tester);
      expect(made.driver.toggle('c:k/garam|leader:3'), isFalse);
    });
  });

  group('키보드 · 창 잇기', () {
    testWidgets('↓ → Space Enter — 창의 키가 연표 전역 키보다 먼저', (tester) async {
      final made = await openSuccession(tester);
      await tester.tap(find.text('1400 ~ 1410'));
      await tester.pumpAndSettle();
      // 카드를 누르면 칸 창이 열린다(그 칸 창에는 '◀ 승계표').
      final sel = made.bus.selection.value!;
      expect(sel.cell, 'leader:0');
      expect(find.text('◀ 승계표'), findsOneWidget);
      await tester.tap(find.text('◀ 승계표'));
      await tester.pumpAndSettle();
      await settleKin(tester, made.bus.slot('kinDriver').value as KinDriver);
      expect(find.text('지도자 5'), findsOneWidget);
      // 키보드: 목록에 초점을 주고 ↓ ↓ → (을 카드 펴기).
      final focus = tester.widgetList<Focus>(find.byType(Focus)).firstWhere((f) => f.focusNode?.debugLabel == '승계표').focusNode!;
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('을의 아들'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('을의 아들'), findsNothing);
    });

    testWidgets('칸 창의 승계표에서 보기 — 그 카드를 펼친 채 데려간다', (tester) async {
      final made = await openSuccession(tester);
      made.bus.select('k/garam', cell: 'leader:2');
      await tester.pumpAndSettle();
      expect(find.text('승계표에서 보기'), findsOneWidget);
      await tester.tap(find.text('승계표에서 보기'));
      await tester.pump();
      await tester.pump();
      await settleKin(tester, made.bus.slot('kinDriver').value as KinDriver);
      expect(find.text('병의 딸'), findsOneWidget);
    });
  });

  group('그리는 수 — 보이지 않는 줄은 짓지 않는다(6-2)', () {
    testWidgets('후손 2,000명을 모두 펼쳐도 지은 줄 ≤ 50', (tester) async {
      const extra = 2000;
      final kin = garamKin();
      // 갑의 첫 자식으로 계보 전용 2,000명(한 세대)을 더 끼운다 — 앞 차례 번호가 밀리므로 열을 다시 짓는다.
      final names = ['갑', for (var i = 0; i < extra; i++) '후손 $i', ...(kin['name'] as List).skip(1).cast<String>()];
      final keys = ['c:k/garam|leader:0', for (var i = 0; i < extra; i++) 'f:k/d$i', ...(kin['key'] as List).skip(1).cast<String>()];
      List<int> shiftPar(List<int> par) => [-1, for (var i = 0; i < extra; i++) 0, ...par.skip(1).map((p) => p <= 0 ? p : p + extra)];
      final big = {
        ...kin,
        'n': 6 + extra,
        'par': shiftPar((kin['par'] as List).cast<int>()),
        'size': [5 + extra, for (var i = 0; i < extra; i++) 1, ...(kin['size'] as List).skip(1).cast<int>()],
        'gen': [0, for (var i = 0; i < extra; i++) 1, ...(kin['gen'] as List).skip(1).cast<int>()],
        'bits': [33, for (var i = 0; i < extra; i++) 65, ...(kin['bits'] as List).skip(1).cast<int>()],
        'edge': List.filled(6 + extra, 0),
        'branch': [0, for (var i = 0; i < extra; i++) 0, ...(kin['branch'] as List).skip(1).cast<int>()],
        'color': [1, for (var i = 0; i < extra; i++) 0, ...(kin['color'] as List).skip(1).cast<int>()],
        'name': names,
        'sub': List.filled(6 + extra, ''),
        'key': keys,
        'branches': [
          {'uid': 'house:h-garam', 'name': '가람 왕가', 'color': '#c8b193', 'at': 0, 'up': -1},
          {'uid': 'house:h-sol', 'name': '솔파', 'color': '#b6c398', 'at': 4 + extra, 'up': 0},
        ],
        'cells': {'k/garam|leader:0': 0, 'k/garam|leader:1': 1 + extra, 'k/garam|leader:2': 3 + extra, 'k/garam|leader:3': 1 + extra, 'k/garam|leader:4': 5 + extra},
      };
      final polity = garamPolity();
      final lin = <String, Object?>{};
      (polity['x_lineage'] as Map).forEach((k, v) {
        final a = (v as Map).cast<String, Object?>();
        final at = (a['kinAt'] as List)[1] as int;
        lin['$k'] = {...a, 'kinAt': ['kin:polity:k/garam', at == 0 ? 0 : at + extra]};
      });
      polity['x_lineage'] = lin;
      final made = await openSuccession(tester, store: {'k/garam': polity, 'kin:polity:k/garam': big});
      made.driver.expandAll();
      await tester.pumpAndSettle();
      expect(find.text('후손 0'), findsOneWidget);
      expect(made.driver.built, lessThanOrEqualTo(50), reason: '지은 줄 ${made.driver.built}');
      // 끝까지 밀어도 지은 줄은 그대로 적다.
      for (var k = 0; k < 20; k++) {
        made.driver.panBy(0, 3000);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(made.driver.built, lessThanOrEqualTo(50));
      expect(find.text('5대'), findsOneWidget, reason: '맨 끝 카드까지 닿는다');
      // 끝에 닿으면 목록 높이가 어림이 아니라 줄 높이의 합 — 측정 대본(`lib/measure` — kinRowTops)이 셈하는 높이(꼬리표 40 · 이음매 22 ·
      // 사람 줄 28)와 같다(+ 아래 옅어짐 28).
      final skel = kinFromMap(big.cast<String, dynamic>(), uid: 'kin:polity:k/garam');
      final spots = [for (var m = 0; m < 5; m++) KinLeaderSpot(skel, skel.locate(((lin['leader:$m'] as Map)['kinAt'] as List)[1] as int).at)];
      final total = kinRowTops(kinRows(spots, kinLevelOpen(spots, KinLevel.all)), spots.length).last;
      final position = tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!.position;
      expect(position.pixels, position.maxScrollExtent);
      expect(position.maxScrollExtent + position.viewportDimension, total + 28);
    });
  });

  // 리메이크 4단계 틀의 시트와 창 걸음 6 — 감독 고름 G5 #9(서고로 다시 그림 · 좁은 창은 위에서 아래로).
  group('서고 꼴 — 이름띠 · 실 · 열쇠표', () {
    test('이음매 여섯의 실 꼴 — 이은 실 · 겹실 · 끊긴 실 + 빗금 · 점 실 · 옅은 실(먹 25) · 복위는 이은 실(고리는 오른쪽 통로)', () {
      const x = SuccLook.threadX, h = SuccLook.thread / 2;
      SuccThread t(int line) => SuccThread.of(line, at: x, a: 0, b: 22);
      final solid = t(SeamLine.solid);
      expect(solid.bars, [const Rect.fromLTRB(x - h, 0, x + h, 22)]);
      expect((solid.slashes.length, solid.dots.length, solid.color), (0, 0, SheetLook.ink45));
      expect(t(SeamLine.restore).bars, solid.bars, reason: '복위의 왼쪽 실은 이은 실');
      final twin = t(SeamLine.abdicate);
      expect(twin.bars, [const Rect.fromLTRB(x - 2 - h, 0, x - 2 + h, 22), const Rect.fromLTRB(x + 2 - h, 0, x + 2 + h, 22)], reason: '선양 = 겹실(가운데에서 ±2)');
      final usurp = t(SeamLine.usurp);
      expect(usurp.bars, [const Rect.fromLTRB(x - h, 0, x + h, 8), const Rect.fromLTRB(x - h, 14, x + h, 22)], reason: '찬탈 · 정변 = 가운데 6을 끊음(길이의 26%)');
      expect(usurp.slashes, [(const Offset(x - 4, 14), const Offset(x + 4, 8))], reason: '빗금은 끊긴 틈을 아래 왼쪽 → 위 오른쪽으로');
      final unknown = t(SeamLine.unknown);
      expect(unknown.bars, isEmpty);
      expect(unknown.dots.map((d) => d.dx).toSet(), {x});
      expect(unknown.dots.map((d) => d.dy).toList(), [1.5, 5.5, 9.5, 13.5, 17.5], reason: '관계 · 방식 미상 = 점 실(4마다)');
      final blank = t(SeamLine.blank);
      expect(blank.bars, solid.bars);
      expect(blank.color, SheetLook.ink25, reason: '비움 = 옅은 실');
      // 가로 꼴(넓은 창 · 범례)도 같은 꼴을 눕힌 것.
      final flat = SuccThread.of(SeamLine.usurp, at: 6.5, a: 0, b: 22, vertical: false);
      expect(flat.bars, [const Rect.fromLTRB(0, 6.5 - h, 8, 6.5 + h), const Rect.fromLTRB(14, 6.5 - h, 22, 6.5 + h)]);
    });

    testWidgets('이음매 줄마다 그 갈래의 실 · 열쇠표 — 비움은 옅은 실만(열쇠표 없음) · 꼬리표 안 실 토막도 옅게', (tester) async {
      final polity = garamPolity();
      final lin = Map<String, Object?>.of((polity['x_lineage'] as Map).cast<String, Object?>());
      polity['x_lineage'] = lin;
      lin['leader:1'] = {...(lin['leader:1'] as Map).cast<String, Object?>(), 'line': 3, 'how': '선양', 'seam': '아들 · 선양'};
      lin['leader:4'] = {'line': 0, 'kinAt': ['kin:polity:k/garam', 5]};
      await openSuccession(tester, height: 1400, store: {'k/garam': polity, 'kin:polity:k/garam': garamKin()});
      final seams = rowPaints(tester).where((p) => p.$1 is SuccRowPainter && (p.$1 as SuccRowPainter).line != null).toList();
      expect([for (final s in seams) (s.$1 as SuccRowPainter).line], [SeamLine.abdicate, SeamLine.usurp, SeamLine.restore, SeamLine.blank]);
      expect([for (final s in seams) (s.$1 as SuccRowPainter).keyThread], [true, true, true, false], reason: '비움은 글이 없어 열쇠표 · 45° 실이 없다');
      expect(find.byType(SuccKeyLabel), findsNWidgets(3));
      final cards = rowPaints(tester).where((p) => p.$1 is SuccTagPainter).map((p) => p.$1 as SuccTagPainter).toList();
      expect([for (final c in cards) (c.threadIn, c.threadOut)], [
        (null, SeamLine.abdicate),
        (SeamLine.abdicate, SeamLine.usurp),
        (SeamLine.usurp, SeamLine.restore),
        (SeamLine.restore, SeamLine.blank),
        (SeamLine.blank, null),
      ]);
      final last = cards.last.stubs(const Size(300, 40)).single;
      expect(last.color, SheetLook.ink25, reason: '비움 이음매로 드는 실 토막은 옅게');
    });

    testWidgets('마름모 → 구멍 — 앞 꼬리표 아랫변 왼쪽의 마름모에서 다음 꼬리표의 구멍까지 같은 x로 끊김 없이(펼친 줄을 지나도)', (tester) async {
      final made = await openSuccession(tester, height: 1400);
      made.driver.toggle('c:k/garam|leader:1');
      made.driver.toggle('c:k/garam|leader:2');
      await tester.pumpAndSettle();
      expect(find.text('을의 아들'), findsOneWidget);
      final rows = rowPaints(tester);
      final cardAt = [for (var i = 0; i < rows.length; i++) if (rows[i].$1 is SuccTagPainter) i];
      expect(cardAt.length, 5);
      for (var k = 0; k + 1 < cardAt.length; k++) {
        final a = rows[cardAt[k]], b = rows[cardAt[k + 1]];
        final from = succDiamondBelow(a.$2), to = succHoleAt(b.$2);
        // 마름모는 구멍과 같은 x · 흰 층(머리 24 아래) 안 · 아랫테에서 6 위.
        expect(from.dx, succHoleAt(a.$2).dx);
        expect(from.dy, a.$2.bottom - 6.5);
        expect(from.dy, greaterThan(a.$2.top + SuccLook.head));
        expect(to.dx, from.dx, reason: '실은 곧게 내려간다');
        // 꼬리표 안 토막: 마름모 → 아랫변 · 윗변 → 구멍 위 끝.
        final out = (a.$1 as SuccTagPainter).stubs(a.$2.size).last.bars.single.shift(a.$2.topLeft);
        final inn = (b.$1 as SuccTagPainter).stubs(b.$2.size).first.bars.single.shift(b.$2.topLeft);
        expect((out.center.dx, out.top, out.bottom), (from.dx, from.dy, a.$2.bottom));
        expect((inn.center.dx, inn.top, inn.bottom), (to.dx, b.$2.top, to.dy - SheetLook.holeRadius));
        // 사이 줄(펼친 사람 줄 · 이음매)마다 같은 x의 실이 줄 키 전체로 — 줄 사이 틈 없음.
        var y = a.$2.bottom;
        for (var r = cardAt[k] + 1; r < cardAt[k + 1]; r++) {
          final (painter, rect) = rows[r];
          expect(rect.top, moreOrLessEquals(y), reason: '줄은 틈 없이 이어진다');
          final thread = (painter as SuccRowPainter).threadOf(rect.size)!;
          final xs = {...thread.bars.map((q) => q.center.dx), ...thread.dots.map((d) => d.dx)};
          if (painter.line != SeamLine.abdicate) expect(xs.map((v) => v + rect.left).toSet(), {to.dx}, reason: '줄 $r의 실 x');
          final ys = [...thread.bars.expand((q) => [q.top, q.bottom]), ...thread.dots.map((d) => d.dy)];
          expect(ys.reduce(math.min), lessThanOrEqualTo(1.5));
          expect(ys.reduce(math.max), greaterThanOrEqualTo(rect.height - 4.5), reason: '줄 $r의 실이 줄 끝까지');
          y = rect.bottom;
        }
        expect(y, moreOrLessEquals(b.$2.top));
      }
    });

    testWidgets('열쇠표 — 실 옆(꼬리표 왼쪽 19) · 다음 꼬리표 윗변 1 위 · 꼬리표 · 글자와 겹치지 않음 · 45° 실', (tester) async {
      final made = await openSuccession(tester, height: 1400);
      made.driver.expandAll();
      await tester.pumpAndSettle();
      final rows = rowPaints(tester);
      final cards = [for (final r in rows) if (r.$1 is SuccTagPainter) r.$2];
      final keys = tester.widgetList<SuccKeyLabel>(find.byType(SuccKeyLabel)).map((w) => tester.getRect(find.byWidget(w))).toList();
      expect(keys.length, 4);
      // 꼬리표 안 글 · 사람 띠 · 건너뛰기 종이의 글(열쇠표 안 글은 빼고).
      final texts = [
        for (final e in find.byType(RichText).evaluate())
          if (find.ancestor(of: find.byWidget(e.widget), matching: find.byType(SuccKeyLabel)).evaluate().isEmpty) tester.getRect(find.byWidget(e.widget)),
      ].where((r) => r.top >= cards.first.top && r.bottom <= cards.last.bottom + 1).toList();
      expect(texts, isNotEmpty);
      for (final k in keys) {
        final next = cards.firstWhere((c) => c.top >= k.bottom);
        expect(next.top - k.bottom, moreOrLessEquals(SuccLook.keyBelow), reason: '다음 꼬리표 윗변 1 위');
        expect(k.left - next.left, moreOrLessEquals(SuccLook.keyLeft), reason: '실(7.5) 옆 — 꼬리표 왼쪽 19');
        expect(k.height, SuccLook.keyBox);
        for (final c in cards) {
          expect(k.overlaps(c), isFalse, reason: '열쇠표 $k가 꼬리표 $c와 겹침');
        }
        for (final t in texts) {
          expect(k.overlaps(t), isFalse, reason: '열쇠표 $k가 글 $t와 겹침');
        }
        // 45° 실: 다음 꼬리표 윗변(반 픽셀)에서 열쇠표 구멍(왼쪽 6.5 · 가운데)까지.
        final seam = rows.firstWhere((r) => r.$2.bottom == next.top && r.$1 is SuccRowPainter);
        expect((seam.$1 as SuccRowPainter).keyThread, isTrue);
        final (a, b) = succKeyThread(seam.$2.height);
        final ga = a + seam.$2.topLeft, gb = b + seam.$2.topLeft;
        expect(ga.dy, moreOrLessEquals(next.top + .5));
        expectNear(gb, k.topLeft + SheetKeyLabel.shape.holeAt!);
        expect(((gb.dx - ga.dx) - (ga.dy - gb.dy)).abs(), lessThanOrEqualTo(1.5), reason: '45°');
      }
    });

    testWidgets('복위 고리 — 오른쪽 통로(꼬리표 오른쪽 30)에서 처음 카드부터 다시 오른 카드까지 · 다시 오른 카드 테에 매듭', (tester) async {
      await openSuccession(tester, height: 1400);
      final loops = <(List<SuccLoop>, Rect, RenderObject)>[];
      for (final e in find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter is SuccRowPainter).evaluate()) {
        final w = e.widget as CustomPaint;
        loops.add(((w.foregroundPainter! as SuccRowPainter).loops, tester.getRect(find.byWidget(w)), e.renderObject!));
      }
      loops.sort((a, b) => a.$2.top.compareTo(b.$2.top));
      // 을(2대) 카드 · 이음매 · 병(3대) 카드 · 이음매 · 을(4대 — 다시) 카드.
      expect([for (final l in loops) l.$1], [
        [SuccLoop.start],
        [SuccLoop.mid],
        [SuccLoop.mid],
        [SuccLoop.mid],
        [SuccLoop.end],
      ]);
      final cards = rowPaints(tester).where((p) => p.$1 is SuccTagPainter).map((p) => p.$2).toList();
      expect(loops.first.$2.top, cards[1].top);
      expect(loops.last.$2.top, cards[3].top);
      for (final c in cards) {
        expect(loops.first.$2.right - c.right, SuccLook.lane, reason: '꼬리표 오른쪽은 통로 30을 비운다');
      }
      final w = loops.last.$2.width, tagRight = w - SuccLook.lane;
      bool knot(Symbol method, List<dynamic> args) => method == #drawCircle && args[1] == SuccLook.knot;
      expect(loops.last.$3, paints..something((m, a) => knot(m, a) && a[0] == Offset(tagRight + 1.5, SuccLook.loopY)), reason: '다시 오른 카드 테에 매듭');
      expect(loops.first.$3, isNot(paints..something(knot)), reason: '매듭은 끝(다시 오른 카드)에만');
    });

    testWidgets('꼬리표 머리 · 흰 층 — 구멍 · 대수 · 이름(머리) · 해(층) · 작은 흰 종이(다시 · n대에서 · 후손 n ▸)', (tester) async {
      await openSuccession(tester, height: 1400);
      final card = tester.getRect(find.ancestor(of: find.text('갑'), matching: tagPaint).first);
      final head = Rect.fromLTRB(card.left, card.top, card.right, card.top + SuccLook.head);
      final floor = Rect.fromLTRB(card.left, card.top + SuccLook.head, card.right, card.bottom);
      for (final t in ['1대', '갑']) {
        expect(head.contains(tester.getRect(find.text(t)).center), isTrue, reason: '$t는 머리에');
      }
      expect(floor.contains(tester.getRect(find.text('1400 ~ 1410')).center), isTrue, reason: '해는 흰 층에');
      final name = tester.widget<Text>(find.text('갑')).style!;
      expect((name.fontSize, name.fontWeight), (SuccLook.nameText, FontWeight.w700));
      expect(tester.widget<Text>(find.text('1대')).style!.fontSize, SuccLook.ordText);
      expect(tester.widget<Text>(find.text('1400 ~ 1410')).style!.fontSize, SuccLook.yearText);
      expect(tester.getRect(find.text('1대')).left - card.left, SuccLook.lead, reason: '글은 구멍 뒤 14부터');
      for (final t in ['다시', '2대에서', '후손 1 ▸']) {
        final paper = tester.getRect(find.ancestor(of: find.text(t).first, matching: find.byType(SuccPaper)).first);
        expect(paper.height, SuccLook.paper, reason: '$t = 작은 흰 종이 14');
        final owner = tester.getRect(find.ancestor(of: find.text(t).first, matching: tagPaint).first);
        expect(paper.top - owner.top, (SuccLook.head - SuccLook.paper) / 2, reason: '$t는 머리 가운데');
        expect(owner.right - paper.right, greaterThanOrEqualTo(SuccLook.headRight - .01), reason: '$t는 꼬리표 안');
      }
      // 칠 = 정권 색 24% · 테 84% + 먹(그림판 꼬리표와 같은 셈).
      final painter = tester.widget<CustomPaint>(find.ancestor(of: find.text('갑'), matching: tagPaint).first).painter! as SuccTagPainter;
      expect(painter.color, const Color(0xffa0bcc5));
    });

    testWidgets('펼친 사람 줄 = 들여쓴 흰 사람 띠(둥근 끝 · 구멍) · 건너뛰기 = 흰 종이 · 파조 = 파 색 꼬리표 — 실 통로 밖', (tester) async {
      final made = await openSuccession(tester, height: 1400);
      made.driver.expandAll();
      await tester.pumpAndSettle();
      final list = made.driver.area!;
      final band = tester.widget<SheetTag>(find.ancestor(of: find.text('을의 아들'), matching: find.byType(SheetTag)).first);
      expect((band.shape.kind, band.shape.fill, band.shape.stroke, band.shape.hole), (SheetTagKind.key, SheetLook.paper, SheetLook.ink45, true));
      final bandRect = tester.getRect(find.ancestor(of: find.text('을의 아들'), matching: find.byType(SheetTag)).first);
      expect(bandRect.height, SuccLook.band);
      expect(bandRect.left - list.left - 18, SuccLook.indentBase + kinRowIndent(1) + SuccLook.toggle, reason: '깊이 1 = 들여쓰기 14 + ▸ 칸 14');
      expect(bandRect.left - list.left - 18, greaterThan(SuccLook.threadX + 10), reason: '지나는 실(7.5)과 떨어져');
      final skip = tester.widget<SheetTag>(find.ancestor(of: find.text('→ 2대 을'), matching: find.byType(SheetTag)).first);
      expect(skip.shape, SheetPaperButton.shapeOf());
      final branch = tester.widget<SuccBranchTag>(find.ancestor(of: find.text('솔파 · 1명'), matching: find.byType(SuccBranchTag)));
      expect(branch.color, const Color(0xffb6c398));
    });
  });
}

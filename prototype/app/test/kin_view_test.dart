import 'dart:convert';
import 'dart:math' as math;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/app_memory.dart';
import 'package:archive_prototype/ui/detail_cell.dart';
import 'package:archive_prototype/ui/detail_item.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/kin/kin_head.dart';
import 'package:archive_prototype/ui/kin/kin_record.dart';
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

/// 목록 안 줄 글(정확히 그 글인 Text · RichText).
Finder rowText(String text) => find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == text);

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
      for (final t in ['세습 · 추대', '선양', '찬탈 · 정변', '관계 · 방식 미상', '복위(같은 사람)']) {
        expect(find.text(t), findsOneWidget, reason: '범례 $t');
      }
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
      expect(pieces['관계 미상'], Ui.text3);
      expect(pieces[' · 추대'], isNot(Ui.text3));
      // 사람 줄은 아직 없다.
      expect(find.text('을의 아들'), findsNothing);
      // 아래 단추는 글 폭만큼(웹 `.btn-sm`) — 창 폭으로 늘어나 한 줄에 하나씩 서지 않는다.
      final close = tester.getRect(find.ancestor(of: find.text('닫기'), matching: find.byType(AnimatedContainer)).first);
      expect(close.width, lessThan(80));
      final back = tester.getRect(find.ancestor(of: find.text('◀ 나라 상세'), matching: find.byType(AnimatedContainer)).first);
      final open = tester.getRect(find.ancestor(of: find.text('모두 펼치기'), matching: find.byType(AnimatedContainer)).first);
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

    testWidgets('펼친 줄은 카드와 이음매 사이에 든다 — 카드 34 · 사람 줄 28 · 이음매 22', (tester) async {
      final made = await openSuccession(tester);
      made.driver.toggle('c:k/garam|leader:1');
      await tester.pumpAndSettle();
      final card = tester.getRect(find.ancestor(of: find.text('을').first, matching: find.byType(Container)).first);
      final row = tester.getRect(find.text('을의 아들'));
      final seam = tester.getRect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == '동생 · 찬탈'));
      expect(card.height, 34);
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
    });
  });
}

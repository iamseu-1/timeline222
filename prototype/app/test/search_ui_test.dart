import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/search_results.dart';
import 'package:archive_prototype/shell/sheet_look.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/search.dart';
import 'package:archive_prototype/ui/search_parse.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 찾기 부품(lib/ui/search.dart)의 검사. 자료 처리부 대신 가짜 ask를 두고 돌린다 —
// 견본은 results/compat/moonwake-layout3.json의 entities에서 뽑아 test/fixtures/search-sample.json에 담았다(이름은 모두 가상).
// 확인하는 것 — 낱말 · 날짜 · 간지의 목록과 차례 · 60건까지 · 검색 강조 · 고르면 **창이 먼저, 이동이 나중** · 키보드.

/// 견본 한 줄.
typedef SampleRow = Map<String, Object?>;

class _Fake {
  _Fake() {
    final file = File('test/fixtures/search-sample.json');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    extent = data['extent'] as Map<String, dynamic>;
    rows = [for (final row in data['rows'] as List) Map<String, Object?>.from(row as Map)];
  }

  late final List<SampleRow> rows;
  late final Map<String, dynamic> extent;

  /// 물어본 것을 모아 둔다(무엇을 얼마나 묻는지도 검사한다).
  final asked = <Map<String, dynamic>>[];

  /// 'ganji_years'를 모르는 자료 처리부 흉내.
  bool knowsGanji = true;

  /// 있는 것보다 많이 찾은 척(60건 넘음).
  int pad = 0;

  Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async {
    asked.add(query);
    switch (query['op']) {
      case 'search':
        final kinds = (query['kinds'] as List).cast<String>();
        final terms = (query['text'] as String).toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
        final hit = [
          for (final row in rows)
            if (kinds.contains(row['kind']) && terms.every((t) => (row['hay'] as String).contains(t))) row,
        ];
        for (int i = 0; i < pad; i++) {
          hit.add({...rows.first, 'uid': '견본/덧-$i', 'name': '덧붙인 줄 $i', 'start': (rows.first['start'] as num) + i});
        }
        return {'items': hit, 'has_more': false};
      case 'search_year':
        final t = query['t'] as int, end = query['end'] as int;
        final kinds = (query['kinds'] as List).cast<String>();
        return {
          'items': [
            for (final row in rows)
              if (kinds.contains(row['kind']) && (row['start'] as num) <= end && (row['end'] as num) >= t) row,
          ],
          'has_more': false,
        };
      case 'ganji_years':
        if (!knowsGanji) throw StateError('알 수 없는 조회 명령');
        return {
          'years': ganjiYears(
            query['ganji'] as String,
            center: query['center'] as int,
            lo: query['lo'] as int,
            hi: query['hi'] as int,
            limit: query['limit'] as int,
          ),
        };
      default:
        throw StateError('알 수 없는 조회 명령: ${query['op']}');
    }
  }
}

/// 가짜 ask 하나를 단 길. 연표는 견본의 범위만큼 벌려 두고 100년쯤 보고 있다.
(AppBus, _Fake) makeBus() {
  final fake = _Fake();
  final controller = TimelineController()
    ..resize(1920, 800)
    ..setExtent(fake.extent['lo'] as num, fake.extent['hi'] as num)
    ..setContentHeight(600);
  controller.showRange(minuteOf(1850), minuteOf(1950));
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {'packs': [], 'tracks': [], 'epochs': []}),
    fetchTile: (level, x, chunk, packs) async => Uint8List(0),
    labelCompute: (input) async => throw StateError('이 검사는 이름 자리를 셈하지 않는다'),
  );
  return (AppBus(ask: fake.ask, controller: controller, scene: scene), fake);
}

Future<void> pumpPanel(WidgetTester tester, AppBus bus, SearchController search) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SearchPanel(bus: bus, controller: search, withField: true, autofocus: true),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('낱말을 치면 맞은 줄과 건수가 뜬다', (tester) async {
    final (bus, fake) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '유리항');
    await tester.pumpAndSettle();

    expect(search.hits, isNotEmpty);
    expect(search.hits.map((h) => h.name), contains('유리항 패총국'));
    expect(search.hits.every((h) => h.uid.isNotEmpty), isTrue);
    // 건수는 폴더 탭의 수(서고 꼴 — '찾음 · 〈찾는 말〉 〈수〉'), 안내 글이 '〈수〉건 찾음' 하나뿐이면 시트에 따로 두지 않는다.
    expect(find.text('찾음 · 유리항'), findsOneWidget);
    expect(search.note, '${search.hits.length}건 찾음');
    expect(find.text(search.countText), findsOneWidget);
    expect(find.textContaining('건 찾음'), findsNothing);
    expect(find.text('유리항 패총국'), findsOneWidget);
    expect(fake.asked.first['op'], 'search');
    expect(fake.asked.first['kinds'], contains('cell'));
  });

  testWidgets('맞는 것이 없으면 그렇게 적는다', (tester) async {
    final (bus, _) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '없는이름');
    await tester.pumpAndSettle();
    expect(find.text('일치하는 항목이 없습니다'), findsOneWidget);
    expect(bus.slot('searchHits').value, isNull);
  });

  testWidgets('차례는 간지 해 → 항목(시작 오름차순) → 칸 → 가문', (tester) async {
    final (bus, _) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '은결');
    await tester.pumpAndSettle();

    final kinds = search.hits.map((h) => h.kind).toList();
    expect(kinds, contains('cell'));
    expect(kinds.indexOf('cell'), lessThan(kinds.indexOf('house')));
    final cells = search.hits.where((h) => h.kind == 'cell').toList();
    for (int i = 1; i < cells.length; i++) {
      expect(cells[i].start, greaterThanOrEqualTo(cells[i - 1].start));
    }
  });

  testWidgets('60건까지만 그린다', (tester) async {
    final (bus, fake) = makeBus();
    fake.pad = 80;
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '유리항');
    await tester.pumpAndSettle();

    expect(search.hits.length, 60);
    expect(search.note, contains('앞의 60건만 표시'));
  });

  testWidgets('검색 강조는 항목과 칸의 정권 uid만 담는다', (tester) async {
    final (bus, _) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '은결');
    await tester.pumpAndSettle();
    final uids = bus.slot('searchHits').value! as List<String>;
    expect(uids, contains('moonwake-chronicle/p-coast-0'));
    expect(uids.any((u) => u.startsWith('house:')), isFalse);
    expect(uids.toSet().length, uids.length);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(bus.slot('searchHits').value, isNull, reason: '검색어를 비우면 창의 조명 강조가 되살아나게 비워 둔다');
  });

  testWidgets('날짜를 치면 맨 위에 이동 줄이 서고 그때에 걸친 항목도 함께 나온다', (tester) async {
    final (bus, fake) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '기원전 900년');
    await tester.pumpAndSettle();

    expect(search.hits.first.kind, 'date');
    expect(find.text('기원전 900년(으)로'), findsOneWidget);
    expect(fake.asked.any((q) => q['op'] == 'search_year'), isTrue);
    expect(search.hits.any((h) => h.kind == 'period'), isTrue, reason: '그때에 걸친 정권');
    expect(search.hits.any((h) => h.kind == 'cell'), isFalse, reason: '날짜 검색이면 칸은 묻지 않는다');
  });

  testWidgets('간지를 치면 보기 가운데에 가까운 해부터 나온다', (tester) async {
    final (bus, _) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '갑오년');
    await tester.pumpAndSettle();

    expect(search.hits.first.kind, 'ganji');
    expect(search.hits.first.name, '1894년 · 갑오년');
    expect(search.note, contains('60년마다 돌아옵니다'));
  });

  testWidgets('간지 명령이 아직 없으면 연표 범위로 스스로 센다', (tester) async {
    final (bus, fake) = makeBus();
    fake.knowsGanji = false;
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '갑오');
    await tester.pumpAndSettle();
    expect(search.hits.first.name, '1894년 · 갑오년');
  });

  testWidgets('항목을 고르면 창이 먼저 열리고 그다음에 이동한다', (tester) async {
    final (bus, _) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    final order = <String>[];
    bus.selection.addListener(() => order.add('고르기'));
    bus.go.addListener(() => order.add('가기'));
    await pumpPanel(tester, bus, search);

    // 친 글과 줄의 글이 같으면 누를 곳이 둘이 되므로 짧게 친다.
    await tester.enterText(find.byType(TextField), '패총국');
    await tester.pumpAndSettle();
    await tester.tap(find.text('유리항 패총국'));
    await tester.pump();

    expect(order, ['고르기', '가기']);
    expect(bus.selection.value!.uid, 'moonwake-chronicle/p-coast-0');
    expect(bus.selection.value!.cell, isNull);
    final go = bus.go.value!;
    expect(go.ring, 'moonwake-chronicle/p-coast-0');
    expect(go.row, 1);
    expect(go.hi - go.lo, closeTo((-1245972960 - -1540504800) * 2.2, 1), reason: '기간의 2.2배');
    expect(search.showResults, isFalse, reason: '고르면 목록을 닫는다');
  });

  testWidgets('칸을 고르면 정권 창이 아니라 칸 창이 열린다', (tester) async {
    final (bus, _) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '레나나');
    await tester.pumpAndSettle();
    final at = search.hits.indexWhere((h) => h.kind == 'cell');
    expect(at, isNonNegative);
    search.activate(at);

    expect(bus.selection.value!.uid, 'moonwake-chronicle/p-coast-0');
    expect(bus.selection.value!.cell, 'leader:1');
    expect(bus.go.value!.hi - bus.go.value!.lo, lessThanOrEqualTo(120 * yearMinutes), reason: '칸은 해 120년까지만');
  });

  testWidgets('날짜 줄을 고르면 같은 해 보기를 먼저 알리고 그다음에 이동한다', (tester) async {
    final (bus, _) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    final order = <String>[];
    bus.slot('yearPanel').addListener(() => order.add('창'));
    bus.go.addListener(() => order.add('가기'));
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '1592');
    await tester.pumpAndSettle();
    search.activate(0);

    expect(order, ['창', '가기']);
    final panel = bus.slot('yearPanel').value! as Map;
    expect(panel['t'], minuteOf(1592));
    expect(panel['prec'], 'y');
    expect(bus.slot('marker').value, minuteOf(1592));
    expect(bus.selection.value, isNull, reason: '해로 갈 때는 고르지 않는다');
  });

  testWidgets('가문을 고르면 연표를 옮기지 않는다', (tester) async {
    final (bus, _) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '본가');
    await tester.pumpAndSettle();
    final at = search.hits.indexWhere((h) => h.kind == 'house');
    expect(at, isNonNegative);
    search.activate(at);

    expect(bus.selection.value!.kind, 'house');
    expect(bus.go.value, isNull);
  });

  testWidgets('키보드로 옮기고 고르고 비운다', (tester) async {
    final (bus, _) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    await tester.enterText(find.byType(TextField), '유리항');
    await tester.pumpAndSettle();
    expect(search.activeIndex, -1);

    // 화살표는 보이는 차례(search.order)를 따른다.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(search.activeIndex, search.order[0]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(search.activeIndex, search.order[1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(search.activeIndex, search.order[0]);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(bus.selection.value, isNotNull);
    expect(search.showResults, isFalse);

    await tester.enterText(find.byType(TextField), '유리항');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(search.query.isEmpty, isTrue);
    expect(search.showResults, isFalse);
    expect(search.text.text, '');
  });

  testWidgets('늦게 온 답은 버린다', (tester) async {
    final (bus, _) = makeBus();
    final search = SearchController(bus: bus);
    addTearDown(search.dispose);
    await pumpPanel(tester, bus, search);

    final slow = search.setQuery('유리항');
    final fast = search.setQuery('은결');
    await slow;
    await fast;
    await tester.pumpAndSettle();
    expect(search.query.raw, '은결');
    expect(search.hits.every((h) => !h.name.contains('패총국')), isTrue);
  });

  // 서고 꼴(감독 고름 G5 #9 — 다듬기 판 shs-search · 계획 4단계 과제 9 '틀의 시트와 창' 걸음 3).
  group('서고 꼴', () {
    test('칸 줄의 곁글을 주인 · 칸 갈래 · 덧글로 가른다', () {
      SearchHit cell(String sub) => SearchHit(kind: 'cell', name: '칸', uid: 'u', sub: sub);
      expect(searchCellOwner(cell('설원 제국 지도자')), (owner: '설원 제국', kind: '지도자', note: ''));
      expect(searchCellOwner(cell('설원 제국 시기 구분')), (owner: '설원 제국', kind: '시기 구분', note: ''));
      expect(searchCellOwner(cell('유리항 패총국 지도자 · 공용 기억')), (owner: '유리항 패총국', kind: '지도자', note: '공용 기억'));
      expect(searchCellOwner(cell('연호')), (owner: '', kind: '연호', note: ''));
      expect(searchCellOwner(cell('이름뿐')), (owner: '이름뿐', kind: '', note: ''));
    });

    test('갈래 상자 차례 · 상자 안은 엔진 차례 · 칸은 같은 정권끼리 · 보이는 차례 표', () {
      const hits = [
        SearchHit(kind: 'date', name: '1592년(으)로'),
        SearchHit(kind: 'event', name: '사건 가', uid: 'e1', start: 1),
        SearchHit(kind: 'period', name: '정권 가', uid: 'p1', start: 2),
        SearchHit(kind: 'figure', name: '인물 가', uid: 'f1', start: 3),
        SearchHit(kind: 'treaty', name: '조약 가', uid: 't1', start: 4),
        SearchHit(kind: 'cell', name: '칸 가', uid: 'p1', cell: 'leader:0', sub: '정권 가 지도자', start: 5),
        SearchHit(kind: 'cell', name: '칸 나', uid: 'p2', cell: 'leader:0', sub: '정권 나 지도자', start: 6),
        SearchHit(kind: 'cell', name: '칸 다', uid: 'p1', cell: 'phase:0', sub: '정권 가 시기 구분', start: 7),
        SearchHit(kind: 'doc', name: '문서 가', uid: 'd1'),
        SearchHit(kind: 'house', name: '가문 가', uid: 'h1'),
      ];
      final layout = SearchLayout.of(hits);
      expect(layout.lead, [0], reason: '날짜 · 간지 이동 줄은 상자 밖 맨 위');
      expect([for (final b in layout.boxes) b.label], searchBoxLabels);
      expect(layout.boxes[0].rows, [2, 9], reason: '객체 = 정권 · 가문(엔진 차례)');
      expect(layout.boxes[2].rows, [1, 4], reason: '사건 · 조약');
      expect(layout.boxes[3].rows, [3, 8], reason: '인물 · 문서');
      final cells = layout.boxes[1].cells;
      expect([for (final g in cells) g.owner], ['정권 가', '정권 나'], reason: '같은 정권의 칸은 주인 하나 — 주인은 처음 나온 차례');
      expect(cells[0].rows, [5, 7]);
      expect(cells[0].kind, '지도자 · 시기 구분');
      expect(layout.boxes[1].count, 3);
      expect(layout.order, [0, 2, 9, 5, 7, 6, 1, 4, 3, 8], reason: '보이는 차례 — 위에서 아래로 상자를 건너');
      expect([for (final b in SearchLayout.of(const [SearchHit(kind: 'event', name: '가')]).boxes) b.label], ['사건 · 조약'], reason: '빈 상자는 두지 않는다');
    });

    testWidgets('폴더 · 상자 뚜껑 · 칸은 주인 꼬리표 하나 · 화살표는 보이는 차례대로 상자를 건넌다', (tester) async {
      final (bus, _) = makeBus();
      final search = SearchController(bus: bus);
      addTearDown(search.dispose);
      await pumpPanel(tester, bus, search);
      await tester.enterText(find.byType(TextField), '은결');
      await tester.pumpAndSettle();

      expect(find.byType(SheetFolder), findsOneWidget);
      expect(tester.getSize(find.byType(SheetFolder)).width, SheetLook.searchWidth);
      // 뚜껑의 흰 라벨이 상자 차례대로 위에서 아래로.
      final labels = [for (final b in search.layout.boxes) b.label];
      expect(labels, containsAllInOrder(['객체', '칸']));
      final ys = [for (final l in labels) tester.getTopLeft(find.descendant(of: find.byType(SheetLidLabel), matching: find.text(l))).dy];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]));
      }
      // 칸 넷(같은 정권)은 주인 꼬리표 하나 — 머리의 칸 갈래 글이 한 번.
      final cellBox = search.layout.boxes.firstWhere((b) => b.label == '칸');
      expect(cellBox.cells, hasLength(1));
      expect(cellBox.cells.single.rows, hasLength(4));
      expect(find.textContaining('· 지도자'), findsOneWidget);
      // 가문(객체 상자)이 칸 앞에 보인다 — 엔진 차례(칸 → 가문)와 다르다.
      final house = search.hits.indexWhere((h) => h.kind == 'house');
      final firstCell = search.hits.indexWhere((h) => h.kind == 'cell');
      expect(house, greaterThan(firstCell));
      expect(search.order.indexOf(house), lessThan(search.order.indexOf(firstCell)));

      // 화살표는 보이는 차례대로 끝까지 가고 처음으로 돈다.
      for (var k = 0; k < search.order.length; k++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(search.activeIndex, search.order[k]);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(search.activeIndex, search.order.first);
      // 고른 줄(칸 밖)은 고른 테 하나(먹 100 · 1.5).
      expect(find.byWidgetPredicate((w) => w is SheetPickRing && w.on), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(search.activeIndex, search.order.last);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(bus.selection.value?.uid, search.hits[search.order.last].uid, reason: 'Enter는 짚은 줄');
    });

    testWidgets('키가 넘치면 폴더 안에서 넘기고, 화살표로 고른 줄이 가려져 있으면 보이게 넘긴다', (tester) async {
      final (bus, fake) = makeBus();
      fake.pad = 80;
      final search = SearchController(bus: bus);
      addTearDown(search.dispose);
      await pumpPanel(tester, bus, search);
      await tester.enterText(find.byType(TextField), '유리항');
      await tester.pumpAndSettle();
      final folder = tester.getRect(find.byType(SheetFolder));
      expect(folder.height, lessThanOrEqualTo(Ui.resultsMaxHeight), reason: '최대 높이 안');
      final view = find.descendant(of: find.byType(SearchResultsPanel), matching: find.byType(SingleChildScrollView));
      final port = tester.getRect(view);
      final last = search.hits[search.order.last];
      expect(tester.getRect(find.text(last.name).last).top, greaterThan(port.bottom), reason: '끝 줄은 처음에 가려져 있다');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // 짚은 줄이 없으면 ↑는 끝 줄
      await tester.pumpAndSettle();
      expect(search.activeIndex, search.order.last);
      final row = tester.getRect(find.text(last.name).last);
      expect(row.top, greaterThanOrEqualTo(port.top - .01));
      expect(row.bottom, lessThanOrEqualTo(port.bottom + .01), reason: '고른 줄이 보이게 넘김');
    });

    testWidgets('짚은 줄이 없으면 Enter는 보이는 첫 줄 · 날짜 이동 줄은 상자 밖 흰 종이', (tester) async {
      final (bus, _) = makeBus();
      final search = SearchController(bus: bus);
      addTearDown(search.dispose);
      await pumpPanel(tester, bus, search);
      await tester.enterText(find.byType(TextField), '기원전 900년');
      await tester.pumpAndSettle();
      expect(search.layout.lead, [0]);
      expect(find.ancestor(of: find.text('기원전 900년(으)로'), matching: find.byType(SheetBox)), findsNothing);
      expect(find.ancestor(of: find.text('기원전 900년(으)로'), matching: find.byType(SheetThreadColumn)), findsNothing, reason: '실에 매달지 않는다');

      await tester.enterText(find.byType(TextField), '은결');
      await tester.pumpAndSettle();
      expect(search.activeIndex, -1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(bus.selection.value?.uid, search.hits[search.order.first].uid);
    });

    testWidgets('사건은 주인 색 꼬리표에 점 · 줄 사이 가로대에서 실', (tester) async {
      final (bus, _) = makeBus();
      final search = SearchController(bus: bus);
      addTearDown(search.dispose);
      await pumpPanel(tester, bus, search);
      await tester.enterText(find.byType(TextField), '유리항');
      await tester.pumpAndSettle();
      final event = search.hits.firstWhere((h) => h.kind == 'event');
      final tag = tester.widget<SheetTag>(find.ancestor(of: find.text(event.name), matching: find.byType(SheetTag)).first);
      final c = Color(0xff000000 | event.color);
      expect(tag.shape.fill, SheetLook.tagFill(c), reason: '주인 색 꼬리표');
      expect(tag.shape.stroke, SheetLook.tagEdge(c));
      expect(tag.shape.hole, isTrue);
      final column = tester.widget<SheetThreadColumn>(find.ancestor(of: find.text(event.name), matching: find.byType(SheetThreadColumn)));
      expect(column.rails, isTrue, reason: '가로대(먹 12)에서 매단 실');
      expect(column.gap, SheetLook.searchRowGap);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/tools_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 표 보기 · CSV 저장(명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 7-4절):
// 열 일곱 · 체크 둘 · 200줄씩 이어 받기 · 보이는 줄만 묶어 채우기 ·
// 줄을 누르면 창을 먼저 열고 그다음 이동 · 덮어쓰지 않는 파일 이름.
//
// 자료 처리부가 아직 `table` · `table_csv` · `entities`를 돌려주지 않으므로
// test/fixtures/도구-표.json(월흔해 견본에서 뽑은 것)으로 가짜 `ask`를 만들어 돌린다.

/// 가짜 자료 처리부 — 견본을 조건에 맞춰 걸러 쪽으로 잘라 준다.
class FakeData {
  FakeData(this.items, this.records);

  factory FakeData.fromFixture() {
    final raw = jsonDecode(File('test/fixtures/도구-표.json').readAsStringSync()) as Map<String, dynamic>;
    final items = [for (final it in raw['items'] as List) (it as Map).cast<String, dynamic>()];
    final records = {
      for (final e in raw['entities'] as List) (e as Map)['uid'] as String: e.cast<String, dynamic>(),
    };
    return FakeData(items, records);
  }

  final List<Map<String, dynamic>> items;
  final Map<String, Map<String, dynamic>> records;

  /// 물어본 것을 다 적어 둔다.
  final asked = <Map<String, dynamic>>[];

  /// 일부러 실패시킬 명령.
  String? failOn;

  List<Map<String, dynamic>> filter({bool withPeriods = false, num? lo, num? hi}) => [
    for (final it in items)
      if ((withPeriods || it['kind'] == 'event' || it['kind'] == 'treaty') &&
          (lo == null || hi == null || ((it['start'] as num) <= hi && (it['end'] as num) >= lo)))
        it,
  ];

  List<Map<String, dynamic>> _filterOf(Map<String, dynamic> q) =>
      filter(withPeriods: q['with_periods'] == true, lo: q['lo'] as num?, hi: q['hi'] as num?);

  Future<Map<String, dynamic>> ask(Map<String, dynamic> q) async {
    asked.add(q);
    if (q['op'] == failOn) throw StateError('일부러 낸 탈');
    switch (q['op']) {
      // 엔진과 같은 규칙: `after`는 건너뛸 줄의 수, 답의 `next`는 다음에 줄 `after`(계약 2-1절).
      case 'table':
        final all = _filterOf(q);
        final from = (q['after'] as num?)?.toInt() ?? 0;
        final limit = (q['limit'] as num?)?.toInt() ?? tablePage;
        final page = all.skip(from).take(limit).toList();
        return {'items': page, 'next': from + limit, 'has_more': from + page.length < all.length};
      case 'entities':
        final uids = [for (final u in q['uids'] as List) u as String];
        return {
          'entities': [
            for (final uid in uids)
              if (records[uid] != null) records[uid]!,
          ],
        };
      case 'table_csv':
        return {'rows': _filterOf(q).length, 'path': q['path']};
      default:
        return const {};
    }
  }
}

/// 검사용 길 — 트랙 이름과 분류 이름을 찾을 수 있게 작은 배치를 함께 얹는다.
({AppBus bus, FakeData data, List<Selection?> picked, List<GoRequest?> went}) makeBus() {
  final data = FakeData.fromFixture();
  final controller = TimelineController()..resize(1200, 700);
  controller.setExtent(-2000000000, -500000000);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [
        {'id': 1, 'name': '월흔해 연대기', 'events': 5426},
      ],
      'tracks': [
        {'id': 0, 'pack': 1, 'ord': 0, 'name': '유리해안', 'color': 10534085, 'rows': []},
        {'id': 1, 'pack': 1, 'ord': 1, 'name': '흑요산맥', 'color': 10534085, 'rows': []},
        {'id': 2, 'pack': 1, 'ord': 2, 'name': '수관림', 'color': 10534085, 'rows': []},
      ],
      'epochs': [],
      'categories': [
        {'id': 1, 'key': 'politics', 'name': '정치', 'color': 11252681},
        {'id': 2, 'key': 'war', 'name': '전쟁', 'color': 13935515},
        {'id': 3, 'key': 'diplomacy', 'name': '외교·교류', 'color': 10337960},
        {'id': 4, 'key': 'mw-magic', 'name': '마법·기억', 'color': 12299464},
      ],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('표 보기는 타일을 읽지 않는다'),
  );
  final picked = <Selection?>[];
  final went = <GoRequest?>[];
  final bus = AppBus(ask: data.ask, controller: controller, scene: scene);
  bus.selection.addListener(() => picked.add(bus.selection.value));
  bus.go.addListener(() => went.add(bus.go.value));
  return (bus: bus, data: data, picked: picked, went: went);
}

/// 창 크기를 못박고 대화 상자만 띄운다.
Future<void> pumpDialog(WidgetTester tester, AppBus bus, {Size size = const Size(1000, 760), Future<Directory?> Function()? folder}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(backgroundColor: Ui.bg, body: TableDialog(bus: bus, folder: folder)),
    ),
  );
}

TableDialogState stateOf(WidgetTester tester) => tester.state<TableDialogState>(find.byType(TableDialog));

/// 폴더와 이름을 이 컴퓨터의 구분 기호로 잇는다.
String joinPath(String folder, String name) => '$folder${Platform.pathSeparator}$name';

/// 체크를 켠다(글을 누르면 켜진다).
Future<void> check(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('글 — 지금 연표와 같은 낱말', () {
    test('구분은 HT.ITEM_WORDS 그대로', () {
      expect(itemWord('period'), '시대');
      expect(itemWord('event'), '사건');
      expect(itemWord('treaty'), '조약');
      expect(itemWord('figure'), '인물');
      expect(itemWord('epoch'), '시대 구분');
      expect(itemWord('scope'), '대범위');
      expect(itemWord('organ'), '기관');
      expect(itemWord('culture'), '문화');
      expect(itemWord('dynasty'), '왕조');
      expect(itemWord('house'), '가문');
      expect(itemWord('뭔가'), '항목');
    });

    test('확실성은 통설이면 빈 칸', () {
      expect(certaintyName('accepted'), '');
      expect(certaintyName(''), '');
      expect(certaintyName('certain'), '확실');
      expect(certaintyName('estimated'), '추정');
      expect(certaintyName('legend'), '전승');
    });

    test('실재성은 실재면 딱지가 없다', () {
      expect(historicityName(''), '');
      expect(historicityName('attested'), '');
      expect(historicityName('semi'), '반전설');
      expect(historicityName('legendary'), '전설');
      expect(historicityName('disputed'), '실재 논쟁');
      expect(historicityName('refuted'), '부정됨');
    });

    test('설명은 100자에서 자른다', () {
      expect(cutDescription('가나다'), '가나다');
      expect(cutDescription('글' * 130).length, tableDescLimit);
      expect(cutDescription('글' * 100).length, tableDescLimit);
    });

    test('분류는 배치의 이름표에서 찾는다', () {
      const categories = [CategoryInfo(2, 'war', '전쟁', 0)];
      expect(categoryName('war', categories), '전쟁');
      expect(categoryName('없는것', categories), '');
      expect(categoryName('', categories), '');
    });

    test('다른 견해 — 비운 쪽은 통설 값으로 채운다', () {
      final base = {'start': 820.0, 'end': 876.0, 'alternatives': [
        {'start': 804, 'label': '광부 구술설'},
      ]};
      expect(altsText(base), '804년 ~ 876년(광부 구술설)');
    });

    test('다른 견해 — 글만 있는 견해는 근거만 · 둘이면 쉼표로', () {
      expect(altsText({'start': 820.0, 'end': 876.0, 'alternatives': [
        {'label': '연대 미상설'},
      ]}), '연대 미상설');
      expect(
        altsText({'start': 820.0, 'end': 876.0, 'alternatives': [
          {'start': 804, 'label': '가'},
          {'start': 815, 'label': '나'},
        ]}),
        '804년 ~ 876년(가), 815년 ~ 876년(나)',
      );
    });

    test('다른 견해 — 기원전은 기원전으로', () {
      expect(
        altsText({'start': -1400.0, 'end': -750.0, 'alternatives': [
          {'start': -1490, 'end': -810, 'label': '깊은 층위설'},
        ]}),
        '기원전 1490년 ~ 기원전 810년(깊은 층위설)',
      );
    });

    test('항목 기록 → 표의 칸', () {
      final extra = TableExtra.fromRecord(
        {
          'uid': '견본/사건-1',
          'kind': 'event',
          'json': jsonEncode({
            'category': 'war',
            'certainty': 'estimated',
            'description': '설명입니다.',
            'historicity': 'semi',
            'start': 820,
            'end': 876,
            'alternatives': [
              {'start': 804, 'label': '광부 구술설'},
            ],
          }),
        },
        categories: const [CategoryInfo(2, 'war', '전쟁', 0)],
      );
      expect(extra.category, '전쟁');
      expect(extra.certainty, '추정');
      expect(extra.description, '설명입니다.');
      expect(extra.historicity, '반전설');
      expect(extra.alt, '804년 ~ 876년(광부 구술설)');
    });

    test('분류는 사건 · 조약에만 적는다', () {
      final extra = TableExtra.fromRecord(
        {'uid': '견본/시대-1', 'kind': 'period', 'json': jsonEncode({'category': 'war', 'description': '나라'})},
        categories: const [CategoryInfo(2, 'war', '전쟁', 0)],
      );
      expect(extra.category, '');
    });

    test('읽지 못하는 기록은 빈 칸', () {
      expect(TableExtra.fromRecord({'uid': 'x', 'kind': 'event', 'json': '{{{'}).description, '');
    });
  });

  group('표의 한 줄', () {
    test('트랙은 실어 온 이름이 먼저 · 없으면 번호로 배치에서 찾는다', () {
      const layout = null;
      final withName = TableItem.fromJson({'kind': 'event', 'uid': 'a', 'name': '가', 'when': '1년', 'track': 7, 'track_name': '유리해안'});
      expect(withName.trackName(layout), '유리해안');
      final onlyNumber = TableItem.fromJson({'kind': 'event', 'uid': 'b', 'name': '나', 'when': '1년', 'track': 99});
      expect(onlyNumber.trackName(layout), '');
      final asText = TableItem.fromJson({'kind': 'event', 'uid': 'c', 'name': '다', 'when': '1년', 'track': '흑요산맥'});
      expect(asText.trackName(layout), '흑요산맥');
    });

    test('날짜를 모르는 줄은 시작 · 끝이 없다', () {
      final unknown = TableItem.fromJson({'kind': 'event', 'uid': 'a', 'name': '가', 'when': '미정'});
      expect(unknown.start, isNull);
      expect(unknown.end, isNull);
    });
  });

  group('CSV를 쓸 자리', () {
    test('이미 있으면 번호를 붙여 덮어쓰지 않는다', () {
      final there = <String>{};
      final folder = joinPath('C:', '내려받기');
      expect(freeCsvPath(folder, exists: there.contains), joinPath(folder, '역사연표.csv'));
      there.add(joinPath(folder, '역사연표.csv'));
      expect(freeCsvPath(folder, exists: there.contains), joinPath(folder, '역사연표 (2).csv'));
      there.add(joinPath(folder, '역사연표 (2).csv'));
      expect(freeCsvPath(folder, exists: there.contains), joinPath(folder, '역사연표 (3).csv'));
    });

    test('폴더 끝의 구분 기호를 겹쳐 붙이지 않는다', () {
      expect(freeCsvPath('/내려받기/', exists: (_) => false), '/내려받기/역사연표.csv');
    });
  });

  group('견본', () {
    test('표의 줄과 항목 기록이 들어 있고 시작 순이다', () {
      final data = FakeData.fromFixture();
      expect(data.filter(withPeriods: true).length, greaterThan(tablePage), reason: '이어 받기를 검사하려면 한 쪽보다 많아야 한다');
      expect(data.records, isNotEmpty);
      for (int i = 1; i < data.items.length; i++) {
        expect((data.items[i]['start'] as num) >= (data.items[i - 1]['start'] as num), isTrue, reason: '$i번째 줄이 앞줄보다 이르다');
      }
    });
  });

  group('대화 상자', () {
    testWidgets('머리 · 체크 둘 · 아래 단추', (tester) async {
      final t = makeBus();
      await pumpDialog(tester, t.bus);
      await tester.pumpAndSettle();

      expect(find.text('표'), findsOneWidget);
      expect(find.text('지금 보이는 시기만'), findsOneWidget);
      expect(find.text('시대 · 인물도 포함'), findsOneWidget);
      expect(find.text('CSV 내보내기'), findsOneWidget);
      expect(find.text('닫기'), findsOneWidget);
    });

    testWidgets('폭은 min(820, 창 − 24)', (tester) async {
      final t = makeBus();
      await pumpDialog(tester, t.bus);
      await tester.pumpAndSettle();
      // 목록의 폭 = 대화 상자 폭 − 좌우 여백 22씩.
      expect(tester.getSize(find.byType(ListView)).width, closeTo(820 - 44, .5));

      final narrow = makeBus();
      await pumpDialog(tester, narrow.bus, size: const Size(600, 700));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ListView)).width, closeTo(600 - 24 - 44, .5));
    });

    testWidgets('열 일곱이 머리 줄에 있다', (tester) async {
      final t = makeBus();
      await pumpDialog(tester, t.bus);
      await tester.pumpAndSettle();
      for (final head in ['시기', '구분', '트랙', '제목', '분류', '확실성', '설명']) {
        expect(find.text(head), findsWidgets, reason: '$head 열이 없다');
      }
    });

    testWidgets('첫 쪽은 200줄까지 · 끝까지 내리면 다음 쪽을 이어 받는다', (tester) async {
      final t = makeBus();
      await pumpDialog(tester, t.bus);
      await tester.pumpAndSettle();
      await check(tester, '시대 · 인물도 포함'); // 260줄 → 두 쪽

      final pages = t.data.asked.where((q) => q['op'] == 'table' && q['with_periods'] == true).toList();
      expect(pages.length, 1, reason: '처음에는 한 쪽만 받는다');
      expect(pages.first['limit'], tablePage);
      expect(pages.first['after'], isNull);
      expect(stateOf(tester).rows.length, tablePage);

      await tester.drag(find.byType(ListView), const Offset(0, -20000));
      await tester.pumpAndSettle();

      final after = t.data.asked.where((q) => q['op'] == 'table' && q['with_periods'] == true).toList();
      expect(after.length, 2);
      expect(after[1]['after'], tablePage, reason: '이어 받기 표는 건너뛸 줄의 수다');
      expect(stateOf(tester).rows.length, t.data.filter(withPeriods: true).length);
    });

    testWidgets('보이는 줄만 묶어서 칸을 채운다 — 한 번에 100개까지', (tester) async {
      final t = makeBus();
      await pumpDialog(tester, t.bus);
      await tester.pumpAndSettle();

      final calls = t.data.asked.where((q) => q['op'] == 'entities').toList();
      expect(calls, isNotEmpty, reason: '보이는 줄의 칸을 묶어 물어야 한다');
      for (final q in calls) {
        expect((q['uids'] as List).length, lessThanOrEqualTo(tableEntityBatch));
      }
      final asked = {for (final q in calls) ...(q['uids'] as List).cast<String>()};
      expect(asked.length, lessThan(tablePage), reason: '보이지 않는 줄까지 다 묻지 않는다');
      expect(asked, contains(t.data.filter()[0]['uid']));
    });

    testWidgets('제목 옆 실재성 딱지 · 아래 다른 견해 · 분류와 확실성', (tester) async {
      final t = makeBus();
      await pumpDialog(tester, t.bus, size: const Size(1000, 900));
      await tester.pumpAndSettle();
      await check(tester, '시대 · 인물도 포함'); // 띠가 보여야 딱지가 나온다

      expect(find.text('유리항 매듭토기 문화'), findsOneWidget);
      expect(find.text('다른 견해: 기원전 1490년 ~ 기원전 810년(깊은 층위설)'), findsOneWidget);

      expect(find.text('안개 문지기국'), findsOneWidget);
      expect(find.text('반전설'), findsOneWidget);
      expect(find.text('두 달의 궁정'), findsOneWidget);
      expect(find.text('전설'), findsOneWidget);
      expect(find.text('빈 종 왕국'), findsOneWidget);
      expect(find.text('실재 논쟁'), findsOneWidget);
      expect(find.text('추정'), findsWidgets);
      expect(find.text('전승'), findsWidgets);
    });

    testWidgets('구분 · 트랙 · 시기는 줄에 온 값 그대로', (tester) async {
      final t = makeBus();
      await pumpDialog(tester, t.bus);
      await tester.pumpAndSettle();
      final first = t.data.filter()[0];
      expect(find.text(first['when'] as String), findsWidgets);
      expect(find.text(itemWord(first['kind'] as String)), findsWidgets);
      expect(find.text('유리해안'), findsWidgets, reason: '트랙 번호를 배치의 이름으로 바꿔 적는다');
    });

    testWidgets('지금 보이는 시기만 — 보기의 lo · hi를 넘기고 다시 받는다', (tester) async {
      final t = makeBus();
      t.bus.controller.showRange(-620000000, -610000000);
      await pumpDialog(tester, t.bus);
      await tester.pumpAndSettle();
      final before = stateOf(tester).rows.length;

      await check(tester, '지금 보이는 시기만');

      final ranged = t.data.asked.where((q) => q['op'] == 'table' && q['lo'] != null).toList();
      expect(ranged, isNotEmpty);
      expect(ranged.first['lo'], closeTo(t.bus.controller.view.lo, 1));
      expect(ranged.first['hi'], closeTo(t.bus.controller.view.hi, 1));
      expect(stateOf(tester).rows.length, lessThan(before), reason: '보기와 겹치는 것만 남는다');
    });

    testWidgets('시대 · 인물도 포함 — 끄면 사건만', (tester) async {
      final t = makeBus();
      await pumpDialog(tester, t.bus);
      await tester.pumpAndSettle();
      expect(t.data.asked.firstWhere((q) => q['op'] == 'table')['with_periods'], isFalse);
      expect(stateOf(tester).rows.every((r) => r.kind == 'event' || r.kind == 'treaty'), isTrue);

      await check(tester, '시대 · 인물도 포함');
      expect(t.data.asked.where((q) => q['op'] == 'table' && q['with_periods'] == true), isNotEmpty);
      expect(stateOf(tester).rows.any((r) => r.kind == 'period' || r.kind == 'figure'), isTrue);
    });

    testWidgets('줄을 누르면 대화 상자를 닫고 · 창을 먼저 열고 · 그다음 옮긴다', (tester) async {
      final t = makeBus();
      tester.view.physicalSize = const Size(1000, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(onPressed: () => showTableDialog(context, t.bus), child: const Text('열기')),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('표'), findsOneWidget);

      final item = stateOf(tester).rows.first;
      await tester.tap(find.text(item.name).first);
      await tester.pumpAndSettle();

      expect(find.text('표'), findsNothing, reason: '대화 상자가 닫힌다');
      expect(t.picked.last?.uid, item.uid);
      expect(t.picked.last?.kind, item.kind);
      expect(t.went.last?.lo, item.start);
      expect(t.went.last?.hi, item.end);
      expect(t.went.last?.ring, item.uid);
    });

    testWidgets('켠 자료집만 묻는다', (tester) async {
      final t = makeBus();
      await pumpDialog(tester, t.bus);
      await tester.pumpAndSettle();
      expect(t.data.asked.firstWhere((q) => q['op'] == 'table')['packs'], [1]);
    });

    testWidgets('CSV — 경로를 정해 넘기고, 끝나면 줄 수와 경로를 한 줄로 적는다', (tester) async {
      final t = makeBus();
      final dir = Directory.systemTemp.createTempSync('표보기검사');
      addTearDown(() => dir.deleteSync(recursive: true));
      await pumpDialog(tester, t.bus, folder: () async => dir);
      await tester.pumpAndSettle();

      await tester.tap(find.text('CSV 내보내기'));
      await tester.pumpAndSettle();

      final q = t.data.asked.lastWhere((q) => q['op'] == 'table_csv');
      expect(q['path'], joinPath(dir.path, '역사연표.csv'));
      expect(q['with_periods'], isFalse);
      expect(q['limit'], isNull, reason: 'CSV는 쪽으로 나누지 않는다');
      expect(find.textContaining('${t.data.filter().length}줄을 저장했습니다 — '), findsOneWidget);
    });

    testWidgets('CSV — 이미 있는 파일은 덮어쓰지 않는다', (tester) async {
      final t = makeBus();
      final dir = Directory.systemTemp.createTempSync('표보기검사2');
      addTearDown(() => dir.deleteSync(recursive: true));
      final already = File(joinPath(dir.path, '역사연표.csv'))..writeAsStringSync('앞서 저장한 것');
      await pumpDialog(tester, t.bus, folder: () async => dir);
      await tester.pumpAndSettle();

      await tester.tap(find.text('CSV 내보내기'));
      await tester.pumpAndSettle();

      expect(t.data.asked.lastWhere((q) => q['op'] == 'table_csv')['path'], endsWith('역사연표 (2).csv'));
      expect(already.readAsStringSync(), '앞서 저장한 것');
    });

    testWidgets('CSV — 실패하면 까닭을 한 줄로 적는다', (tester) async {
      final t = makeBus();
      t.data.failOn = 'table_csv';
      final dir = Directory.systemTemp.createTempSync('표보기검사3');
      addTearDown(() => dir.deleteSync(recursive: true));
      await pumpDialog(tester, t.bus, folder: () async => dir);
      await tester.pumpAndSettle();

      await tester.tap(find.text('CSV 내보내기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CSV로 저장하지 못했습니다'), findsOneWidget);
    });

    testWidgets('빈 표', (tester) async {
      final t = makeBus();
      t.data.items.clear();
      await pumpDialog(tester, t.bus);
      await tester.pumpAndSettle();
      expect(find.text('표시할 항목이 없습니다.'), findsOneWidget);
    });

    testWidgets('읽지 못한 표', (tester) async {
      final t = makeBus();
      t.data.failOn = 'table';
      await pumpDialog(tester, t.bus);
      await tester.pumpAndSettle();
      expect(find.textContaining('표를 읽지 못했습니다'), findsOneWidget);
    });

    testWidgets('줄의 자리는 칸이 늦게 채워져도 그대로다', (tester) async {
      final t = makeBus();
      await pumpDialog(tester, t.bus);
      await tester.pump(); // 줄만 받은 첫 모습(칸은 아직 빈 칸)
      await tester.pump();
      final rows = stateOf(tester).rows;
      double top(int i) => tester.getTopLeft(find.text(rows[i].name).first).dy;
      List<double> gaps() => [top(1) - top(0), top(2) - top(1)];

      final before = gaps();
      expect(before, [tableRowHeight, tableRowHeight]);

      await tester.pumpAndSettle(); // 칸이 채워진 뒤
      expect(find.text('정치'), findsWidgets, reason: '분류가 채워졌다');
      expect(gaps(), before, reason: '칸이 채워져도 줄 높이는 그대로다');

      // '다른 견해'가 한 줄 더 붙는 줄도 높이가 같다.
      await check(tester, '시대 · 인물도 포함');
      final now = stateOf(tester).rows;
      double after(int i) => tester.getTopLeft(find.text(now[i].name).first).dy;
      expect(find.textContaining('다른 견해: '), findsWidgets);
      expect([after(1) - after(0), after(2) - after(1)], [tableRowHeight, tableRowHeight]);
    });
  });
}

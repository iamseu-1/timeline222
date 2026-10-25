import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/detail_echo.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/filter_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart';

// 같은 시기 타국(메아리)의 창 쪽 — 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md` 3-4절 ·
// 지금 연표의 `echoBoxHTML` · `fillEchoSlot`(js/viewer.js:2137~2204).
// 보는 것: 스위치가 필터의 `show.spotEcho`와 한 설정인가 · 답에서 연표가 쓸 것을 슬롯에 싣는가 ·
// 추려 보이기(40건 · 나라마다 5건 · 8곳)와 더 보기 · 그 조회 명령이 없을 때 자리를 비우는가.

/// 견본 묶음 하나 — `n`건을 담는다(마지막 줄만 중요한 사건).
Map<String, dynamic> echoGroup(String uid, String name, int n, {String track = '숲기슭', bool folded = false, int from = 0, int trackId = 7, int? row}) => {
  'uid': uid,
  'name': name,
  'track': trackId,
  'row': ?row,
  'track_name': track,
  'color': 0xb6c398,
  'folded': folded,
  'count': n,
  'events': [
    for (var i = 0; i < n; i++)
      {'id': from + i, 'uid': '$uid/ev-$i', 'title': '$name 사건 $i', 'when': '${800 + i}년', 'importance': i == n - 1 ? 3 : 1},
  ],
};

/// 답 하나(묶음 여럿).
Map<String, dynamic> answerOf(List<Map<String, dynamic>> groups, {List<String> ownUids = const [], List<int> echoIds = const []}) => {
  'spans': const [],
  'own': const [],
  'ownUids': ownUids,
  'echo': const [],
  'echoIds': echoIds,
  'groups': groups,
  'count': groups.fold<int>(0, (n, g) => n + (g['count'] as int)),
};

/// 검사용 AppBus — `echo`에만 답한다(주지 않으면 '없는 명령'으로 거절해 그 자리가 비는지 본다).
({AppBus bus, List<Map<String, dynamic>> asked}) echoBus({Map<String, dynamic>? answer, Map<String, dynamic>? shape}) {
  final asked = <Map<String, dynamic>>[];
  final controller = TimelineController()..resize(1920, 500);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(
      shape ??
          const {
            'packs': [
              {'id': 1, 'name': '견본 기록집', 'events': 3},
            ],
            'tracks': [],
            'epochs': [],
          },
    ),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('메아리 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(
    ask: (query) async {
      asked.add(query);
      if (query['op'] == 'echo' && answer != null) return answer;
      throw StateError('없는 명령');
    },
    controller: controller,
    scene: scene,
  );
  return (bus: bus, asked: asked);
}

/// 부품 하나를 띄우는 작은 틀(상세 창의 폭 380 · 몸통은 스크롤 하나).
Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Ui.bg,
    body: SizedBox(width: Ui.detailWidth, child: SingleChildScrollView(child: child)),
  ),
);

/// 그 글이 보이도록 스크롤한다.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder.first, 120, scrollable: find.byType(Scrollable).first);
}

/// 이 창이 켠 기간 조명 하나.
const List<Map<String, dynamic>> oneSpot = [
  {'uid': '가상/p-coast', 'cell': 'leader:3', 'start': 1000.0, 'end': 2000.0},
];

Future<({AppBus bus, List<Map<String, dynamic>> asked})> open(
  WidgetTester tester, {
  Map<String, dynamic>? answer,
  bool always = true,
  List<Widget> between = const [],
  List<Map<String, dynamic>> spots = oneSpot,
  FilterState? filters,
  Map<String, dynamic>? shape,
}) async {
  final made = echoBus(answer: answer, shape: shape);
  if (filters != null) made.bus.slot('filters').value = filters;
  await tester.pumpWidget(host(EchoSlot(bus: made.bus, spots: spots, always: always, between: between)));
  await tester.pumpAndSettle();
  return made;
}

void main() {
  group('스위치', () {
    testWidgets('기본은 꺼짐이고, 켜면 필터의 show.spotEcho와 slot(echo)가 함께 바뀐다', (tester) async {
      final made = await open(tester, answer: answerOf([echoGroup('가상/p-other', '잎울 나이테국', 2)]), filters: const FilterState());
      expect(find.text(echoSwitchLabel), findsOneWidget);
      expect(find.textContaining('같은 시기 타국'), findsNothing);

      await tester.tap(find.text(echoSwitchLabel));
      await tester.pumpAndSettle();
      expect(made.bus.slot(echoSlot).value, isTrue);
      expect((made.bus.slot('filters').value as FilterState).showing('spotEcho'), isTrue);
      expect(find.textContaining('같은 시기 타국'), findsOneWidget);

      // 다시 끄면 자리가 빈다.
      await tester.tap(find.text(echoSwitchLabel));
      await tester.pumpAndSettle();
      expect(made.bus.slot(echoSlot).value, isFalse);
      expect((made.bus.slot('filters').value as FilterState).showing('spotEcho'), isFalse);
      expect(find.textContaining('같은 시기 타국'), findsNothing);
    });

    testWidgets('필터 시트에서 켜도 창의 체크와 묶음이 함께 바뀐다', (tester) async {
      final made = await open(tester, answer: answerOf([echoGroup('가상/p-other', '잎울 나이테국', 2)]), filters: const FilterState());
      made.bus.slot('filters').value = const FilterState().withShowing('spotEcho', true);
      await tester.pumpAndSettle();
      expect(find.textContaining('같은 시기 타국'), findsOneWidget);
    });

    testWidgets('필터 값이 없으면 기억은 slot(echo) 하나뿐이다', (tester) async {
      final made = await open(tester, answer: answerOf([echoGroup('가상/p-other', '잎울 나이테국', 1)]));
      await tester.tap(find.text(echoSwitchLabel));
      await tester.pumpAndSettle();
      expect(made.bus.slot(echoSlot).value, isTrue);
      expect(made.bus.slot('filters').value, isNull);
    });
  });

  group('자료', () {
    testWidgets('물어보는 모양 — op · spots · limit', (tester) async {
      final made = await open(tester, answer: answerOf(const []));
      final query = made.asked.firstWhere((q) => q['op'] == 'echo');
      expect(query['limit'], echoLimit);
      expect(query['spots'], [
        {'uid': '가상/p-coast', 'start': 1000.0, 'end': 2000.0},
      ]);
      // 스위치는 답을 다시 묻지 않는다 — 한 답에 제 것과 메아리가 함께 들어 있다.
      await tester.tap(find.text(echoSwitchLabel));
      await tester.pumpAndSettle();
      expect(made.asked.where((q) => q['op'] == 'echo').length, 1);
    });

    testWidgets('연표가 쓸 것(ownUids · echoIds)만 slot(echoHits)에 싣고, 창이 사라지면 치운다', (tester) async {
      final made = await open(
        tester,
        answer: answerOf([echoGroup('가상/p-other', '잎울 나이테국', 1)], ownUids: const ['가상/ev-own'], echoIds: const [11, 12]),
      );
      final hits = made.bus.slot(echoHitsSlot).value as EchoHits;
      expect(hits.ownUids, ['가상/ev-own']);
      expect(hits.echoIds, [11, 12]);

      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(made.bus.slot(echoHitsSlot).value, isNull);
    });

    testWidgets('조명이 없으면 묻지 않는다', (tester) async {
      final made = await open(tester, answer: answerOf(const []), spots: const []);
      expect(made.asked, isEmpty);
      expect(find.text(echoSwitchLabel), findsOneWidget);
    });

    testWidgets('그 조회 명령이 없으면 자리만 빈다 — 스위치는 그대로 선다', (tester) async {
      final made = await open(tester);
      await tester.tap(find.text(echoSwitchLabel));
      await tester.pumpAndSettle();
      expect(made.bus.slot(echoSlot).value, isTrue);
      expect(find.textContaining('같은 시기 타국'), findsNothing);
      expect(made.bus.slot(echoHitsSlot).value, isNull);
    });
  });

  group('묶음', () {
    /// 메아리를 켠 채로 연다.
    Future<({AppBus bus, List<Map<String, dynamic>> asked})> lit(
      WidgetTester tester,
      Map<String, dynamic> answer, {
      List<Widget> between = const [],
    }) => open(tester, answer: answer, between: between, filters: const FilterState().withShowing('spotEcho', true));

    testWidgets('머리 · 나라 이름 · 트랙 · 건수 · 접힘 딱지', (tester) async {
      await lit(tester, answerOf([echoGroup('가상/p-other', '잎울 나이테국', 2), echoGroup('가상/p-fold', '밤그늘 연맹', 1, track: '검은유리', folded: true, from: 90)]));
      // (답이 스스로 접혔다고 적는 일은 실제로는 없다 — 아래 '접힘 딱지' 묶음이 진짜 길이다.)
      expect(find.textContaining('2곳 · 3건'), findsOneWidget);
      expect(find.text('잎울 나이테국'), findsOneWidget);
      expect(find.text('숲기슭 · 2건'), findsOneWidget);
      expect(find.text('검은유리 · 1건'), findsOneWidget);
      expect(find.text('접힘'), findsOneWidget);
      expect(find.text('잎울 나이테국 사건 0'), findsOneWidget);
      expect(find.text('800년'), findsWidgets);
    });

    testWidgets('하위 사건은 포함 n · 공동 사건은 속 빈 점 · 조약은 마름모', (tester) async {
      await lit(tester, {
        'count': 2,
        'groups': [
          {
            'uid': '가상/p-other',
            'name': '잎울 나이테국',
            'track_name': '숲기슭',
            'color': 0xb6c398,
            'count': 2,
            'events': [
              {'id': 1, 'uid': '가상/ev-1', 'title': '나이테 개정', 'when': '850년', 'kids': 3, 'treaty': true},
              {'id': 2, 'uid': '가상/ev-2', 'title': '아홉 인장 회담', 'when': '858년', 'shared': true, 'with': ['밤그늘 연맹']},
            ],
          },
        ],
      });
      expect(find.textContaining('포함 3'), findsOneWidget);
      expect(find.textContaining('함께 · 밤그늘 연맹'), findsOneWidget);
    });

    testWidgets('정권이 없는 사건의 묶음은 트랙 이름으로 선다', (tester) async {
      await lit(tester, answerOf([echoGroup('', '', 1, track: '유리해안')]));
      expect(find.text('유리해안'), findsOneWidget);
      expect(find.text('정권 없는 사건 · 1건'), findsOneWidget);
    });

    testWidgets('그 시기 타국의 사건이 없으면 없음 한 줄', (tester) async {
      await lit(tester, answerOf(const []));
      expect(find.textContaining('없음'), findsOneWidget);
      expect(find.text('그 시기 타국의 사건이 없습니다.'), findsOneWidget);
    });

    testWidgets('모두 40건이 넘으면 나라마다 중요한 5건 + n건 더 보기', (tester) async {
      await lit(tester, answerOf([echoGroup('가상/p-many', '잎울 나이테국', 45)]));
      expect(find.textContaining('나라마다 중요한 $echoEach건'), findsOneWidget);
      // 중요한 것(마지막 줄)이 남고, 보이는 차례는 받은 그대로다.
      expect(find.text('잎울 나이테국 사건 44'), findsOneWidget);
      expect(find.text('잎울 나이테국 사건 5'), findsNothing);
      await reveal(tester, find.text('40건 더 보기'));
      await tester.tap(find.text('40건 더 보기'));
      await tester.pumpAndSettle();
      expect(find.text('잎울 나이테국 사건 5'), findsOneWidget);
    });

    testWidgets('40건 아래면 나라마다 모두 편다', (tester) async {
      await lit(tester, answerOf([echoGroup('가상/p-many', '잎울 나이테국', 9)]));
      expect(find.textContaining('나라마다 중요한'), findsNothing);
      expect(find.text('잎울 나이테국 사건 5'), findsOneWidget);
    });

    testWidgets('묶음이 8곳을 넘으면 타국 n곳 더 펼치기', (tester) async {
      await lit(tester, answerOf([for (var i = 0; i < 11; i++) echoGroup('가상/p-$i', '나라 $i', 1, from: i * 10)]));
      expect(find.text('나라 7'), findsOneWidget);
      expect(find.text('나라 8'), findsNothing);
      await reveal(tester, find.text('타국 3곳 더 펼치기'));
      await tester.tap(find.text('타국 3곳 더 펼치기'));
      await tester.pumpAndSettle();
      expect(find.text('나라 10'), findsOneWidget);
    });

    testWidgets('줄을 누르면 그 사건을 고른다', (tester) async {
      final made = await lit(tester, answerOf([echoGroup('가상/p-other', '잎울 나이테국', 2)]));
      await reveal(tester, find.text('잎울 나이테국 사건 1'));
      await tester.tap(find.text('잎울 나이테국 사건 1'));
      await tester.pump();
      expect(made.bus.selection.value?.uid, '가상/p-other/ev-1');
    });

    testWidgets('스위치와 묶음 사이에 다른 묶음이 든다(지금 연표의 차례)', (tester) async {
      await lit(tester, answerOf([echoGroup('가상/p-other', '잎울 나이테국', 1)]), between: const [DetailBox(title: '이 시기의 사건')]);
      final middle = tester.getCenter(find.textContaining('이 시기의 사건')).dy;
      expect(tester.getCenter(find.text(echoSwitchLabel)).dy, lessThan(middle));
      expect(tester.getCenter(find.textContaining('같은 시기 타국')).dy, greaterThan(middle));
    });

    testWidgets('메아리 목록에는 소속 · 〈나라〉를 적지 않는다(지금 연표의 echoRowsHTML)', (tester) async {
      // `member`(계약 2-5)는 칸 상세의 '이 시기의 사건'에만 붙는 글이다 — 지금 연표의 메아리 목록
      // (js/viewer.js:2140)에는 `포함 n`과 `함께 · 〈나라〉`뿐이다. 엔진이 뒷날 이 자리를 채우더라도
      // 지금 연표에 없는 꼬리표가 생기지 않아야 한다.
      await lit(tester, {
        'count': 1,
        'groups': [
          {
            'uid': '가상/p-host',
            'name': '윗물 상국',
            'track_name': '숲기슭',
            'count': 1,
            'events': [
              {'id': 3, 'uid': '가상/ev-3', 'title': '세 골짜기의 맹세', 'when': '870년', 'member': '아랫물 속국'},
            ],
          },
        ],
      });
      expect(find.text('세 골짜기의 맹세'), findsOneWidget);
      expect(find.textContaining('소속 · '), findsNothing);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────────────────────
  //  접힘 딱지 — 엔진은 보기 상태를 몰라 답의 `folded`가 늘 거짓이라, 창이 줄 쌓기를 보고 붙인다.
  //  견본 줄 쌓기(`support/fold_rows.dart`): 트랙 1은 줄 0·1·2(민족 묶음 하나), 트랙 2는 줄 3·4.
  // ────────────────────────────────────────────────────────────────────────────────────────────

  group('접힘 딱지', () {
    Future<({AppBus bus, List<Map<String, dynamic>> asked})> lit(WidgetTester tester, Map<String, dynamic> answer) =>
        open(tester, answer: answer, shape: twoTrackLayout(), filters: const FilterState().withShowing('spotEcho', true));

    testWidgets('엔진의 folded가 거짓이어도 접은 트랙의 묶음에는 딱지가 붙는다', (tester) async {
      final made = await lit(tester, answerOf([echoGroup('가상/p-a', '잎울 나이테국', 1, trackId: 1, row: 1)]));
      expect(find.text('접힘'), findsNothing);

      made.bus.scene.applyViewState(made.bus.scene.layout.viewState.withTrackFolded(1, true));
      await tester.pumpAndSettle();
      expect(find.text('접힘'), findsOneWidget);

      made.bus.scene.applyViewState(made.bus.scene.layout.viewState.withTrackFolded(1, false));
      await tester.pumpAndSettle();
      expect(find.text('접힘'), findsNothing);
    });

    testWidgets('접은 민족 묶음에 합쳐진 줄도 접힘이다', (tester) async {
      final made = await lit(tester, answerOf([echoGroup('가상/p-a', '잎울 나이테국', 1, trackId: 1, row: 1)]));
      final layout = made.bus.scene.layout;
      final track = layout.tracks.first;
      // 줄 0·1·2를 품은 민족 묶음을 접으면 줄 1은 합쳐져 안 보인다(첫 줄만 남는다).
      made.bus.scene.applyViewState(layout.viewState.withGroupFolded(layout.groupKeyOf(track, track.groups.first), true));
      await tester.pumpAndSettle();
      expect(layout.isMergedAway(1), isTrue);
      expect(find.text('접힘'), findsOneWidget);
    });

    testWidgets('다른 트랙을 접은 것은 이 묶음과 상관없다', (tester) async {
      final made = await lit(tester, answerOf([echoGroup('가상/p-b', '밤그늘 연맹', 1, trackId: 2, row: 3)]));
      made.bus.scene.applyViewState(made.bus.scene.layout.viewState.withTrackFolded(1, true));
      await tester.pumpAndSettle();
      expect(find.text('접힘'), findsNothing);
    });

    testWidgets('줄 번호가 아직 답에 없으면 트랙만이라도 본다', (tester) async {
      final made = await lit(tester, answerOf([echoGroup('가상/p-a', '잎울 나이테국', 1, trackId: 1)]));
      expect(find.text('접힘'), findsNothing);
      made.bus.scene.applyViewState(made.bus.scene.layout.viewState.withTrackFolded(1, true));
      await tester.pumpAndSettle();
      expect(find.text('접힘'), findsOneWidget);
    });

    test('줄도 트랙도 없는 묶음은 딱지를 붙이지 않는다', () {
      final group = EchoGroup.read(const {'uid': '가상/p-c', 'name': '없는 곳', 'count': 0});
      expect(group.row, -1);
      expect(group.trackId, -1);
      expect(group.foldedIn(SceneLayout.fromJson(twoTrackLayout())), isFalse);
    });

    testWidgets('정권이 없는 사건의 묶음은 트랙을 접어도 딱지가 없다', (tester) async {
      // 지금 연표도 띠가 없는 묶음에는 접힘을 매기지 않는다(core.js의 `folded: !!b && !!b.folded`).
      final made = await lit(tester, answerOf([echoGroup('', '별여울 갈래', 1, trackId: 1)]));
      made.bus.scene.applyViewState(made.bus.scene.layout.viewState.withTrackFolded(1, true));
      await tester.pumpAndSettle();
      expect(find.text('접힘'), findsNothing);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────────────────────
  //  진짜 자료 처리부(DLL) + 진짜 저장소 — 가짜 답으로는 못 잡는 것(열쇠 이름 · 꼴)을 여기서 굳힌다.
  //  돌리는 법은 `test/contract_real_engine_test.dart`와 같다. DLL · 저장소가 없으면 건너뛴다.
  // ────────────────────────────────────────────────────────────────────────────────────────────

  group('진짜 엔진의 echo', () {
    final dll = File('../engine/target/release/archive_engine.dll');
    final db = File('../data/moonwake3h/archive.db');
    final ready = dll.existsSync() && db.existsSync();
    const noData = '자료 처리부 DLL 또는 data/moonwake3h 저장소가 없습니다';

    ArchiveEngine? engine;

    setUpAll(() async {
      if (!ready) return;
      engine = ArchiveEngine(libraryPath: dll.absolute.path);
      await engine!.start(db.absolute.path);
    });

    tearDownAll(() => engine?.close());

    /// 앱 틀과 같은 길 — 배열로 오는 답은 `{items: […]}`로 감싼다.
    Future<Map<String, dynamic>> ask(Map<String, dynamic> query) async {
      final answer = await engine!.call(query);
      final data = answer['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is List) return <String, dynamic>{'items': data};
      return <String, dynamic>{};
    }

    /// 유리항 패총국(`moonwake-chronicle/p-coast-0`)이 있던 동안 — 창이 켜는 조명과 같은 꼴.
    /// **화면은 분을 소수 꼴로 보낸다**(검증 보고서 9-2절) — 그 꼴 그대로 묻는다.
    Future<Map<String, dynamic>> echoOf() => ask({
      'op': 'echo',
      'spots': [
        {'uid': 'moonwake-chronicle/p-coast-0', 'start': -1540504800.0, 'end': -1245972960.0},
      ],
      'limit': echoLimit,
    });

    test('부품이 읽는 열쇠가 답에 그대로 있다', () async {
      final answer = await echoOf();
      expect(answer.keys, containsAll(['spans', 'own', 'ownUids', 'echo', 'echoIds', 'groups', 'count', 'total']));
      final read = EchoAnswer.read(answer);
      expect(read.count, greaterThan(0), reason: '이 조명에는 같은 시기 타국의 사건이 있다');
      expect(read.groups, isNotEmpty);
      expect(read.echoIds, isNotEmpty);

      final group = read.groups.first;
      expect(group.name, isNotEmpty);
      expect(group.track, isNotEmpty, reason: '묶음 머리의 옅은 글(트랙 이름)');
      expect(group.color, isNotNull);
      expect(group.count, group.events.length);
      expect(group.folded, isFalse, reason: '엔진은 보기 상태를 모른다 — 계약 2-5의 ②');

      final one = group.events.first;
      expect(one.uid, isNotEmpty);
      expect(one.title, isNotEmpty);
      expect(one.when, isNotEmpty, reason: '날짜 글은 엔진이 적어 준다');
      expect(one.importance, inInclusiveRange(1, 3));
    }, skip: ready ? false : noData);

    test('답의 사건 줄에 member 자리가 있다(아직 빈 글) · with는 아직 오지 않는다', () async {
      final answer = await echoOf();
      final groups = (answer['groups'] as List).cast<Map<String, dynamic>>();
      final rows = (groups.first['events'] as List).cast<Map<String, dynamic>>();
      expect(rows.first.keys, contains('member'), reason: '계약 2-5의 사건 한 줄');
      expect(EchoGroup.read(groups.first).events.first.member, '', reason: '저장소에 그 관계가 없어 늘 빈 글이다');
      // `with`(함께 · 〈나라〉)는 엔진이 아직 싣지 않는다 — 오면 그대로 그리게 되어 있다(위 '묶음'의 검사).
      expect(EchoGroup.read(groups.first).events.first.alsoIn, isEmpty);
    }, skip: ready ? false : noData);

    test('묶음에 줄 번호(row)가 실리면 접힘 딱지가 그 줄을 본다', () async {
      final answer = await echoOf();
      final groups = (answer['groups'] as List).cast<Map<String, dynamic>>();
      final read = EchoGroup.read(groups.first);
      expect(groups.first.keys, contains('track'), reason: '트랙 번호는 지금도 온다 — 접힌 트랙은 이것만으로 안다');
      expect(read.trackId, greaterThanOrEqualTo(0));
      // `row`는 엔진이 아직 싣지 않는다(보고에 적었다) — 그때까지는 −1이고 트랙만 본다.
      expect(read.row, groups.first['row'] is num ? (groups.first['row'] as num).toInt() : -1);
    }, skip: ready ? false : noData);
  });
}

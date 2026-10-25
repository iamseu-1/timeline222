import 'load_app_fonts.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/shell/sheet_look.dart';
import 'package:archive_prototype/shell/sheet_parts.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/detail_shell.dart';
import 'package:archive_prototype/ui/doc_window.dart';
import 'package:archive_prototype/ui/shell_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 문서(위키) 창과 하위 문서 칩 — 지금 연표의 `js/viewer.js` 2691~3009.
// 견본은 두 벌이다:
//   · `docs-moonwake.json` — 내보내기(`scripts/export/docs.mjs`)가 월흔해에서 낸 기록 그대로(항목 기록은 칩이 읽는 값만 남겨 줄였다).
//   · `docs-markup.json`   — 문법을 한자리에 모은 가상 견본(별빛 서고 · 닻별 항구).
// 자료 처리부는 가짜 `ask` 하나로 흉내 낸다 — `{"op":"entity","uid":"doc:<열쇠>"}` · 받침 카드의 주인 `{"op":"entities"}`(진짜 엔진처럼 없는 열쇠는 빼고)
// · 대문 `{"op":"doc_list"}` 말고는 답하지 않는다. [makeBus]의 colors는 주인 항목 기록에 빛깔(`color`)을 얹는다(견본 항목 기록에는 빛깔이 없다).

const pack = 'moonwake-chronicle/';

/// 그림을 뜰 곳 — `--dart-define=OUT=../results/doc9-render`를 줄 때만 뜬다.
/// 지금 연표의 같은 장면은 `prototype/results/dom-doc9/문서-*.png`(1920×1080 · 같은 좌표)다.
const captureTo = String.fromEnvironment('OUT');

/// 검사 환경에는 시스템 글꼴이 없다 — 지금 연표가 이 PC에서 쓰는 글꼴을 파일에서 읽어 같은 이름으로 올린다
/// (`test/render_scene_test.dart`의 `_loadFonts`와 같다).
Future<void> loadFonts() async {
  await loadAppFonts();
  for (final (family, files) in [
    ('Noto Sans KR', ['C:/Windows/Fonts/NotoSansKR-VF.ttf']),
    ('Malgun Gothic', ['C:/Windows/Fonts/malgun.ttf', 'C:/Windows/Fonts/malgunbd.ttf']),
  ]) {
    final loader = FontLoader(family);
    var any = false;
    for (final path in files) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length)));
      any = true;
    }
    if (any) await loader.load();
  }
}

({AppBus bus, List<Map<String, dynamic>> asked}) makeBus({List<String> fixtures = const ['docs-moonwake.json'], Map<String, dynamic>? docList, Map<String, Object> colors = const {}}) {
  final store = <String, Map<String, dynamic>>{};
  for (final name in fixtures) {
    for (final e in jsonDecode(File('test/fixtures/$name').readAsStringSync()) as List) {
      final row = (e as Map).cast<String, dynamic>();
      store[row['uid'] as String] = row;
    }
  }
  final asked = <Map<String, dynamic>>[];
  final controller = TimelineController()..resize(1920, 500);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [
        {'id': 1, 'name': '견본 기록집', 'events': 3},
      ],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('문서 창 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(
    ask: (query) async {
      asked.add(query);
      if (query['op'] == 'entity') {
        final row = store[query['uid']];
        if (row == null) throw StateError('없는 기록: ${query['uid']}');
        return row;
      }
      if (query['op'] == 'doc_list') return docList ?? const {};
      if (query['op'] == 'entities') {
        return {
          'items': [
            for (final uid in (query['uids'] as List).cast<String>())
              if (store[uid] != null)
                {
                  ...store[uid]!,
                  'json': {...(jsonDecode('${store[uid]!['json']}') as Map).cast<String, dynamic>(), if (colors[uid] != null) 'color': colors[uid]},
                },
          ],
        };
      }
      return const {};
    },
    controller: controller,
    scene: scene,
  );
  return (bus: bus, asked: asked);
}

/// 창 하나를 넓은 화면에 띄운다(1920×1080 — 목차 · 본문 · 딸린 항목 세 단이 다 드는 폭).
Future<void> pumpWindow(WidgetTester tester, AppBus bus, {Size size = const Size(1920, 1080)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
      home: Scaffold(
        backgroundColor: Ui.bg,
        body: Stack(children: [const SizedBox.expand(), DocWindow(bus: bus)]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 문서를 열고 뜰 때까지 기다린다.
Future<void> open(WidgetTester tester, AppBus bus, String key) async {
  bus.slot(docSlot).value = key;
  await tester.pumpAndSettle();
}

/// 그 글이 보이도록 본문을 굴린다.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder.first, 150, scrollable: find.byType(Scrollable).last);
}

/// 하위 문서 칩 하나 — 이름으로 고른다(📄와 이름이 다른 글이라 이름으로 찾는다). 문서 창의 칩은 [DocSubChip] · 상세 칸의 칩은 [DocChip].
Finder chipNamed(String name) => find.ancestor(of: find.text(name), matching: find.byWidgetPredicate((w) => w is DocSubChip || w is DocChip));

/// 이전 문서 단추(흰 종이 '← 이전' — 풍선 '이전 문서').
Finder get backButton => find.byTooltip('이전 문서');

/// 견본 하나의 본문을 푼다(문법 검사용).
DocBody bodyOf(String fixture, String uid) {
  for (final e in jsonDecode(File('test/fixtures/$fixture').readAsStringSync()) as List) {
    final row = (e as Map).cast<String, dynamic>();
    if (row['uid'] != uid) continue;
    final record = DocRecord.fromAnswer(row)!;
    return parseDocBody(record.body, links: record.links);
  }
  throw StateError('견본에 없다: $uid');
}

void main() {
  group('문서 기록', () {
    test('답을 풀면 제목 · 곁글 · 하위 문서 · 고리 · 기간이 선다', () {
      final rows = jsonDecode(File('test/fixtures/docs-moonwake.json').readAsStringSync()) as List;
      final row = rows.firstWhere((e) => (e as Map)['uid'] == 'doc:${pack}p-coast-0') as Map;
      final record = DocRecord.fromAnswer(row.cast<String, dynamic>())!;
      expect(record.key, '${pack}p-coast-0');
      expect(record.title, '유리항 패총국');
      expect(record.meta, '국가 · 기원전 960년 ~ 기원전 400년 · 유리해안');
      expect(record.uid, '${pack}p-coast-0');
      expect(record.span, isNotNull);
      expect(record.subs.map((s) => s.label), ['사료', '생활']); // 가나다 차례
      expect(record.links['월흔해 안내서']!.key, '${pack}p-coast-6-guide');
      expect(record.back.single.key, '${pack}p-coast-6-guide//구성요소 길잡이');
      expect(record.empty, isFalse);
    });

    test('칸 문서는 칸 참조와 제 정권을 들고 온다', () {
      final rows = jsonDecode(File('test/fixtures/docs-moonwake.json').readAsStringSync()) as List;
      final row = rows.firstWhere((e) => (e as Map)['uid'] == 'doc:cell:${pack}p-coast-6:leaders:은결 나엔@720') as Map;
      final record = DocRecord.fromAnswer(row.cast<String, dynamic>())!;
      expect(record.title, '은결 나엔');
      expect(record.meta, '은륜 제국 지도자 · 720년 ~ 760년');
      expect(record.uid, '${pack}p-coast-6');
      expect(record.ref, 'leader:0');
      expect(record.crumbs.single.label, '은륜 제국');
    });

    test('기록이 아니면 null', () {
      expect(DocRecord.fromAnswer(const {'uid': 'x', 'kind': 'doc'}), isNull);
      expect(DocRecord.fromAnswer(const {'json': '{"title":"열쇠가 없다"}'}), isNull);
      expect(DocRecord.fromAnswer(const {'json': '깨진 글'}), isNull);
    });
  });

  group('본문 문법', () {
    late DocBody body;
    setUp(() => body = bodyOf('docs-markup.json', 'doc:별빛-서고'));

    test('제목의 단계와 목차 번호', () {
      expect(body.toc.map((h) => h.plain), ['첫 마디', '둘째 마디', '셋째 마디']);
      expect(body.toc.map((h) => h.number), ['1', '1.1', '2']);
      expect(body.toc.map((h) => h.depth), [1, 2, 1]);
      expect(body.toc.first.level, 2);
    });

    test('굵게 · 기울임 · 취소 · 밑줄 · 위아래 첨자', () {
      final spans = body.nodes.whereType<DocParagraph>().first.spans;
      DocSpan of(String text) => spans.firstWhere((s) => s.text == text);
      expect(of('굵은 밤').bold, isTrue);
      expect(of('기울인 밤').italic, isTrue);
      expect(of('지운 밤').strike, isTrue);
      expect(of('그은 밤').underline, isTrue);
      expect(of('아래').low, isTrue);
      expect(of('위').sup, isTrue);
    });

    test('안쪽 고리 — 있는 문서 · 없는 이름 · 아직 빈 문서 · 바깥 주소', () {
      final links = body.nodes.whereType<DocParagraph>().expand((p) => p.spans).where((s) => s.link != null).map((s) => s.link!).toList();
      final found = links.firstWhere((l) => l.name == '닻별 항구');
      expect(found.key, '닻별-항구');
      expect(found.missing, isFalse);
      expect(links.firstWhere((l) => l.name == '사라진 이름').missing, isTrue);
      expect(links.firstWhere((l) => l.name == '아직 빈 곳').empty, isTrue);
      expect(links.firstWhere((l) => l.name.startsWith('https')).url, 'https://example.invalid');
      expect(body.categories, ['서고']);
    });

    test('각주는 번호를 매겨 목록으로 모인다', () {
      expect(body.footnotes.single.label, '1');
      expect(body.footnotes.single.spans.single.text, '이것은 가상의 주석이다.');
      expect(body.footMarked, isTrue); // 본문에 `[각주]`를 적었다
    });

    test('목록은 들여쓰기가 깊이 · 번호는 종류마다 따로', () {
      final list = body.nodes.whereType<DocList>().first;
      expect(list.items.map((i) => i.depth), [0, 0, 1, 0, 0]);
      expect(list.items.map((i) => i.marker), ['•', '•', '•', '1.', '2.']);
      expect(list.items[2].spans.single.text, '더 들어간 조각');
    });

    test('표 — 칸 나누기 · 칸 합치기 · 바탕색', () {
      final tables = body.nodes.whereType<DocTable>().toList();
      expect(tables.length, 2);
      expect(tables.first.rows.length, 2);
      expect(tables.first.rows.first.map((c) => c.spans.single.text), ['이름', '뜻']);
      expect(tables.first.plain, isTrue);
      final merged = tables.last;
      expect(merged.rows.first.single.colspan, 2);
      expect(merged.rows.first.single.background, const Color(0xffd7c18e));
      expect(merged.plain, isFalse);
    });

    test('인용 · 가로줄 · 접기 · 크기 · 색 · 코드', () {
      expect(body.nodes.whereType<DocQuote>().length, 1);
      expect(body.nodes.whereType<DocRule>().length, 1);
      final fold = body.nodes.whereType<DocFold>().single;
      expect(fold.summary.single.text, '접은 이야기');
      expect(fold.body.whereType<DocParagraph>().single.spans.single.text, '접힌 속이다.');
      final tail = body.nodes.whereType<DocParagraph>().last.spans;
      expect(tail.firstWhere((s) => s.text == '크게').scale, 1.25);
      expect(tail.firstWhere((s) => s.text == '작게').scale, .9);
      expect(tail.firstWhere((s) => s.text == '물든 글').color, const Color(0xff596877));
      expect(tail.firstWhere((s) => s.text == '낱말').code, isTrue);
    });

    test('`[목차]`가 적힌 자리를 기억한다', () {
      expect(body.nodes.first, isA<DocTocMark>());
      expect(body.nodes.whereType<DocFootMark>().length, 1);
    });

    test('월흔해의 표 문서도 같은 꼴로 풀린다', () {
      final real = bodyOf('docs-moonwake.json', 'doc:${pack}p-coast-0//사료');
      expect(real.toc.single.plain, '유리항 패총국의 사료');
      final table = real.nodes.whereType<DocTable>().single;
      expect(table.rows.length, 4);
      expect(table.rows.every((r) => r.length == 3), isTrue);
      expect(table.rows[1].first.spans.single.text, '공용 창고 장부');
    });
  });

  group('문서 창', () {
    testWidgets('열쇠를 실으면 열리고 비우면 닫힌다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      expect(find.byType(DocArticle), findsNothing);

      await open(tester, made.bus, '${pack}p-coast-0');
      expect(find.text('유리항 패총국'), findsWidgets);
      expect(find.byType(DocArticle), findsOneWidget);
      expect(made.asked.where((q) => q['op'] == 'entity').single['uid'], 'doc:${pack}p-coast-0');
      // 받침 카드의 주인은 실패가 남지 않는 하나짜리 목록으로 한 번 묻는다.
      expect(made.asked.where((q) => q['op'] == 'entities').single['uids'], ['${pack}p-coast-0']);

      made.bus.slot(docSlot).value = null;
      await tester.pumpAndSettle();
      expect(find.byType(DocArticle), findsNothing);
    });

    testWidgets('머리에 제목 · 곁글 · 자료집 이름', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-0');
      final title = tester.widget<Text>(find.text('유리항 패총국').first);
      expect(title.style!.fontSize, 22);
      expect(title.style!.fontWeight, FontWeight.w700);
      expect(find.textContaining('국가 · 기원전 960년 ~ 기원전 400년 · 유리해안'), findsOneWidget);
      expect(find.textContaining('의 문서'), findsOneWidget);
    });

    testWidgets('하위 문서 칩을 누르면 그 문서로 · ←로 돌아온다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-0');
      expect(chipNamed('생활'), findsOneWidget);

      await tester.tap(chipNamed('생활'));
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, '${pack}p-coast-0//생활');
      expect(find.text('유리항 패총국/생활'), findsOneWidget);
      // 하위 문서에는 빵 부스러기가 선다.
      expect(find.text('›'), findsOneWidget);
      expect(find.text('생활'), findsOneWidget);

      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, '${pack}p-coast-0');
    });

    testWidgets('문서를 닫고 새 문서를 열면 닫은 문서로 돌아가지 않는다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      final window = tester.state<DocWindowState>(find.byType(DocWindow));
      window.open('${pack}p-coast-0');
      await tester.pumpAndSettle();

      window.close();
      await tester.pumpAndSettle();
      expect(window.openKey, isEmpty);
      window.open('track:mw-coast');
      await tester.pumpAndSettle();
      expect(window.openKey, 'track:mw-coast');

      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, 'track:mw-coast');
      expect(window.openKey, 'track:mw-coast');
    });

    testWidgets('열린 문서에서 새 문서로 옮기면 이전 문서로 돌아간다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      final window = tester.state<DocWindowState>(find.byType(DocWindow));
      window.open('${pack}p-coast-0');
      await tester.pumpAndSettle();
      window.open('track:mw-coast');
      await tester.pumpAndSettle();
      expect(window.openKey, 'track:mw-coast');

      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, '${pack}p-coast-0');
      expect(window.openKey, '${pack}p-coast-0');
    });

    testWidgets('빵 부스러기를 누르면 바탕 문서로', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-0//사료');
      await tester.tap(find.text('유리항 패총국').first);
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, '${pack}p-coast-0');
    });

    testWidgets('본문의 안쪽 고리를 누르면 그 문서로', (tester) async {
      final made = makeBus(fixtures: const ['docs-markup.json']);
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '별빛-서고');
      // 고리는 한 문단 안의 글 조각이라 그 글자 자리를 집어 누른다(같은 이름이 역고리 줄에도 있어 본문 안으로 좁힌다).
      await tester.tapOnText(find.textRange.ofSubstring('닻별 항구', descendentOf: find.byType(DocArticle)));
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, '닻별-항구');
      expect(find.text('닻별 항구'), findsWidgets);
    });

    testWidgets('연표에 없는 이름을 누르면 알림 한 줄만 뜬다', (tester) async {
      final made = makeBus(fixtures: const ['docs-markup.json']);
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '별빛-서고');
      final article = tester.widget<DocArticle>(find.byType(DocArticle));
      final missing = article.body.nodes.whereType<DocParagraph>().expand((p) => p.spans).firstWhere((s) => s.link?.name == '사라진 이름');
      expect(missing.link!.missing, isTrue);
    });

    testWidgets('🎯 연표에서 — 고르고 그 기간으로 데려간다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, 'cell:${pack}p-coast-6:leaders:은결 나엔@720');
      // 받침 카드의 이름 탭(주인 = 칸의 정권 '은륜 제국' · 과녁 — 풍선 '연표에서')
      expect(find.descendant(of: find.byTooltip('연표에서'), matching: find.text('은륜 제국')), findsOneWidget);
      await tester.tap(find.byTooltip('연표에서'));
      await tester.pumpAndSettle();
      expect(made.bus.selection.value!.uid, '${pack}p-coast-6');
      expect(made.bus.selection.value!.cell, 'leader:0');
      final go = made.bus.go.value!;
      expect(go.lo, lessThan(go.hi));
      expect(made.bus.slot(docSlot).value, isNull); // 창은 닫힌다
    });

    testWidgets('트랙 문서에는 🎯(이름 탭)가 없다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, 'track:mw-coast');
      expect(find.text('유리해안'), findsWidgets);
      expect(find.byTooltip('연표에서'), findsNothing);
    });

    testWidgets('본문이 없으면 안내와 설명만', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '${pack}myth-refuted');
      expect(find.text('아직 문서가 없습니다.'), findsOneWidget);
      expect(find.text('설명'), findsOneWidget);
      expect(find.byType(DocArticle), findsNothing);
    });

    testWidgets('없는 문서는 창을 열지 않고 알린다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '없는-열쇠');
      expect(find.byType(DocArticle), findsNothing);
      expect(made.bus.slot(slotNotice).value, '문서를 찾을 수 없습니다.');
      expect(made.bus.slot(docSlot).value, isNull);
    });

    testWidgets('닫기 단추로 닫는다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-0');
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, isNull);
      expect(find.byType(DocArticle), findsNothing);
    });

    testWidgets('목차는 옆에 서고 좁으면 본문 위로 간다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-6-guide');
      expect(find.byType(DocToc), findsWidgets);
      final toc = tester.getTopLeft(find.byType(DocToc).first);
      final article = tester.getTopLeft(find.byType(DocArticle));
      expect(toc.dx, lessThan(article.dx)); // 넓으면 왼쪽에

      await tester.binding.setSurfaceSize(const Size(700, 900));
      await tester.pumpAndSettle();
      addTearDown(() => tester.binding.setSurfaceSize(null));
      expect(tester.getTopLeft(find.byType(DocToc).first).dy, lessThan(tester.getTopLeft(find.byType(DocArticle)).dy));
    });

    testWidgets('명령 — W(고른 항목) · 트랙 문서 · Esc', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      made.bus.select('${pack}p-coast-0');
      runCommand(made.bus, Cmd.wiki, uid: '${pack}p-coast-0');
      await tester.pumpAndSettle();
      expect(find.text('유리항 패총국'), findsWidgets);

      runCommand(made.bus, Cmd.close);
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, isNull);

      made.bus.slot('tracks').value = {
        'mw-coast': {'name': '유리해안', 'color': 0xa0bcc5},
        '3': {'name': '유리해안', 'color': 0xa0bcc5},
      };
      runCommand(made.bus, Cmd.trackWiki, trackId: 3);
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, 'track:mw-coast');
      expect(find.text('유리해안'), findsWidgets);
    });
  });

  // 2026-10-16 감독 "문서 기능과 함께 볼 수 있는 기능 부활" → 갈래 '가'(상세 칸 자리에 붙은 칸) · "문서 한번에 나란히 볼 수 있게 하는 대문".
  group('나란히 · 대문', () {
    /// 창 밑에 연표 대신 누름을 세는 바닥을 깐다(나란히일 때 칸 밖은 그대로 눌려야 한다).
    Future<List<Offset>> pumpOverGround(WidgetTester tester, AppBus bus, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final taps = <Offset>[];
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
          home: Scaffold(
            backgroundColor: Ui.bg,
            body: Stack(
              children: [
                Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTapDown: (d) => taps.add(d.globalPosition))),
                DocWindow(bus: bus, top: 60),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return taps;
    }

    const items = {
      'items': [
        {'key': 'track:mw-coast', 'title': '유리해안', 'group': 'track', 'head': '유리해안의 줄 이야기.'},
        {'key': '${pack}p-coast-0', 'title': '유리항 패총국', 'group': 'period', 'meta': '국가 · 기원전 960년', 'span': [-100, 0], 'subs': 2,
          'head': "== 개요 ==\n'''유리항 패총국'''은 바닷가의 나라다.[* 견본]"},
        {'key': '${pack}p-old', 'title': '먼 옛 나라', 'group': 'period', 'span': [-900, -500], 'head': '가장 이른 나라.'},
      ],
    };

    testWidgets('나란히면 맨 위 띠 아래 오른쪽에 붙은 760 칸 — 칸 밖은 그대로 눌린다 · 좁으면 덮는다', (tester) async {
      final made = makeBus();
      made.bus.slot(docSideSlot).value = true;
      final taps = await pumpOverGround(tester, made.bus, const Size(1920, 1080));
      await open(tester, made.bus, '${pack}p-coast-0');
      final head = tester.getTopLeft(find.text('유리항 패총국').first);
      expect(head.dx, greaterThan(1920 - DocUi.sideWidth));
      expect(head.dy, greaterThan(60));
      await tester.tapAt(const Offset(300, 500));
      expect(taps, [const Offset(300, 500)]);

      await tester.binding.setSurfaceSize(const Size(1100, 900)); // 1100 − 760 < 480 → 덮는다
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('유리항 패총국').first).dx, lessThan(200));
    });

    testWidgets('머리의 기호 단추가 나란히 ↔ 넓게를 뒤집는다', (tester) async {
      final made = makeBus();
      made.bus.slot(docSideSlot).value = true;
      await pumpOverGround(tester, made.bus, const Size(1920, 1080));
      await open(tester, made.bus, '${pack}p-coast-0');
      await tester.tap(find.text('넓게 보기'));
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSideSlot).value, false);
      expect(tester.getTopLeft(find.text('유리항 패총국').first).dx, lessThan(1920 - DocUi.sideWidth)); // 덮는 창 — 세 단이 가운데
      await tester.tap(find.text('나란히 보기'));
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSideSlot).value, true);
    });

    testWidgets('나란히면 🎯 연표에서를 눌러도 문서는 그대로', (tester) async {
      final made = makeBus();
      made.bus.slot(docSideSlot).value = true;
      await pumpOverGround(tester, made.bus, const Size(1920, 1080));
      await open(tester, made.bus, '${pack}p-coast-0');
      await tester.tap(find.byTooltip('연표에서'));
      await tester.pumpAndSettle();
      expect(made.bus.selection.value?.uid, '${pack}p-coast-0');
      expect(made.bus.slot(docSlot).value, '${pack}p-coast-0');
    });

    testWidgets('대문 — 갈래별 카드(나라가 트랙보다 먼저 · 안에서는 때 차례) · 카드를 누르면 그 문서 · ←로 대문', (tester) async {
      final made = makeBus(docList: items);
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, docFrontKey);
      expect(find.text('문서 대문'), findsOneWidget);
      expect(find.text('문서 3개'), findsOneWidget);
      expect(tester.getTopLeft(find.text('나라')).dy, lessThan(tester.getTopLeft(find.text('트랙')).dy));
      expect(tester.getTopLeft(find.text('먼 옛 나라')).dx, lessThan(tester.getTopLeft(find.text('유리항 패총국')).dx));
      expect(find.text('유리항 패총국은 바닷가의 나라다.'), findsOneWidget); // 제목 · 각주를 뺀 앞부분
      expect(find.text('대문'), findsNothing); // 대문에서는 대문 단추가 없다

      await tester.tap(find.widgetWithText(DocFrontCard, '유리항 패총국'));
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, '${pack}p-coast-0');
      expect(find.byType(DocArticle), findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, docFrontKey);
      expect(find.byType(DocFrontCard), findsNWidgets(3));
    });

    testWidgets('문서의 대문 단추 · 고른 것 없는 W 명령은 대문으로', (tester) async {
      final made = makeBus(docList: items);
      await pumpWindow(tester, made.bus);
      runCommand(made.bus, Cmd.wiki);
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, docFrontKey);
      await open(tester, made.bus, '${pack}p-coast-0');
      await tester.tap(find.text('대문'));
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, docFrontKey);
    });

    testWidgets('문서가 없는 서재 — 창은 열고 까닭을 적는다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, docFrontKey);
      expect(find.textContaining('문서가 없습니다'), findsOneWidget);
      expect(find.byType(DocFrontCard), findsNothing);
    });

    test('앞부분은 문단과 목록의 글만', () {
      expect(docLead("== 개요 ==\n'''한기'''는 들판[* 각주]의 나라다.\n\n * 하나\n * 둘\n|| 표 || 칸 ||"), '한기는 들판의 나라다. 하나 둘');
      expect(docLead(''), '');
    });
  });

  // 서고 꼴(감독 고름 G5 #9 · 다듬기 판 sht-doc — 목업 g-sheet-tree `drawDoc`): 받침 카드 · 머리 · 세 단 · 딸린 항목 · 대문.
  // 1920×1080 · 100% · 맨 위 띠 60 아래(창 자리 12 · 72 ~ 1908 · 1064).
  group('서고 꼴의 자리와 빛깔', () {
    final shot = GlobalKey();

    Future<void> pumpStage(WidgetTester tester, AppBus bus) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
          home: Scaffold(
            backgroundColor: Ui.bg,
            body: RepaintBoundary(
              key: shot,
              child: Stack(children: [const SizedBox.expand(), DocWindow(bus: bus, padding: const EdgeInsets.fromLTRB(12, Ui.top + 12, 12, 16), top: Ui.top)]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// 화면 그림의 화소 몇(1배) — 받침 카드 · 흰 종이의 빛깔을 그대로 본다.
    Future<List<Color>> pixels(WidgetTester tester, List<Offset> at) async {
      late List<Color> out;
      await tester.runAsync(() async {
        final image = await tester.renderObject<RenderRepaintBoundary>(find.byKey(shot)).toImage();
        final data = (await image.toByteData())!;
        out = [
          for (final p in at)
            () {
              final i = (p.dy.toInt() * image.width + p.dx.toInt()) * 4;
              return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
            }(),
        ];
        image.dispose();
      });
      return out;
    }

    testWidgets('받침 카드: 주인의 빛깔(칠 24% · 테 84%)이 흰 종이 위 · 오른쪽으로 6 · 오른쪽 끝 이름 탭(주인 이름 + 과녁)을 누르면 연표에서', (tester) async {
      const color = Color(0xffa0bcc5);
      final made = makeBus(colors: {'${pack}p-coast-0': '#a0bcc5'});
      await pumpStage(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-0');
      final window = tester.state<DocWindowState>(find.byType(DocWindow));
      expect(window.owner!.name, '유리항 패총국');
      expect(window.owner!.color, color);
      final card = tester.widget<SheetCard>(find.byType(SheetCard));
      expect(card.color, color);
      expect(SheetCard.fillOf(card.color), SheetLook.tagFill(color));
      expect(SheetCard.edgeOf(card.color), SheetLook.tagEdge(color));
      // 카드 자리: 창 자리(12, 72 ~ 1908, 1064) — 탭 18 · 카드 윗변 90 · 흰 종이 96 · 카드는 오른쪽으로 6 더(1908).
      final cardBox = tester.getRect(find.byType(SheetCard));
      expect(cardBox, const Rect.fromLTRB(12, 72, 1908, 1064));
      // 화소: 오른쪽 띠(종이 밖 · 카드 안)는 카드 칠 · 위 띠도 카드 칠 · 종이 안은 흰 · 카드 오른쪽 테 · 종이 오른쪽 테(먹 25).
      final px = await pixels(tester, [const Offset(1904, 600), const Offset(600, 93), const Offset(100, 600), const Offset(1907, 600), const Offset(1901, 600)]);
      expect(px[0], SheetLook.tagFill(color), reason: '오른쪽으로 드러난 카드');
      expect(px[1], SheetLook.tagFill(color), reason: '위로 드러난 카드');
      expect(px[2], SheetLook.paper, reason: '흰 종이');
      expect(px[3], SheetLook.tagEdge(color), reason: '카드 오른쪽 테');
      expect(px[4], SheetLook.ink25, reason: '종이 오른쪽 테');
      // 이름 탭: 카드 오른쪽 테에서 10 안 · 위 72 · 주인 이름 + 과녁 · 풍선 '연표에서'
      final tab = tester.getRect(find.byTooltip('연표에서'));
      expect(tab.right, 1908 - SheetCard.tabInset);
      expect(tab.top, 72);
      expect(find.descendant(of: find.byTooltip('연표에서'), matching: find.text('유리항 패총국')), findsOneWidget);
      expect(find.descendant(of: find.byTooltip('연표에서'), matching: find.byWidgetPredicate((w) => w is LineIcon && w.glyph == LineGlyph.locate)), findsOneWidget);
      await tester.tap(find.byTooltip('연표에서'));
      await tester.pumpAndSettle();
      expect(made.bus.selection.value!.uid, '${pack}p-coast-0');
      expect(made.bus.go.value, isNotNull);
    });

    testWidgets('주인 없는 문서(트랙)는 먹 카드(칠 먹 4 · 테 먹 25) · 이름 탭 없음 · 주인을 묻지 않음', (tester) async {
      final made = makeBus();
      await pumpStage(tester, made.bus);
      await open(tester, made.bus, 'track:mw-coast');
      expect(tester.state<DocWindowState>(find.byType(DocWindow)).owner, isNull);
      expect(tester.widget<SheetCard>(find.byType(SheetCard)).color, isNull);
      expect(made.asked.where((q) => q['op'] == 'entities'), isEmpty);
      expect(find.byTooltip('연표에서'), findsNothing);
      final px = await pixels(tester, [const Offset(1904, 600), const Offset(600, 93), const Offset(1907, 600)]);
      expect(px[0], SheetLook.ink4);
      expect(px[1], SheetLook.ink4);
      expect(px[2], SheetLook.ink25);
    });

    testWidgets('주인 기록에 빛깔이 없으면 먹 카드 · 이름 탭은 주인 이름(칸 문서는 그 정권)', (tester) async {
      final made = makeBus();
      await pumpStage(tester, made.bus);
      await open(tester, made.bus, 'cell:${pack}p-coast-6:leaders:은결 나엔@720');
      final owner = tester.state<DocWindowState>(find.byType(DocWindow)).owner!;
      expect(owner.name, '은륜 제국');
      expect(owner.color, isNull);
      expect(find.descendant(of: find.byTooltip('연표에서'), matching: find.text('은륜 제국')), findsOneWidget);
    });

    testWidgets('세 단: 목차 상자 220 · 본문 780 · 딸린 항목 256 · 사이 32 · 흰 종이 가운데 · 머리는 세 단과 같은 폭', (tester) async {
      final made = makeBus();
      await pumpStage(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-0');
      // 흰 종이 12 ~ 1902(안쪽 13 ~ 1901 · 폭 1888) · 단 모두 220 + 32 + 780 + 32 + 256 = 1320 → 왼쪽 13 + 284
      const left = 13.0 + (1888 - 1320) ~/ 2;
      final toc = tester.getRect(find.ancestor(of: find.byType(DocToc), matching: find.byType(SheetBox)).first);
      expect(toc.left, left);
      expect(toc.width, DocUi.tocColumn);
      final article = tester.getRect(find.byType(DocArticle));
      expect(article.left, left + DocUi.tocColumn + DocUi.columnGap);
      expect(article.width, DocUi.articleWidth);
      final subs = tester.getRect(find.ancestor(of: find.byType(DocSubChip).first, matching: find.byType(SheetBox)).first);
      expect(subs.left, article.right + DocUi.columnGap);
      expect(subs.width, DocUi.asideColumn);
      expect(subs.top, toc.top, reason: '목차 · 딸린 항목 상자는 같은 줄에서 시작');
      // 머리: 제목 22 굵게가 목차 왼쪽에 · 단추 넷(← 이전 · 대문 · 나란히 보기 · 닫기)의 오른쪽 끝이 딸린 항목 오른쪽 끝에
      final title = tester.widget<Text>(find.text('유리항 패총국').first);
      expect(title.style!.fontSize, DocUi.title);
      expect(title.style!.fontWeight, FontWeight.w700);
      expect(tester.getTopLeft(find.text('유리항 패총국').first).dx, left);
      expect(tester.getRect(find.ancestor(of: find.text('닫기'), matching: find.byType(SheetPaperButton))).right, subs.right);
      for (final label in ['← 이전', '대문', '나란히 보기']) {
        expect(find.ancestor(of: find.text(label), matching: find.byType(SheetPaperButton)), findsOneWidget, reason: label);
      }
      // 목차 상자 · 하위 문서 상자 · 가리키는 문서 상자의 뚜껑 흰 라벨
      for (final label in ['목차', '하위 문서', '가리키는 문서']) {
        expect(find.descendant(of: find.byType(SheetLidLabel), matching: find.text(label)), findsOneWidget, reason: label);
      }
    });

    testWidgets('하위 문서 = 뚜껑 매듭에서 내려온 실에 매단 흰 종이 칩(구멍 · 테 먹 45) · 누르면 그 하위 문서', (tester) async {
      final made = makeBus();
      await pumpStage(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-6-guide');
      expect(find.byType(DocSubChip), findsNWidgets(5));
      expect(find.descendant(of: find.byType(SheetThreadColumn), matching: find.byType(DocSubChip)), findsNWidgets(5), reason: '실 기둥에 꿰었다');
      expect(find.text('5'), findsWidgets); // 뚜껑의 수
      final shape = DocSubChip.shapeOf();
      expect((shape.hole, shape.stroke, shape.fill, shape.dash), (true, SheetLook.ink45, SheetLook.paper, null));
      final chips = [for (final e in find.byType(DocSubChip).evaluate()) tester.getRect(find.byWidget(e.widget))];
      for (var i = 1; i < chips.length; i++) {
        expect(chips[i].top - chips[i - 1].bottom, DocUi.chipGap);
        expect(chips[i].left, chips[0].left);
      }
      expect(chips.first.height, DocUi.chip);
      await tester.tap(chipNamed('문서 표현'));
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, '${pack}p-coast-6-guide//문서 표현');
    });

    testWidgets('나란히(760)에서는 딸린 항목이 본문 밑으로 · 목차는 본문 위로', (tester) async {
      final made = makeBus();
      made.bus.slot(docSideSlot).value = true;
      await pumpStage(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-0');
      final card = tester.getRect(find.byType(SheetCard));
      expect(card, Rect.fromLTRB(1920 - DocUi.sideWidth + DocUi.sideInset, Ui.top + DocUi.sideInset, 1920 - DocUi.sideInset, 1080 - DocUi.sideInset));
      final article = tester.getRect(find.byType(DocArticle));
      final toc = tester.getRect(find.byType(DocToc).first);
      expect(toc.bottom, lessThan(article.top), reason: '목차가 본문 위');
      await reveal(tester, find.byType(DocSubChip).first);
      final subs = tester.getRect(find.ancestor(of: find.byType(DocSubChip).first, matching: find.byType(SheetBox)).first);
      expect(subs.top, greaterThan(tester.getRect(find.byType(DocArticle)).bottom), reason: '딸린 항목이 본문 밑');
      expect(subs.left, tester.getRect(find.byType(DocArticle)).left);
      expect(subs.width, tester.getRect(find.byType(DocArticle)).width);
    });

    testWidgets('대문 = 갈래 상자(뚜껑 흰 라벨 = 갈래 이름 + 수) + 흰 종이 카드(테 먹 25 · 올리면 먹 45)', (tester) async {
      final made = makeBus(docList: const {
        'items': [
          {'key': 'track:mw-coast', 'title': '유리해안', 'group': 'track', 'head': '유리해안의 줄 이야기.'},
          {'key': '${pack}p-coast-0', 'title': '유리항 패총국', 'group': 'period', 'meta': '국가', 'span': [-100, 0], 'subs': 2, 'head': '바닷가의 나라.'},
          {'key': '${pack}p-old', 'title': '먼 옛 나라', 'group': 'period', 'span': [-900, -500], 'head': '가장 이른 나라.'},
        ],
      });
      await pumpStage(tester, made.bus);
      await open(tester, made.bus, docFrontKey);
      Finder boxOf(String name) => find.ancestor(of: find.descendant(of: find.byType(SheetLidLabel), matching: find.text(name)), matching: find.byType(SheetBox));
      expect(find.descendant(of: boxOf('나라'), matching: find.byType(DocFrontCard)), findsNWidgets(2));
      expect(find.descendant(of: boxOf('트랙'), matching: find.byType(DocFrontCard)), findsOneWidget);
      expect(tester.widget<SheetCard>(find.byType(SheetCard)).color, isNull, reason: '대문은 주인이 없다');
      expect(find.byTooltip('연표에서'), findsNothing);
      expect(DocFrontCard.shapeOf().stroke, SheetLook.ink25);
      expect(DocFrontCard.shapeOf(hover: true).stroke, SheetLook.ink45);
      expect(DocFrontCard.shapeOf(hover: true).fill, SheetLook.ink4);
      expect(tester.getSize(find.byType(DocFrontCard).first).height, DocUi.frontCardHeight);
    });

    testWidgets('표는 상자 꼴 — 네 귀 모따기 6 · 테 먹 25 · 칸 금 먹 12 · 바탕색 없는 표의 머리 칸(두 칸 표 = 첫 열 · 세 칸 넘는 표 = 첫 줄)은 칠 먹 4 · 글 먹 60', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 700, child: SingleChildScrollView(child: DocArticle(body: parseDocBody('|| 도읍 || 설원성 ||\n|| 황실 || 온씨 ||\n')))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DocTableBox), findsOneWidget);
      BoxDecoration cellOf(String text) => tester.widget<Container>(find.ancestor(of: find.text(text), matching: find.byType(Container)).first).decoration! as BoxDecoration;
      expect(cellOf('도읍').color, SheetLook.ink4);
      expect(cellOf('황실').color, SheetLook.ink4);
      expect(cellOf('설원성').color, isNull);
      expect((cellOf('도읍').border! as Border).right.color, SheetLook.ink12);
      // 머리 칸의 글은 먹 60(목업 drawDoc) · 값 칸은 본문 글빛 그대로.
      Color? inkOf(String text) => (tester.widget<Text>(find.text(text)).textSpan! as TextSpan).children!.first.style!.color;
      expect(inkOf('도읍'), SheetLook.ink60);
      expect(inkOf('설원성'), Ui.text);

      // 세 칸 넘는 자료 표(바탕색 없음)는 첫 줄이 머리 칸.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 700, child: SingleChildScrollView(child: DocArticle(body: parseDocBody('|| 차례 || 이름 || 행방 ||\n|| 첫째 || 새벽 || 하연 ||\n')))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final head in ['차례', '이름', '행방']) {
        expect(cellOf(head).color, SheetLook.ink4, reason: head);
        expect(inkOf(head), SheetLook.ink60, reason: head);
      }
      for (final body in ['첫째', '새벽', '하연']) {
        expect(cellOf(body).color, isNull, reason: body);
      }
    });

    test('머리 칸 — 두 칸 표는 첫 열 · 세 칸 넘는 표는 첫 줄 · 쓴 이가 바탕색을 준 표 · 한 칸 표는 더 칠하지 않는다', () {
      DocGrid gridOf(String src) => parseDocBody(src).nodes.whereType<DocTable>().single.grid;
      List<bool> headOf(DocGrid g) => [for (final p in g.cells) docTableHead(g, p)];
      // 두 칸(목업의 이름 · 값 정보 표) — 첫 열. 줄 전체를 합친 제목 줄(`<-2>`)은 머리 열이 아니다.
      expect(headOf(gridOf('|| 가 || 나 ||\n|| 다 || 라 ||\n')), [true, false, true, false]);
      expect(headOf(gridOf('||<-2> 제목 ||\n|| 도읍 || 설원성 ||\n')), [false, true, false]);
      // 세 칸 이상(자료 표 — 등불 견본의 '다섯 시대' · '아홉 불씨') — 첫 줄.
      expect(headOf(gridOf('|| 차례 || 이름 || 행방 ||\n|| 첫째 || 새벽 || 하연 ||\n|| 둘째 || 한낮 || 설원 ||\n')), [true, true, true, false, false, false, false, false, false]);
      expect(headOf(gridOf('|| 가 || 나 || 다 ||\n')), [false, false, false], reason: '한 줄뿐인 표는 머리를 짐작하지 않는다');
      // 쓴 이가 바탕색을 준 표 · 한 칸 표 — 칠하지 않는다.
      expect(headOf(gridOf('||<bgcolor=#f5f2eb> 가 || 나 ||\n|| 다 || 라 ||\n')), [false, false, false, false]);
      expect(headOf(gridOf('|| 혼자 ||\n|| 둘째 ||\n')), [false, false]);
    });

    test('단 나눔 — 세 단 · 딸린 항목 밑 · 목차 위', () {
      final wide = DocColumns.of(1832, toc: true, aside: true);
      expect((wide.tocBeside, wide.asideBeside, wide.article, wide.width), (true, true, 780.0, 1320.0));
      final mid = DocColumns.of(1200, toc: true, aside: true); // 1320에 못 미침 → 딸린 항목은 본문 밑
      expect((mid.tocBeside, mid.asideBeside, mid.article, mid.width), (true, false, 780.0, 1032.0));
      final side = DocColumns.of(688, toc: true, aside: true); // 나란히 칸 — 목차도 본문 위
      expect((side.tocBeside, side.asideBeside, side.article, side.width), (false, false, 688.0, 688.0));
      final noToc = DocColumns.of(1200, toc: false, aside: true);
      expect((noToc.tocBeside, noToc.asideBeside, noToc.article, noToc.width), (false, true, 780.0, 1068.0));
    });

    testWidgets('목차 — 번호 칸은 같은 깊이끼리 같은 폭 · 깊은 줄은 위 깊이의 번호 칸만큼 들임 · 줄 26', (tester) async {
      final body = parseDocBody('== 하나 ==\n글\n=== 둘의 하나 ===\n글\n=== 둘의 둘 ===\n글\n== 셋 ==\n글\n== 넷 ==\n글\n== 다섯 ==\n글\n== 여섯 ==\n글\n== 일곱 ==\n글\n== 여덟 ==\n글\n== 아홉 ==\n글\n== 열 ==\n글\n');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SizedBox(width: DocUi.tocColumn, child: docTocBox(body.toc, (_) async {}))),
        ),
      );
      await tester.pumpAndSettle();
      Rect textOf(String s) => tester.getRect(find.text(s));
      expect(textOf('하나').left, textOf('열').left, reason: '1과 10의 제목이 한 줄에 선다');
      expect(textOf('1.1').left, textOf('하나').left, reason: '둘째 깊이의 번호는 첫 깊이의 제목 자리에서');
      expect(textOf('둘의 하나').left, textOf('둘의 둘').left);
      final rows = find.descendant(of: find.byType(DocToc), matching: find.byType(SheetPress));
      expect(tester.getSize(rows.first).height, DocUi.tocRow);
    });

    // 바꾸지 않는 길: 본문의 글꼴 · 제목 크기는 서고 꼴에서도 그대로(걸음 8까지 '지금 연표와 자리 대조'에 있던 검사 — 자리 검사는 위 '세 단'이 맡는다).
    testWidgets('본문의 글꼴 — 제목 단계마다의 크기와 문단 여백', (tester) async {
      final made = makeBus();
      await pumpStage(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-0');
      // `== … ==`는 `<h3>`(1.25em = 19.375) · `=== … ===`는 `<h4>`(1.1em = 17.05)
      double sizeOf(String head) {
        // 같은 글이 목차에도 있으므로 본문 안으로 좁힌다.
        final rich = tester.widgetList<RichText>(find.descendant(of: find.byType(DocArticle), matching: find.byType(RichText))).firstWhere((r) => r.text.toPlainText().trim() == head);
        double size = 0;
        rich.text.visitChildren((span) {
          if (size == 0 && span is TextSpan && (span.text ?? '').isNotEmpty && span.style?.fontSize != null) size = span.style!.fontSize!;
          return true;
        });
        return size;
      }

      expect(sizeOf('1. 유리항 패총국'), closeTo(18.75, 1e-6));
      expect(sizeOf('1.1. 제도와 생활'), closeTo(16.5, 1e-6));
      // 본문 글꼴 — 명조 15 · 줄 높이 24(`.wiki-article` · `.wk`)
      final article = tester.widget<DocArticle>(find.byType(DocArticle));
      expect(article.body.toc.first.level, 2);
      expect(DocUi.font, 15);
      expect(DocUi.lineHeight, 24 / 15);
    });

    testWidgets('`[목차]` 자리의 목차 상자 — 뚜껑 \'목차\' · 글에 맞춘 폭(220 ~ 360) · 본문 왼쪽 · 줄 26 · 줄을 누르면 그 제목으로', (tester) async {
      Future<void> pumpArticle(String src) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(width: DocUi.articleWidth, height: 600, child: SingleChildScrollView(child: DocArticle(body: parseDocBody(src)))),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Finder tocBox() => find.descendant(of: find.byType(DocArticle), matching: find.ancestor(of: find.byType(DocToc), matching: find.byType(SheetBox)));
      // 짧은 제목들 — 가장 좁은 폭 220
      await pumpArticle('[목차]\n== 하나 ==\n글\n=== 둘의 하나 ===\n글\n== 셋 ==\n${'긴 문단. ' * 300}\n== 넷 ==\n끝 글\n');
      expect(tocBox(), findsOneWidget);
      final box = tester.getRect(tocBox());
      expect(box.width, DocUi.inlineTocMin);
      expect(box.left, tester.getRect(find.byType(DocArticle)).left);
      expect(find.descendant(of: tocBox(), matching: find.descendant(of: find.byType(SheetLidLabel), matching: find.text('목차'))), findsOneWidget);
      final rows = find.descendant(of: find.byType(DocToc), matching: find.byType(SheetPress));
      expect(rows, findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        expect(tester.getSize(rows.at(i)).height, DocUi.tocRow);
      }
      // 줄을 누르면 그 제목이 보이도록 미끄러진다(본문 끝의 '넷').
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(scroll.pixels, 0);
      await tester.tap(find.descendant(of: find.byType(DocToc), matching: find.text('넷')));
      await tester.pumpAndSettle();
      expect(scroll.pixels, greaterThan(0));
      // 긴 제목 — 가장 넓은 폭 360에서 줄이 바뀌고 넘치지 않는다.
      await pumpArticle('[목차]\n== 아주 긴 제목이 목차 상자의 가장 넓은 폭을 넘어서 줄이 바뀌어야 하는 때의 제목 ==\n글\n');
      expect(tester.getRect(tocBox()).width, DocUi.inlineTocMax);
      expect(tester.takeException(), isNull);
    });

    testWidgets('각주 위 가름 금은 짧게 — 폭 200 · 먹 25(제목 밑금은 본문 폭 · 먹 12)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: DocUi.articleWidth, child: SingleChildScrollView(child: DocArticle(body: parseDocBody('== 하나 ==\n글[* 각주 글]\n')))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rule = find.descendant(of: find.byType(DocArticle), matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == SheetLook.ink25));
      expect(rule, findsOneWidget);
      expect(tester.getSize(rule), const Size(DocUi.footRule, 1));
      expect(tester.getTopLeft(rule).dx, tester.getTopLeft(find.byType(DocArticle)).dx);
      expect(tester.getTopLeft(rule).dy, lessThan(tester.getTopLeft(find.textContaining('각주 글', findRichText: true)).dy));
    });

    test('주인 — 빛깔은 항목 기록의 color · 없으면 x_polity · 이름은 name · title · 물러설 이름', () {
      expect(docColor('#a0bcc5'), const Color(0xffa0bcc5));
      expect(docColor('#abc'), const Color(0xffaabbcc));
      expect(docColor(0xa0bcc5), const Color(0xffa0bcc5));
      expect(docColor(''), isNull);
      expect(docColor('붉음'), isNull);
      final event = DocOwner.of(const {
        'title': '불씨 맹약',
        'color': '',
        'x_polity': {'name': '등불 왕국', 'color': '#d7c18e'},
      }, '물러설 이름');
      expect((event.name, event.color), ('불씨 맹약', const Color(0xffd7c18e)));
      final none = DocOwner.of(null, '물러설 이름');
      expect((none.name, none.color), ('물러설 이름', null));
    });
  });

  // 휴대폰 · 좁은 창 — 종이 안 폭이 [DocUi.compact] 560보다 좁으면 머리 단추 넷이 제목 위 제 줄에 선다.
  // 320 폭이면 종이 안이 232라 단추 넷(약 243 ~ 256)이 한 줄에 들지 않는다 — 넘치지 않고 종이 안에서 줄을 바꾼다.
  // 글꼴은 시험 기본 글꼴(진짜 글꼴보다 넓다)이라 실기기보다 빡빡하게 본다.
  group('휴대폰 폭', () {
    Finder buttonOf(String label) => find.ancestor(of: find.text(label), matching: find.byType(SheetPaperButton));
    final titleText = find.byWidgetPredicate((w) => w is Text && w.data == '유리항 패총국' && w.style?.fontSize == DocUi.title);

    for (final (w, h, scale) in const [(320.0, 700.0, 1.0), (360.0, 780.0, 1.0), (412.0, 915.0, 1.0), (360.0, 780.0, 1.3)]) {
      testWidgets('문서 창 머리 — ${w.toInt()}×${h.toInt()} · 글자 배율 $scale: 단추 넷이 제목 위 · 종이 안 · 넘침 없음', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final made = makeBus();
        await pumpWindow(tester, made.bus, size: Size(w, h));
        await open(tester, made.bus, '${pack}p-coast-0');
        expect(tester.takeException(), isNull);
        final card = tester.getRect(find.byType(SheetCard));
        final page = SheetCard.pageRect(card.size).shift(card.topLeft);
        expect(titleText, findsOneWidget);
        final title = tester.getRect(titleText);
        for (final label in ['← 이전', '대문', '나란히 보기', '닫기']) {
          final b = tester.getRect(buttonOf(label));
          expect(b.left, greaterThanOrEqualTo(page.left), reason: '$label — 종이 왼쪽 안');
          expect(b.right, lessThanOrEqualTo(page.right), reason: '$label — 종이 오른쪽 안');
          expect(b.bottom, lessThanOrEqualTo(title.top), reason: '$label — 제목 위 제 줄');
        }
        // 이름 탭(연표에서)도 카드 안 — 카드 왼쪽 모따기를 넘지 않는다.
        final tab = tester.getRect(find.byTooltip('연표에서'));
        expect(tab.left, greaterThanOrEqualTo(card.left + SheetCard.peek + SheetCard.chamfer));
        // 단추는 여전히 눌린다 — 닫기.
        await tester.tap(buttonOf('닫기'));
        await tester.pumpAndSettle();
        expect(made.bus.slot(docSlot).value, isNull);
      });
    }

    testWidgets('받침 카드의 이름 탭은 좁은 카드에서 카드 폭을 넘지 않고 이름을 줄인다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 260,
                height: 200,
                child: SheetCard(tab: '아주 긴 주인 이름이 이어지는 나라' * 4, onTab: () {}, tabHint: '연표에서', child: const SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(SheetCard));
      final tab = tester.getRect(find.byTooltip('연표에서'));
      expect(tab.right, card.right - SheetCard.tabInset);
      expect(tab.left, greaterThanOrEqualTo(card.left + SheetCard.peek + SheetCard.chamfer));
      // 넓은 카드에서는 그대로 가장 넓어도 320.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 1200,
                height: 200,
                child: SheetCard(tab: '아주 긴 주인 이름이 이어지는 나라' * 4, onTab: () {}, tabHint: '연표에서', child: const SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byTooltip('연표에서')).width, SheetCard.tabMax);
    });
  });

  // 1920×1080 그림 뜨기 — 지금 연표의 `results/dom-doc9/문서-*.png`와 같은 좌표다(`side-by-side.mjs`로 나란히 놓는다).
  testWidgets(
    '그림 뜨기(OUT을 줄 때만)',
    (tester) async {
      await loadFonts();
      final made = makeBus(
        colors: {'${pack}p-coast-0': '#a0bcc5', '${pack}p-coast-6': '#c9a7d8'},
        docList: const {
          'items': [
            {'key': 'track:mw-coast', 'title': '유리해안', 'group': 'track', 'head': '유리해안의 줄 이야기.'},
            {'key': '${pack}p-coast-0', 'title': '유리항 패총국', 'group': 'period', 'meta': '국가 · 기원전 960년', 'span': [-100, 0], 'subs': 2, 'head': "'''유리항 패총국'''은 바닷가의 나라다."},
            {'key': '${pack}p-coast-6', 'title': '은륜 제국', 'group': 'period', 'meta': '국가', 'span': [-50, 0], 'subs': 2, 'head': '은륜 제국은 달 조각의 나라다.'},
            {'key': '${pack}p-coast-6-guide', 'title': '월흔해 안내서', 'group': 'event', 'meta': '사건 · 842년', 'subs': 5, 'head': '월흔해는 이 DLC를 위해 만든 판타지 세계다.'},
          ],
        },
      );
      final key = GlobalKey();
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
          home: Scaffold(
            backgroundColor: Ui.bg,
            body: RepaintBoundary(
              key: key,
              child: Stack(children: [const SizedBox.expand(), DocWindow(bus: made.bus, padding: const EdgeInsets.fromLTRB(12, Ui.top + 12, 12, 16), top: Ui.top)]),
            ),
          ),
        ),
      );
      final folder = Directory(captureTo)..createSync(recursive: true);
      // 넓게(연표를 덮는 창) 여섯 + 대문 · 나란히(760 — 딸린 항목이 본문 밑) 둘.
      for (final (name, docKey) in [
        ('기본', '${pack}p-coast-0'),
        ('표', '${pack}p-coast-0//사료'),
        ('문법', '${pack}p-coast-6-guide//문서 표현'),
        ('목차', '${pack}p-coast-6-guide'),
        ('빈문서', '${pack}myth-refuted'),
        ('칸', 'cell:${pack}p-coast-6:leaders:은결 나엔@720'),
        ('대문', docFrontKey),
        ('나란히-기본', '${pack}p-coast-0'),
        ('나란히-대문', docFrontKey),
      ]) {
        made.bus.slot(docSideSlot).value = name.startsWith('나란히');
        await open(tester, made.bus, docKey);
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
          final image = await boundary.toImage();
          final png = await image.toByteData(format: ImageByteFormat.png);
          image.dispose();
          File('${folder.path}/문서-$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
        await tester.pumpAndSettle();
      }
    },
    skip: captureTo.isEmpty,
  );

  // 남의 파일의 버그를 붙잡아 둔다(총괄에게 보고한 것) — `DetailChip`은 `Wrap` 안에서 가로로 늘어난다.
  // `detail_shell.dart`의 `_DetailChipState`가 `AnimatedContainer`에 `alignment: Alignment.center`를 두어
  // 느슨한 폭 제약을 통째로 받아 쓰기 때문이다. 그래서 문서 창은 제 칩(`DocChip`)을 쓴다.
  testWidgets('DetailChip도 DocChip도 Wrap 안에서 제 글만큼만 넓다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            child: Wrap(spacing: 6, children: [DetailChip('가', onTap: () {}), DocChip(text: '나', onTap: () {})]),
          ),
        ),
      ),
    );
    // 전에는 DetailChip이 주어진 폭을 다 써서(>300) 상세 창의 칩이 한 줄에 하나씩 섰다 — 고침.
    expect(tester.getSize(find.byType(DetailChip)).width, lessThan(120));
    expect(tester.getSize(find.byType(DetailChip)).height, 32);
    expect(tester.getSize(find.byType(DocChip)).width, lessThan(120));
    expect(tester.getSize(find.byType(DocChip)).height, 32);
  });

  group('하위 문서 칩', () {
    Future<void> pumpChips(WidgetTester tester, AppBus bus, String uid, {Map<String, dynamic>? json}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: Ui.detailWidth, child: DocChips(bus: bus, uid: uid, json: json)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('항목 기록의 x_docs로 칩이 선다', (tester) async {
      final made = makeBus();
      await pumpChips(tester, made.bus, '${pack}p-coast-0');
      expect(find.text('하위 문서 2', findRichText: true), findsOneWidget); // 묶음 제목은 `Text.rich`다
      expect(chipNamed('사료'), findsOneWidget);
      expect(chipNamed('생활'), findsOneWidget);
    });

    testWidgets('이미 읽어 둔 기록을 주면 되묻지 않는다', (tester) async {
      final made = makeBus();
      await pumpChips(tester, made.bus, '${pack}p-coast-0', json: const {
        'x_docs': [
          {'key': 'a//역사', 'sub': '역사'},
        ],
      });
      expect(made.asked, isEmpty);
      expect(chipNamed('역사'), findsOneWidget);
    });

    testWidgets('하위 문서가 없으면 아무것도 그리지 않는다', (tester) async {
      final made = makeBus();
      await pumpChips(tester, made.bus, '${pack}myth-refuted');
      expect(find.byType(DetailBox), findsNothing);
      expect(find.textContaining('하위 문서', findRichText: true), findsNothing);
    });

    testWidgets('칩을 누르면 문서 열쇠가 실린다', (tester) async {
      final made = makeBus();
      await pumpChips(tester, made.bus, '${pack}p-coast-0');
      await tester.tap(chipNamed('사료'));
      await tester.pump();
      expect(made.bus.slot(docSlot).value, '${pack}p-coast-0//사료');
    });

    // ── 되묻기의 소음(검증 보고서 9-2절의 남은 하나) ─────────────────────────────────────────
    //  새 내보내기로 만든 기록에서는 `x_docs`가 없는 것이 곧 '하위 문서 없음'이다.
    //  그런데도 `doc:<uid>`를 되물으면 **없는 기록을 묻는 실패**가 앱의 실패 기록에 쌓인다.

    test('미리 푼 값이 하나라도 있으면 새 내보내기의 기록이다', () {
      expect(docRecordIsNew(const {'name': '아무개'}), isFalse);
      expect(docRecordIsNew(const {'name': '아무개', 'x_cellDocs': []}), isTrue);
      expect(docRecordIsNew(null), isFalse);
    });

    testWidgets('새 기록이면 하위 문서가 없어도 되묻지 않는다', (tester) async {
      final made = makeBus();
      await pumpChips(tester, made.bus, '${pack}p-coast-0', json: const {
        'name': '유리항 패총국',
        'x_cellDocs': ['leader:0'],
      });
      expect(made.asked, isEmpty);
      expect(find.byType(DetailBox), findsNothing);
    });

    testWidgets('새 기록을 되읽었을 때도 doc:을 되묻지 않는다', (tester) async {
      final asked = <Map<String, dynamic>>[];
      final made = makeBus();
      final bus = AppBus(
        ask: (query) async {
          asked.add(query);
          if (query['op'] == 'entity' && query['uid'] == '가상/p-plain') {
            return const {
              'uid': '가상/p-plain',
              'kind': 'period',
              'json': {'name': '민무늬 나라', 'x_eventStat': {'count': 2}},
            };
          }
          throw StateError('없는 기록: ${query['uid']}');
        },
        controller: made.bus.controller,
        scene: made.bus.scene,
      );
      await pumpChips(tester, bus, '가상/p-plain');
      expect(asked.map((q) => q['uid']), ['가상/p-plain'], reason: 'doc:가상/p-plain은 묻지 않는다');
      expect(find.byType(DetailBox), findsNothing);
    });

    testWidgets('옛 기록만 되묻고, 그것도 실패가 남지 않는 하나짜리 목록으로', (tester) async {
      final asked = <Map<String, dynamic>>[];
      final made = makeBus();
      final bus = AppBus(
        ask: (query) async {
          asked.add(query);
          if (query['op'] == 'entity') {
            return const {
              'uid': '가상/p-old',
              'kind': 'period',
              'json': {'name': '옛 저장소의 나라'},
            };
          }
          if (query['op'] == 'entities') {
            // 진짜 엔진의 `entities`는 없는 열쇠를 **빼고** 줄 뿐 거절하지 않는다.
            return const {
              'items': [
                {
                  'uid': 'doc:가상/p-old',
                  'kind': 'doc',
                  'json': {
                    'key': '가상/p-old',
                    'subs': [
                      {'key': '가상/p-old//역사', 'sub': '역사'},
                    ],
                  },
                },
              ],
            };
          }
          throw StateError('없는 명령');
        },
        controller: made.bus.controller,
        scene: made.bus.scene,
      );
      await pumpChips(tester, bus, '가상/p-old');
      expect(asked.map((q) => q['op']), ['entity', 'entities']);
      expect(asked.last['uids'], ['doc:가상/p-old']);
      expect(chipNamed('역사'), findsOneWidget);
    });

    testWidgets('옛 기록인데 문서도 없으면 빈 목록이 올 뿐이다', (tester) async {
      final made = makeBus();
      await pumpChips(tester, made.bus, '${pack}myth-refuted');
      expect(made.asked.map((q) => q['op']), ['entity', 'entities']);
      expect(find.byType(DetailBox), findsNothing);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  표 — 칸 합치기(`<-n>`) · 세로 칸 합치기(`<|n>`)와 글에 맞춘 칸 폭
  // ──────────────────────────────────────────────────────────────────────────────────────────

  group('표의 격자', () {
    DocTable tableOf(String source) => parseDocBody(source).nodes.whereType<DocTable>().single;

    test('세로로 합친 칸은 아래 줄의 자리를 잡아 둔다', () {
      final grid = tableOf('''
||<|2>왼쪽||위 가운데||위 오른쪽||
||아래 가운데||아래 오른쪽||
''').grid;
      expect(grid.columns, 3);
      expect(grid.rows, 2);
      expect([for (final c in grid.cells) (c.cell.spans.single.text, c.row, c.column, c.colspan, c.rowspan)], [
        ('왼쪽', 0, 0, 1, 2),
        ('위 가운데', 0, 1, 1, 1),
        ('위 오른쪽', 0, 2, 1, 1),
        ('아래 가운데', 1, 1, 1, 1),
        ('아래 오른쪽', 1, 2, 1, 1),
      ]);
    });

    test('가로 · 세로 합치기가 겹쳐도 자리가 어긋나지 않는다', () {
      final grid = tableOf('''
||<-2>머리 둘||<|2>오른쪽 둘 높이||
||가||나||
''').grid;
      expect(grid.columns, 3);
      expect([for (final c in grid.cells) (c.row, c.column, c.colspan, c.rowspan)], [
        (0, 0, 2, 1),
        (0, 2, 1, 2),
        (1, 0, 1, 1),
        (1, 1, 1, 1),
      ]);
    });

    test('표 밖으로 뻗은 세로 합치기는 마지막 줄에서 멈춘다', () {
      final grid = tableOf('||<|5>혼자||옆||\n').grid;
      expect(grid.rows, 1);
      expect(grid.cells.first.rowspan, 1);
    });

    testWidgets('칸 폭은 글에 맞고, 합친 칸이 있어도 줄마다 자리가 맞는다', (tester) async {
      await loadFonts();
      final body = parseDocBody('''
||<-2>아주 긴 머리말이 한 줄로 들어가는 칸||
||가||아주 긴 오른쪽 칸의 글||
''');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 700, child: SingleChildScrollView(child: DocArticle(body: body))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final head = tester.getRect(find.ancestor(of: find.text('아주 긴 머리말이 한 줄로 들어가는 칸'), matching: find.byType(Container)).first);
      final left = tester.getRect(find.ancestor(of: find.text('가'), matching: find.byType(Container)).first);
      final right = tester.getRect(find.ancestor(of: find.text('아주 긴 오른쪽 칸의 글'), matching: find.byType(Container)).first);
      // 합친 칸은 아래 두 칸을 꼭 덮는다.
      expect(head.left, closeTo(left.left, 0.5));
      expect(head.right, closeTo(right.right, 0.5));
      expect(left.right, closeTo(right.left, 0.5));
      // 왼쪽 칸은 글 한 글자에 맞춰 좁고(고르게 반씩 나누지 않는다), 오른쪽이 넓다.
      expect(left.width, lessThan(right.width / 2));
    });

    testWidgets('세로로 합친 칸은 두 줄의 높이를 함께 덮는다', (tester) async {
      await loadFonts();
      final body = parseDocBody('''
||<|2>왼쪽||위||
||아래||
''');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 700, child: SingleChildScrollView(child: DocArticle(body: body))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Rect boxOf(String text) => tester.getRect(find.ancestor(of: find.text(text), matching: find.byType(Container)).first);
      final merged = boxOf('왼쪽'), up = boxOf('위'), down = boxOf('아래');
      expect(merged.top, closeTo(up.top, 0.5));
      expect(merged.bottom, closeTo(down.bottom, 0.5));
      expect(merged.height, closeTo(up.height + down.height, 0.5));
      expect(up.left, closeTo(down.left, 0.5), reason: '아래 줄의 칸이 왼쪽으로 밀려나지 않는다');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  각주에서 본문으로 · 바깥 고리
  // ──────────────────────────────────────────────────────────────────────────────────────────

  group('각주와 바깥 고리', () {
    testWidgets('각주 표와 각주 목록을 서로 오간다', (tester) async {
      await loadFonts();
      final body = parseDocBody('여기에 각주가 있다[* 가상의 주석이다.]\n\n${'빈 줄로 길게 미는 글.\n\n' * 40}[각주]\n');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 400, width: 700, child: SingleChildScrollView(child: DocArticle(body: body))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mark = find.text('[1]'); // 본문의 각주 표
      final label = find.text('[1] '); // 각주 목록의 번호
      expect(mark, findsOneWidget);
      expect(label, findsOneWidget);
      expect(tester.getTopLeft(mark).dy, inInclusiveRange(0, 400));
      expect(tester.getTopLeft(label).dy, greaterThan(400), reason: '각주 목록은 한참 아래에 있다');

      // 표를 누르면 각주 목록으로 내려간다.
      await tester.tap(mark);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(label).dy, inInclusiveRange(0, 400));
      expect(tester.getTopLeft(mark).dy, lessThan(0));

      // 목록의 `[1]`을 누르면 본문의 그 자리로 되돌아온다(js/wiki.js의 `wk-rfn-<n>`).
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(mark).dy, inInclusiveRange(0, 400));
    });

    testWidgets('이름을 붙인 각주를 되풀이 써도 본문이 그려진다', (tester) async {
      await loadFonts();
      // `[*ㄱ …]`을 먼저 적고 뒤에서 `[*ㄱ]`을 다시 쓰면 파서는 **같은 번호**를 돌려준다(js/wiki.js:59~61).
      // 그러면 본문에 그 표가 둘이 되는데, 둘 다에 되돌아올 자리를 달면 같은 GlobalKey가 두 위젯에 붙어 창이 깨졌다.
      final body = parseDocBody('첫 자리[*ㄱ 가상의 주석이다.]와 뒤의 같은 자리[*ㄱ]가 있다.\n\n[각주]\n');
      expect(body.footnotes.single.label, 'ㄱ', reason: '되풀이 쓴 각주는 목록에 하나뿐이다');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 400, width: 700, child: SingleChildScrollView(child: DocArticle(body: body))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '같은 표가 둘이어도 창이 깨지지 않는다');
      expect(find.text('[ㄱ]'), findsNWidgets(2), reason: '본문의 표는 둘 다 그려진다');
      expect(find.text('[ㄱ] '), findsOneWidget, reason: '각주 목록의 번호는 하나다');

      // 목록의 `[ㄱ]`을 누르면 **첫 표**로 되돌아간다(브라우저도 같은 id 가운데 첫 자리로 간다).
      await tester.tap(find.text('[ㄱ] '));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('바깥 고리는 앱 틀이 채워 둔 길로 연다', (tester) async {
      final opened = <String>[];
      docOpenUrl = (url) async {
        opened.add(url);
        return true;
      };
      addTearDown(() => docOpenUrl = null);
      final made = makeBus(fixtures: const ['docs-markup.json']);
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '별빛-서고');
      await tester.tapOnText(find.textRange.ofSubstring('바깥 글', descendentOf: find.byType(DocArticle)));
      await tester.pumpAndSettle();
      expect(opened, ['https://example.invalid']);
    });

    testWidgets('길이 없으면 주소를 복사하고 안내 한 줄을 남긴다', (tester) async {
      docOpenUrl = null;
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final made = makeBus(fixtures: const ['docs-markup.json']);
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '별빛-서고');
      await tester.tapOnText(find.textRange.ofSubstring('바깥 글', descendentOf: find.byType(DocArticle)));
      await tester.pumpAndSettle();
      expect(copied, ['https://example.invalid']);
      expect('${made.bus.slot(slotNotice).value}', contains('https://example.invalid'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────────────────────
  //  진짜 자료 처리부(DLL) + 진짜 저장소 — 가짜 답으로는 못 잡는 것을 여기서 굳힌다.
  //  돌리는 법은 `test/contract_real_engine_test.dart`와 같다. DLL · 저장소가 없으면 건너뛴다.
  // ──────────────────────────────────────────────────────────────────────────────────────────

  group('진짜 엔진의 문서 기록', () {
    final dll = File('../engine/target/release/archive_engine.dll');
    final db = File('../data/moonwake3h/archive.db');
    final ready = dll.existsSync() && db.existsSync();
    const noData = '자료 처리부 DLL 또는 data/moonwake3h 저장소가 없습니다';
    const withSubs = '${pack}p-coast-0'; // 하위 문서가 달린 항목(유리항 패총국)

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

    Map<String, dynamic> bodyOfAnswer(Map<String, dynamic> answer) {
      final raw = answer['json'];
      if (raw is Map) return raw.cast<String, dynamic>();
      return (jsonDecode('$raw') as Map).cast<String, dynamic>();
    }

    test('항목 기록의 x_docs가 칩이 읽는 꼴 그대로다', () async {
      final json = bodyOfAnswer(await ask({'op': 'entity', 'uid': withSubs}));
      expect(docRecordIsNew(json), isTrue, reason: '새 내보내기의 기록이다 — 되묻지 않는다');
      final subs = (json['x_docs'] as List).cast<Map<String, dynamic>>();
      expect(subs, isNotEmpty);
      expect(subs.first.keys, containsAll(['key', 'sub']));
      expect('${subs.first['key']}', startsWith('$withSubs//'));
      expect('${subs.first['sub']}', isNotEmpty);
    }, skip: ready ? false : noData);

    test('doc:<열쇠> 기록이 창이 읽는 열쇠를 모두 준다', () async {
      final answer = await ask({'op': 'entity', 'uid': 'doc:$withSubs'});
      final record = DocRecord.fromAnswer(answer)!;
      expect(record.key, withSubs);
      expect(record.title, isNotEmpty);
      expect(record.empty, isFalse);
      expect(record.subs, isNotEmpty);
      expect(record.links, isNotEmpty, reason: '안쪽 고리의 목적지는 내보내기가 미리 푼다');
      // 진짜 본문이 문법 풀기를 그대로 지난다.
      final parsed = parseDocBody(record.body, links: record.links);
      expect(parsed.nodes, isNotEmpty);
    }, skip: ready ? false : noData);

    test('없는 doc: 열쇠는 entity 하나로 물으면 **거절**이고, entities 목록으로 물으면 빈 목록이다', () async {
      // 되묻기의 소음이 이것이었다 — 하나로 물으면 실패가 앱의 실패 기록에 남는다.
      await expectLater(ask({'op': 'entity', 'uid': 'doc:$withSubs//없는-하위-문서'}), throwsA(anything));
      final many = await ask({
        'op': 'entities',
        'uids': ['doc:$withSubs//없는-하위-문서'],
      });
      expect(many['items'], isEmpty);
    }, skip: ready ? false : noData);

    test('하위 문서가 없는 항목도 새 내보내기의 기록이라 되묻지 않는다', () async {
      // 이 저장소에서 x_docs가 없는 항목 기록을 찾아 본다(띠 서른을 훑는다).
      final names = <String>[];
      for (var id = 1; id <= 30; id++) {
        final one = await ask({'op': 'uid_of', 'kind': 'band', 'id': id});
        final uid = one['uid'];
        if (uid is String && uid.isNotEmpty) names.add(uid);
      }
      expect(names, isNotEmpty, reason: '띠 이름을 못 읽으면 이 검사는 뜻이 없다');
      var plain = 0;
      for (final uid in names) {
        final json = bodyOfAnswer(await ask({'op': 'entity', 'uid': uid}));
        if (json.containsKey('x_docs')) continue;
        plain++;
        // 되묻지 않는 길로 갈리는지 — `x_` 값이 있으면 그것으로, 없으면 `entities` 목록으로(실패 아님).
        if (!docRecordIsNew(json)) {
          final many = await ask({
            'op': 'entities',
            'uids': ['doc:$uid'],
          });
          expect(many['items'], isA<List>());
        }
      }
      expect(plain, greaterThan(0), reason: '하위 문서가 없는 항목이 있어야 이 길이 시험된다');
    }, skip: ready ? false : noData);
  });
}

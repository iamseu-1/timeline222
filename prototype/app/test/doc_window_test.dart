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
// 자료 처리부는 가짜 `ask` 하나로 흉내 낸다 — `{"op":"entity","uid":"doc:<열쇠>"}` 말고는 답하지 않는다.

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

({AppBus bus, List<Map<String, dynamic>> asked}) makeBus({List<String> fixtures = const ['docs-moonwake.json'], Map<String, dynamic>? docList}) {
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
      return const {};
    },
    controller: controller,
    scene: scene,
  );
  return (bus: bus, asked: asked);
}

/// 창 하나를 넓은 화면에 띄운다(목차가 본문 옆에 서는 폭).
Future<void> pumpWindow(WidgetTester tester, AppBus bus, {Size size = const Size(1400, 900)}) async {
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

/// 하위 문서 칩 하나 — 이름으로 고른다(📄와 이름이 다른 글이라 이름으로 찾는다).
Finder chipNamed(String name) => find.ancestor(of: find.text(name), matching: find.byType(DocChip));

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
      expect(made.asked.single['uid'], 'doc:${pack}p-coast-0');

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

      await tester.tap(find.text('←'));
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

      await tester.tap(find.text('←'));
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

      await tester.tap(find.text('←'));
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
      await tester.tap(find.text('연표에서'));
      await tester.pumpAndSettle();
      expect(made.bus.selection.value!.uid, '${pack}p-coast-6');
      expect(made.bus.selection.value!.cell, 'leader:0');
      final go = made.bus.go.value!;
      expect(go.lo, lessThan(go.hi));
      expect(made.bus.slot(docSlot).value, isNull); // 창은 닫힌다
    });

    testWidgets('트랙 문서에는 🎯가 없다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, 'track:mw-coast');
      expect(find.text('유리해안'), findsWidgets);
      expect(find.text('연표에서'), findsNothing);
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

    testWidgets('✕로 닫는다', (tester) async {
      final made = makeBus();
      await pumpWindow(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-0');
      await tester.tap(find.text('✕'));
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
      await tester.tap(find.byTooltip('넓게 보기'));
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSideSlot).value, false);
      expect(tester.getTopLeft(find.text('유리항 패총국').first).dx, lessThan(200));
      await tester.tap(find.byTooltip('나란히 보기'));
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSideSlot).value, true);
    });

    testWidgets('나란히면 🎯 연표에서를 눌러도 문서는 그대로', (tester) async {
      final made = makeBus();
      made.bus.slot(docSideSlot).value = true;
      await pumpOverGround(tester, made.bus, const Size(1920, 1080));
      await open(tester, made.bus, '${pack}p-coast-0');
      await tester.tap(find.text('연표에서'));
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
      expect(find.byTooltip('대문'), findsNothing); // 대문에서는 대문 단추가 없다

      await tester.tap(find.widgetWithText(DocFrontCard, '유리항 패총국'));
      await tester.pumpAndSettle();
      expect(made.bus.slot(docSlot).value, '${pack}p-coast-0');
      expect(find.byType(DocArticle), findsOneWidget);
      await tester.tap(find.text('←'));
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
      await tester.tap(find.byTooltip('대문'));
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

  // 지금 연표의 문서 창을 머리 없는 브라우저로 띄워 잰 값(`prototype/results/dom-doc9/wiki-dump.json`)과 맞댄다.
  // 1920×1080 · 100% · 맨 위 띠 60 아래에 창이 선다.
  group('지금 연표와 자리 대조', () {
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
            body: Stack(children: [const SizedBox.expand(), DocWindow(bus: bus, padding: const EdgeInsets.fromLTRB(12, Ui.top + 12, 12, 16))]),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('창 · 머리 · 하위 문서 줄 · 목차 · 본문의 자리', (tester) async {
      final made = makeBus();
      await pumpStage(tester, made.bus);
      await open(tester, made.bus, '${pack}p-coast-0');

      // .wiki-pane [12, 72, 1896, 992]
      final pane = tester.getRect(find.byType(ClipRRect).first);
      expect(pane.left, 12);
      expect(pane.top, 72);
      expect(pane.width, 1896);
      expect(pane.height, 992);

      // .wiki-titles h2 — 22px/700 · 자간 −.025em · 왼쪽 70(창 18 + ← 32 + 틈 8)
      final title = tester.widget<Text>(find.text('유리항 패총국').first);
      expect(title.style!.fontSize, 22);
      expect(title.style!.letterSpacing, closeTo(-.55, 1e-6));
      expect(tester.getTopLeft(find.text('유리항 패총국').first).dx, closeTo(70, .5));

      // .wiki-subs 높이 49(칩이 있는 줄) · 칩 높이 28 · 칩 사이 6
      final chips = find.byType(DocChip);
      expect(tester.getSize(chips.first).height, 32);
      expect(tester.getTopLeft(chips.at(1)).dx - tester.getTopRight(chips.first).dx, closeTo(6, .5));
      expect(tester.getTopLeft(chips.first).dx, closeTo(30, .5)); // 창 12 + 여백 18

      // .wiki-toc [40, …, 200](안쪽 여백 14) → 목차 목록은 `.wiki-toc ol`과 같은 [54, …, 172]
      final toc = tester.getRect(find.byType(DocToc).first);
      expect(toc.left, closeTo(54, .5));
      expect(toc.width, closeTo(172, .5));
      final article = tester.getRect(find.byType(DocArticle));
      expect(article.left, closeTo(268, .5));
      expect(article.width, closeTo(780, .5));
    });

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
  });

  // 1920×1080 그림 뜨기 — 지금 연표의 `results/dom-doc9/문서-*.png`와 같은 좌표다(`side-by-side.mjs`로 나란히 놓는다).
  testWidgets(
    '그림 뜨기(OUT을 줄 때만)',
    (tester) async {
      await loadFonts();
      final made = makeBus();
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
              child: Stack(children: [const SizedBox.expand(), DocWindow(bus: made.bus, padding: const EdgeInsets.fromLTRB(12, Ui.top + 12, 12, 16))]),
            ),
          ),
        ),
      );
      final folder = Directory(captureTo)..createSync(recursive: true);
      for (final (name, docKey) in [
        ('기본', '${pack}p-coast-0'),
        ('표', '${pack}p-coast-0//사료'),
        ('문법', '${pack}p-coast-6-guide//문서 표현'),
        ('목차', '${pack}p-coast-6-guide'),
        ('빈문서', '${pack}myth-refuted'),
        ('칸', 'cell:${pack}p-coast-6:leaders:은결 나엔@720'),
      ]) {
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

import 'load_app_fonts.dart';

import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/fonts.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/shell/look.dart';
import 'package:archive_prototype/ui/app_bus.dart';
import 'package:archive_prototype/ui/doc_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_import.dart';

// 문서 그림(형식 3 images — 10건 D3 결정 9 B) — 지금 연표의 문서 창(js/wiki.js `namu.figureHTML` · css/viewer.css `.wk-fig`)과 같은 규칙인가.
// 고정 자료 `test/fixtures/docs-images.json`: 견본 samples/sample-doc-images.json(가상 나라 해온국 · 확인용 그림 둘)을 내보내기로 낸 배치
// (HT_EXPORT_SAMPLE=sample-doc-images node prototype/scripts/export-layout.mjs — 보조 달력 기록 cal:은 크기 때문에 뺐다). 문서 기록의 `images`와
// 겉 열쇠 `blobs[]`(그림 바이트 base64)가 들어 있다. 자료 처리부는 가짜 `ask`로 흉내 내고(entity · blob), 마지막 검사만 진짜 자료 처리부를 쓴다.
//
// 1배 그림: `--dart-define=OUT=<폴더>`를 주면 1920×1080(웹 연표를 찍는 크로미움과 같은 자리 — 창 가장자리 12 · 위 72)으로 문서 창을 뜬다.
//   지금 연표의 같은 장면은 scripts/doc-images-check.mjs가 뜬다(문서-그림-오른쪽.png · 문서-그림-좁은-화면.png).

const fixture = 'test/fixtures/docs-images.json';
const doc = 'sample-doc-images/p-haeon';
const captureTo = String.fromEnvironment('OUT');
final _shot = GlobalKey();

Map<String, dynamic> readFixture() => (jsonDecode(File(fixture).readAsStringSync()) as Map).cast<String, dynamic>();

/// 본문과 제목은 앱에 실린 같은 글꼴을 반드시 읽고, 시스템 글꼴은 대체 글꼴로만 올린다.
Future<void> loadFonts() async {
  await loadAppFonts();
  final home = Platform.environment['HOME'] ?? '';
  for (final (family, files) in [
    ('Noto Sans KR', ['C:/Windows/Fonts/NotoSansKR-VF.ttf', '$home/.fonts/Pretendard-Regular.otf']),
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

({AppBus bus, List<String> blobs}) makeBus({String? body}) {
  final raw = readFixture();
  final store = <String, Map<String, dynamic>>{};
  for (final e in raw['entities'] as List) {
    final row = (e as Map).cast<String, dynamic>();
    if (body != null && row['uid'] == 'doc:$doc') {
      final record = (jsonDecode(row['json'] as String) as Map).cast<String, dynamic>();
      row['json'] = jsonEncode({...record, 'body': body});
    }
    store[row['uid'] as String] = row;
  }
  final blobs = <String, Map<String, dynamic>>{for (final b in raw['blobs'] as List) (b as Map)['key'] as String: b.cast<String, dynamic>()};
  final asked = <String>[];
  final controller = TimelineController()..resize(1920, 500);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson(const {
      'packs': [
        {'id': 1, 'name': '견본 기록집', 'events': 1},
      ],
      'tracks': [],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async => throw UnimplementedError('문서 창 검사는 타일을 읽지 않는다'),
  );
  final bus = AppBus(
    ask: (query) async {
      if (query['op'] == 'entity') {
        final row = store[query['uid']];
        if (row == null) throw StateError('없는 기록: ${query['uid']}');
        return row;
      }
      if (query['op'] == 'blob') {
        final key = query['key'] as String;
        asked.add(key);
        final b = blobs[key];
        if (b == null) throw StateError('그림이 저장소에 없습니다: $key');
        return {'key': key, 'mime': b['mime'], 'bytes': base64Decode(b['data'] as String).length, 'data': b['data']};
      }
      return const {};
    },
    controller: controller,
    scene: scene,
  );
  return (bus: bus, blobs: asked);
}

/// 웹 연표와 같은 자리에 창을 띄운다(창 가장자리 12 · 위 72 · 아래 16).
Future<void> pumpWindow(WidgetTester tester, AppBus bus, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
      home: Scaffold(
        backgroundColor: Ui.bg,
        body: RepaintBoundary(
          key: _shot,
          child: Stack(children: [const SizedBox.expand(), DocWindow(bus: bus, padding: const EdgeInsets.fromLTRB(12, 72, 12, 16))]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 문서를 열고, 그림 바이트를 받아 풀고, 띄운 자리를 잰 뒤까지 기다린다.
Future<void> openDoc(WidgetTester tester, AppBus bus, String key) async {
  bus.slot(docSlot).value = key;
  await tester.pumpAndSettle();
  await decodeImages(tester);
}

/// 화면의 그림을 실제로 풀어 둔다(검사 환경의 시계는 멈춰 있어 그림 풀기는 runAsync 안에서만 끝난다).
Future<void> decodeImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
}

/// 본문의 글 줄(문단 · 목록 항목) — 그림 설명 · 그림 없음 자리는 뺀다. [Rect]는 화면 좌표의 줄 상자(그 줄 조각들을 합친 것).
List<Rect> textLines(WidgetTester tester, List<Rect> skip) {
  final out = <Rect>[];
  final article = find.byType(DocArticle);
  for (final rp in tester.renderObjectList<RenderParagraph>(find.descendant(of: article, matching: find.byType(RichText)))) {
    final origin = rp.localToGlobal(Offset.zero);
    final whole = origin & rp.size;
    if (skip.any((r) => r.inflate(1).contains(whole.center))) continue;
    final text = rp.text.toPlainText(includeSemanticsLabels: false);
    final lines = <Rect>[];
    // 선택 상자는 줄 끝 공백을 줄 폭 밖까지 포함할 수 있다. 그림과의 틈은 눈에 그려지는 글로 잰다.
    for (final word in RegExp(r'\S+').allMatches(text)) {
      for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: word.start, extentOffset: word.end))) {
        final r = Rect.fromLTRB(b.left, b.top, b.right, b.bottom).shift(origin);
        final i = lines.indexWhere((l) => (l.top - r.top).abs() < 6);
        if (i < 0) {
          lines.add(r);
        } else {
          lines[i] = lines[i].expandToInclude(r);
        }
      }
    }
    out.addAll(lines);
  }
  out.sort((a, b) => a.top.compareTo(b.top));
  return out;
}

/// 그림 상자들(누르는 자리 — 선 1px 포함)과 그 아래 설명까지.
List<Rect> figureBoxes(WidgetTester tester) =>
    [for (final e in find.byType(DocImage).evaluate()) tester.getRect(find.ancestor(of: find.byWidget(e.widget), matching: find.byType(Container)).first)];

Future<void> capture(WidgetTester tester, String name) async {
  if (captureTo.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ImageByteFormat.png);
    Directory(captureTo).createSync(recursive: true);
    File('$captureTo/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  test('문법: [[파일:…]] 줄은 그 앞에서 문단을 끊고 그림을 놓는다 — 자리 · 크기 · 그림 없음 · 목록 안은 지움', () {
    final images = DocImageRef.parse({
      '바다.webp': {'key': 'img:p/sea', 'mime': 'image/webp', 'w': 800, 'h': 450, 'caption': '바다', 'credit': '검사'},
      'g1': {'key': 'img:p/g1', 'w': 10, 'h': 10},
    });
    expect(images['바다.webp']!.captionLine, '바다 · 검사');
    expect(images['바다.webp']!.ratio, 450 / 800);
    final body = parseDocBody(
      '== 바다 ==\n[[파일:바다.webp]]\n첫 줄 글\n둘째 줄 글\n앞 글 [[이미지:g1|align=center|width=60%]] 뒤 글\n[[file:없는 그림|align=left|width=240]]\n * 목록 [[파일:바다.webp]] 안',
      images: images,
    );
    final kinds = body.nodes.map((n) => n.runtimeType.toString()).toList();
    expect(kinds, ['DocHeading', 'DocFigure', 'DocParagraph', 'DocFigure', 'DocParagraph', 'DocFigure', 'DocList']);
    final right = body.nodes[1] as DocFigure, center = body.nodes[3] as DocFigure, missing = body.nodes[5] as DocFigure;
    expect((right.name, right.floats, right.image!.key), ('바다.webp', true, 'img:p/sea'));
    expect((center.align, center.widthPct, center.floats, center.image!.key), ('center', 60.0, false, 'img:p/g1'));
    expect((missing.align, missing.widthPx, missing.image, missing.floats), ('left', 240.0, null, false));
    expect((body.nodes[2] as DocParagraph).spans.where((s) => !s.lineBreak).map((s) => s.text).join(), '첫 줄 글둘째 줄 글');
    expect((body.nodes[4] as DocParagraph).spans.map((s) => s.text).join(), '앞 글  뒤 글');
    expect((body.nodes[6] as DocList).items.single.spans.map((s) => s.text).join(), '목록  안');
    // 그림이 없는 옛 문서는 예전 그대로(그림 마디가 생기지 않는다).
    expect(parseDocBody('== 개요 ==\n글 한 줄\n[[다른 문서]]').nodes.whereType<DocFigure>(), isEmpty);
  });

  testWidgets('넓은 창(1920×1080): 그림은 본문 오른쪽 끝에 떠 있고, 옆 줄은 그림 왼쪽 24 앞에서 끝나며 그림 아래 줄은 본문 폭 — 줄마다', (tester) async {
    final entity = (readFixture()['entities'] as List).cast<Map>().singleWhere((e) => e['uid'] == 'doc:$doc');
    final body = (jsonDecode(entity['json'] as String) as Map)['body'] as String;
    const nextSection = '\n== 도읍 ==';
    expect(body, contains(nextSection));
    // 내장 글꼴에서는 견본의 일반 문단이 그림 옆에서 끝나고 들여쓴 목록만 아래에 남는다.
    // 다음 절 앞에 일반 문단을 명시하여 그림 아래의 본문 전체 폭을 실제로 검사한다.
    final afterFigure = List.filled(6, '그림 아래에서는 포구와 섬 사이의 뱃길 기록을 본문 전체 폭으로 이어서 읽습니다.').join(' ');
    final made = makeBus(body: body.replaceFirst(nextSection, '\n\n$afterFigure$nextSection'));
    await pumpWindow(tester, made.bus, const Size(1920, 1080));
    await openDoc(tester, made.bus, doc);
    expect(made.blobs.toSet(), {'img:sample-doc-images/img-sea', 'img:sample-doc-images/img-castle'}, reason: '문서가 쓰는 그림만 자료 처리부에 묻는다');
    final article = tester.getRect(find.byType(DocArticle));
    final boxes = figureBoxes(tester);
    expect(boxes, hasLength(2));
    final right = boxes.first, center = boxes.last;
    expect(right.right, moreOrLessEquals(article.right, epsilon: .5), reason: '본문 오른쪽 끝');
    expect(right.width, moreOrLessEquals(DocUi.figureWidth, epsilon: .5));
    expect(right.height, moreOrLessEquals((340 - 2) * 450 / 800 + 2, epsilon: .5), reason: '원본 비율(800×450)');
    final caption = tester.getRect(find.text('남쪽 바닷길 — 포구 셋을 잇는 뱃길 (확인용 그림) · 확인용 견본'));
    expect(caption.left, moreOrLessEquals(right.left, epsilon: .5));
    final floatBottom = caption.bottom + DocUi.figureBottom; // 그림의 바깥 아랫변
    final lines = textLines(tester, [caption]);
    final beside = lines.where((l) => l.top >= right.top - DocUi.figureTop - 1 && l.top < floatBottom - .5).toList();
    final head = tester.getRect(find.descendant(of: find.byType(DocArticle), matching: find.text('3. 도읍', findRichText: true)));
    final below = lines.where((l) => l.top >= floatBottom - .5 && l.bottom <= head.top).toList();
    expect(beside.length, greaterThanOrEqualTo(4));
    for (final l in beside) {
      expect(l.right, lessThanOrEqualTo(right.left - DocUi.figureGap + .5), reason: '그림 옆 줄 $l');
    }
    expect(beside.map((l) => l.right).reduce((a, b) => a > b ? a : b), greaterThan(right.left - DocUi.figureGap - 60), reason: '좁아진 폭을 거의 다 씀');
    expect(below, isNotEmpty, reason: '그림 아래로 내려간 줄이 있어야 함');
    // 목록은 들여쓰기가 있으므로, 덧붙인 일반 문단에 본문 전체 폭이 배정되는지 본다.
    // 한 문단과 목록 자체가 그림 경계를 넘어가는 흐름은 아래 두 검사에서 따로 본다.
    final belowParagraphs = tester.renderObjectList<RenderParagraph>(find.descendant(of: find.byType(DocArticle), matching: find.byType(RichText))).where((rp) {
      final origin = rp.localToGlobal(Offset.zero);
      return origin.dy >= floatBottom - .5 && origin.dy + rp.size.height <= head.top;
    });
    expect(belowParagraphs.any((rp) => rp.constraints.maxWidth >= article.width - .5), isTrue, reason: '그림 아래 본문 줄에는 본문 폭을 배정함');
    expect(head.top, greaterThanOrEqualTo(floatBottom - .5), reason: '다음 제목은 그림 아래에서 시작(겹치지 않음)');
    // 가운데 그림(align=center · width=60%) · 그림 없음 자리
    expect(center.width, moreOrLessEquals(article.width * .6, epsilon: .5));
    expect(center.center.dx, moreOrLessEquals(article.center.dx, epsilon: .5));
    expect(find.text('그림 없음 — 지운 그림.webp'), findsOneWidget);
    // 옆 글이 그림과 겹치지 않음(그림 상자 · 설명 둘 다)
    for (final l in lines) {
      expect(l.overlaps(right) || l.overlaps(caption), isFalse, reason: '겹침 $l');
    }
    await capture(tester, '앱-문서-그림-오른쪽');
  });

  for (final list in [false, true]) {
    testWidgets('긴 ${list ? '목록' : '문단'}: 그림 옆의 좁은 줄이 그림 아래에서 실제로 본문 폭을 쓴다', (tester) async {
      final text = List.filled(24, '가상 포구의 기록을 따라 물섬과 솔뫼 사이를 오간 뱃길을 적었습니다.').join(' ');
      final made = makeBus(body: '== 줄 흐름 ==\n[[파일:남쪽 바닷길.webp]]\n${list ? ' * ' : ''}$text\n== 다음 절 ==\n그림 다음 본문입니다.');
      await pumpWindow(tester, made.bus, const Size(1920, 1080));
      await openDoc(tester, made.bus, doc);
      final figure = figureBoxes(tester).single;
      final caption = tester.getRect(find.text('남쪽 바닷길 — 포구 셋을 잇는 뱃길 (확인용 그림) · 확인용 견본'));
      final bottom = caption.bottom + DocUi.figureBottom;
      final head = tester.getRect(find.descendant(of: find.byType(DocArticle), matching: find.text('2. 다음 절', findRichText: true)));
      final lines = textLines(tester, [caption]).where((r) => r.top >= figure.top - DocUi.figureTop - 1 && r.bottom <= head.top).toList();
      final beside = lines.where((r) => r.top < bottom - .5).toList();
      final below = lines.where((r) => r.top >= bottom - .5).toList();
      expect(beside.length, greaterThanOrEqualTo(4));
      expect(below.length, greaterThanOrEqualTo(2));
      for (final line in beside) {
        expect(line.right, lessThanOrEqualTo(figure.left - DocUi.figureGap + .5), reason: '그림 옆 줄 $line');
      }
      expect(below.any((r) => r.right > figure.left + 40), isTrue, reason: '긴 글은 그림 아래에서 넓어진 폭을 실제로 씀');
      for (final line in lines) {
        expect(line.overlaps(figure) || line.overlaps(caption), isFalse, reason: '그림이나 설명과 겹침 $line');
      }
      expect(head.top, greaterThanOrEqualTo(bottom - .5));
      await capture(tester, '앱-문서-그림-긴-${list ? '목록' : '문단'}');
    });
  }

  testWidgets('좁은 창(본문 600 아래): 그림을 띄우지 않고 본문 폭 가운데 — 옆에 글이 없음(결정 9 A)', (tester) async {
    final made = makeBus();
    await pumpWindow(tester, made.bus, const Size(640, 900));
    await openDoc(tester, made.bus, doc);
    final article = tester.getRect(find.byType(DocArticle));
    expect(article.width, lessThan(DocUi.figureNarrow));
    final fig = figureBoxes(tester).first;
    expect(fig.width, moreOrLessEquals(article.width, epsilon: .5), reason: '원본(800)이 본문보다 넓으면 본문 폭');
    expect(fig.center.dx, moreOrLessEquals(article.center.dx, epsilon: .5));
    for (final l in textLines(tester, const [])) {
      expect(l.top >= fig.bottom || l.bottom <= fig.top, isTrue, reason: '그림 옆에 글이 없어야 함 $l · $fig');
    }
    await capture(tester, '앱-문서-그림-좁은-화면');
  });

  testWidgets('그림을 누르면 화면 전체로 크게 — Esc는 크게 보기만 닫고 문서 창은 그대로', (tester) async {
    final made = makeBus();
    await pumpWindow(tester, made.bus, const Size(1920, 1080));
    await openDoc(tester, made.bus, doc);
    await tester.tap(find.byType(DocImage).first);
    await tester.pumpAndSettle();
    await decodeImages(tester);
    final zoomCaption = find.text('남쪽 바닷길 — 포구 셋을 잇는 뱃길 (확인용 그림) · 확인용 견본');
    expect(zoomCaption, findsNWidgets(2), reason: '본문의 설명 + 크게 보기의 설명');
    final big = tester.getRect(find.byType(DocImage).last);
    expect(big.width, moreOrLessEquals(800, epsilon: .5), reason: '원본 크기까지(화면 안에 들면 늘리지도 줄이지도 않음)');
    expect(big.center.dx, moreOrLessEquals(960, epsilon: .5));
    await capture(tester, '앱-문서-그림-크게');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(zoomCaption, findsOneWidget, reason: '크게 보기만 닫힘');
    expect(tester.state<DocWindowState>(find.byType(DocWindow)).openKey, doc);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.state<DocWindowState>(find.byType(DocWindow)).openKey, '', reason: '다음 Esc는 문서 창을 닫음');
  });

  testWidgets('id로 적은 그림([[파일:img-sea]] — 사건 문서)도 같은 그림 · 읽어 둔 바이트는 다시 묻지 않음', (tester) async {
    final made = makeBus();
    await pumpWindow(tester, made.bus, const Size(1920, 1080));
    await openDoc(tester, made.bus, 'sample-doc-images/e-route');
    expect(figureBoxes(tester), hasLength(1), reason: 'id(img-sea)로 적은 그림도 같은 그림');
    expect(find.byType(Image), findsOneWidget, reason: '바이트를 받아 그림이 그려짐');
    expect(made.blobs, isEmpty, reason: '앞 검사에서 읽어 둔 그림(img-sea)은 자료 처리부에 다시 묻지 않음');
  });

  test('진짜 자료 처리부: 배치의 blobs → 저장소 → archive_blob · {"op":"blob"} 바이트가 같다', () async {
    final dll = File('../engine/target/release/archive_engine.dll');
    if (!dll.existsSync() || !DynamicLibrary.open(dll.absolute.path).providesSymbol('archive_blob')) {
      markTestSkipped('archive_blob이 있는 자료 처리부가 없습니다');
      return;
    }
    final dir = Directory.systemTemp.createTempSync('doc-figure-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final layout = File('${dir.path}/layout.json')..writeAsStringSync(File(fixture).readAsStringSync());
    final out = '${dir.path}/archive.db';
    final answer = await callArchiveImport({'layout': layout.path, 'out': out}, libraryPath: dll.absolute.path);
    expect(answer['ok'], isTrue, reason: '$answer');
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(() async {
      try {
        await engine.call({'op': 'close'});
      } catch (_) {
        // 저장소를 열기 전에 끝난 검사 — 놓을 것이 없다.
      }
      engine.close();
    });
    await engine.start(out);
    for (final b in readFixture()['blobs'] as List) {
      final key = (b as Map)['key'] as String;
      final want = base64Decode(b['data'] as String);
      expect(await engine.blob(key), want, reason: key);
      final asked = await engine.call({'op': 'blob', 'key': key});
      expect(base64Decode(asked['data']['data'] as String), want);
      expect(asked['data']['mime'], 'image/webp');
    }
    expect(await engine.blob('img:sample-doc-images/없는-그림'), isNull);
    final record = await engine.call({'op': 'entity', 'uid': 'doc:$doc'});
    final images = DocRecord.fromAnswer((record['data'] as Map).cast<String, dynamic>())!.images;
    expect(images.keys.toSet(), {'남쪽 바닷길.webp', '달내 성.webp'});
  });
}

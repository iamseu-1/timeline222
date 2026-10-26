import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/scene/paint/batch.dart';
import 'package:archive_prototype/scene/paint/patterns.dart';
import 'package:archive_prototype/scene/sprites.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 그리기의 공용 묶음(네모 · 무늬 · 조각 · 글자 줄)과 타일 해독의 검사.
// 여기서 보는 것은 "같은 그림을 더 적은 자리 · 더 적은 그리기 호출로 내보내는가"다 — 그림 자체가 같은지는 장면 그림(render_scene_test)으로 본다.

void main() {
  group('네모 묶음', () {
    test('색인은 네모마다 (0,1,2)(0,2,3)이고 한 벌을 다시 쓴다', () {
      final six = QuadIndices.of(1);
      expect(six, [0, 1, 2, 0, 2, 3]);
      expect(QuadIndices.of(2).sublist(6), [4, 5, 6, 4, 6, 7]);
      // 마지막 네모의 마지막 꼭짓점이 Uint16의 한도에 딱 맞는다 — 한 번에 이보다 많이 내보낼 수 없는 까닭.
      final all = QuadIndices.of(QuadIndices.perDraw);
      expect(all.length, QuadIndices.perDraw * 6);
      expect(all.last, 65535, reason: '마지막 꼭짓점이 Uint16의 한도에 딱 맞는다');
      expect(QuadIndices.perDraw * 4, 65536);
    });

    test('색인의 한도를 넘으면 나눠 내보낸다', () {
      final quads = Quads();
      for (int i = 0; i < QuadIndices.perDraw; i++) {
        quads.add(0, 0, 1, 1, 0xff102030);
      }
      final spy = _SpyCanvas();
      quads.flush(spy);
      expect(spy.vertices, 1, reason: '한도까지는 한 번에');
      expect(quads.count, 0, reason: '내보낸 뒤에는 비어 있다');

      for (int i = 0; i < QuadIndices.perDraw + 1; i++) {
        quads.add(0, 0, 1, 1, 0xff102030);
      }
      final split = _SpyCanvas();
      quads.flush(split);
      expect(split.vertices, 2, reason: '한도를 넘은 하나 때문에 두 번');
    });

    test('빈 묶음은 아무것도 내보내지 않는다', () {
      final spy = _SpyCanvas();
      Quads().flush(spy);
      expect(spy.vertices, 0);
    });

    test('꼭짓점 넷의 색이 네 모서리에 그대로 간다', () async {
      final pixels = await _draw((canvas) {
        final quads = Quads()
          // 왼쪽 위 빨강 · 오른쪽 위 초록 · 오른쪽 아래 파랑 · 왼쪽 아래 흰색.
          ..addCorners(0, 0, 40, 40, 0xffff0000, 0xff00ff00, 0xff0000ff, 0xffffffff)
          // 옆으로 번지는 네모와 단색 네모.
          ..addFade(40, 0, 80, 40, 0xff000000, 0xffffffff)
          ..add(0, 40, 80, 80, 0xff204060);
        quads.flush(canvas);
      });
      int at(int x, int y) => pixels.getUint32((y * 80 + x) * 4);
      // 꼭짓점 색은 세모 안에서 이어지므로 꼭짓점 픽셀도 그 한 칸만큼은 이웃 색이 섞인다 — 어느 빛깔이 이겼는지로 본다.
      int red(int v) => (v >> 24) & 0xff;
      int green(int v) => (v >> 16) & 0xff;
      int blue(int v) => (v >> 8) & 0xff;
      expect(red(at(0, 0)), greaterThan(240), reason: '왼쪽 위는 빨강');
      expect(green(at(0, 0)) + blue(at(0, 0)), lessThan(16));
      expect(green(at(39, 0)), greaterThan(240), reason: '오른쪽 위는 초록');
      expect(blue(at(39, 39)), greaterThan(240), reason: '오른쪽 아래는 파랑');
      expect(red(at(0, 39)) + green(at(0, 39)) + blue(at(0, 39)), greaterThan(740), reason: '왼쪽 아래는 흰색');
      // 옆으로 번지는 네모: 위와 아래가 같은 색이고 왼쪽에서 오른쪽으로 밝아진다.
      expect(at(42, 2), at(42, 37));
      expect(red(at(42, 20)), lessThan(red(at(77, 20))));
      expect(at(10, 60), 0x204060ff, reason: '단색 네모는 네 꼭짓점이 모두 같은 색');
      expect(at(70, 70), 0x204060ff);
    });

    test('점선은 무늬가 시작하는 자리(phase)에 붙어 끊긴다', () {
      final quads = Quads()..hLine(10, 30, 5, 0xff000000, dash: 4, gap: 4, phase: 0);
      // 8px 주기의 무늬가 0에서 시작하므로 10~30에는 10~12(앞에서 걸쳐 든 것) · 16~20 · 24~28이 든다.
      expect(quads.count, 3);
      // 끊지 않으면 아무리 길어도 네모 하나다.
      final solid = Quads()..hLine(10, 3000, 5, 0xff000000);
      expect(solid.count, 1);
    });
  });

  group('무늬 묶음', () {
    test('무늬마다 따로 모으고 한도를 넘으면 나눠 내보낸다', () {
      final patterns = Patterns();
      const stripes = PatternSpec.stripes(90, 1, 4), dots = PatternSpec.dots(6, 1.5);
      for (int i = 0; i < QuadIndices.perDraw + 1; i++) {
        patterns.add(stripes, 0, 0, 10, 10, 0xff000000);
      }
      patterns.add(dots, 0, 0, 10, 10, 0xff000000);
      final spy = _SpyCanvas();
      patterns.flush(spy);
      expect(spy.vertices, 3, reason: '줄무늬 둘(나눠서) + 점무늬 하나');
      final again = _SpyCanvas();
      patterns.flush(again);
      expect(again.vertices, 0, reason: '내보낸 뒤에는 비어 있다');
      patterns.dispose();
    });

    test('넓이가 없는 네모는 담지 않는다', () {
      final patterns = Patterns();
      const stripes = PatternSpec.stripes(0, 1, 4);
      patterns.add(stripes, 10, 10, 10, 20, 0xff000000);
      patterns.add(stripes, 10, 10, 20, 10, 0xff000000);
      final spy = _SpyCanvas();
      patterns.flush(spy);
      expect(spy.vertices, 0);
      patterns.dispose();
    });
  });

  group('글자 줄', () {
    test('처음 잡은 자리를 넘어도 늘려 담고, 그린 뒤에는 비운다', () {
      final queue = TextQueue();
      const look = TextLook(12, ui.FontWeight.w400, 0xff000000);
      for (int i = 0; i < 700; i++) {
        queue.add('이름', '글줄 $i', look, i.toDouble(), i * 2.0, i.isEven ? 1 : .5);
      }
      expect(queue.count, 700);
      final text = _FakeText();
      final seen = <String>[];
      final painted = queue.paint(_SpyCanvas(), text, onPainted: (kind, what, x, y, alpha) => seen.add('$kind|$what|$x|$y|$alpha'));
      expect(painted, 700);
      expect(queue.count, 0);
      expect(text.flushes, 1);
      // 자리와 투명도가 담은 그대로 나온다(typed 배열로 바꾸며 어긋나지 않았는가).
      expect(seen.first, '이름|글줄 0|0.0|0.0|1.0');
      expect(seen[3], '이름|글줄 3|3.0|6.0|0.5');
      expect(seen.last, '이름|글줄 699|699.0|1398.0|0.5');
    });

    test('그리지 못한 글줄은 세지 않는다', () {
      final queue = TextQueue();
      const look = TextLook(12, ui.FontWeight.w400, 0xff000000);
      queue.add('이름', '가', look, 0, 0);
      queue.add('이름', '나', look, 1, 1);
      final text = _FakeText()..refuse = '나';
      expect(queue.paint(_SpyCanvas(), text), 1);
    });
  });

  group('글줄 보관', () {
    test('폭은 색이 달라도 한 번만 잰다', () {
      // 검사 환경의 첫 글줄은 글꼴을 찾느라 예산을 넘길 수 있다 — 여기서 보는 것은 예산이 아니라 몇 벌을 만드는가다.
      final text = ParagraphText()
        ..budgetMicros = 10000000
        ..beginFrame();
      const look = TextLook(12, ui.FontWeight.w400, 0xff112233);
      final a = text.widthOf('별여울 나루', look);
      expect(a, isNotNull);
      expect(text.newThisFrame, 1);
      final b = text.widthOf('별여울 나루', look.withColor(0x80112233));
      expect(b, a, reason: '색만 다르면 같은 폭이다');
      expect(text.newThisFrame, 1, reason: '색이 다르다고 글줄을 한 벌 더 만들지 않는다');
      // 그릴 때는 그 색의 글줄이 필요하다 — 그때 비로소 하나 더 만든다.
      expect(text.paint(_SpyCanvas(), '별여울 나루', look.withColor(0x80112233), 0, 0), isTrue);
      expect(text.newThisFrame, 2);
      text.dispose();
    });

    test('예산이 없으면 폭을 모른다고 답한다', () {
      final text = ParagraphText()
        ..maxNewPerFrame = 0
        ..beginFrame();
      expect(text.widthOf('처음 보는 이름', const TextLook(12, ui.FontWeight.w400, 0xff000000)), isNull);
      expect(text.starved, isTrue);
      text.dispose();
    });
  });

  group('작은 그림판', () {
    test('숫자 글줄의 폭은 글자마다의 폭을 더한 것이고, 숫자가 아닌 것은 건너뛴다', () {
      final sprites = Sprites.shared;
      final plus = sprites.digitsWidth('+'), three = sprites.digitsWidth('3');
      expect(sprites.digitsWidth('+3'), closeTo(plus + three, 1e-9));
      expect(sprites.digitsWidth('+3가'), closeTo(plus + three, 1e-9), reason: '그림판에 없는 글자는 건너뛴다');
      expect(sprites.digitsWidth(''), 0);
    });

    test('숫자 글줄은 글자 수만큼 조각을 찍는다', () {
      final sprites = Sprites.shared;
      final before = sprites.count;
      sprites.addDigits('+38', 10, 20, 0xffffffff);
      expect(sprites.count - before, 3);
      sprites.addDigits('가나', 10, 20, 0xffffffff);
      expect(sprites.count - before, 3, reason: '숫자가 아니면 아무것도 찍지 않는다');
      sprites.flush(_SpyCanvas());
      expect(sprites.count, 0);
    });
  });

  group('타일 해독', () {
    test('큰 타일을 받아도 해독은 열을 풀지 않는다(처음 읽을 때 푼다)', () {
      final bytes = _bigTile();
      expect(bytes.length, greaterThan(500 * 1024), reason: '100만 건의 성긴 단계 타일만 한 크기(55만 바이트)로 잰다');
      // 데우기 한 번(첫 해독 · 첫 열 열기에는 이 길을 처음 도는 값이 섞인다).
      _touch(Tile.decode(bytes));
      final watch = Stopwatch()..start();
      final tile = Tile.decode(bytes);
      final decodeUs = watch.elapsedMicroseconds;
      expect(tile.cellCount, 5620);
      watch
        ..reset()
        ..start();
      final sum = _touch(tile);
      final viewUs = watch.elapsedMicroseconds;
      expect(sum, isNotNaN);
      // ignore: avoid_print
      print('타일 ${(bytes.length / 1024).round()}KiB(칸 ${tile.cellCount} · 띠 ${tile.bandCount} · 사건 ${tile.eventCount}) · 해독 $decodeUs µs · 열 열기 $viewUs µs');
      expect(decodeUs, lessThan(5000), reason: '해독은 머리와 구역 표만 읽는다 — 자료를 베끼면 한 장면이 통째로 밀린다');
    });

    test('글자는 처음 물을 때만 풀고 그 뒤에는 같은 것을 준다', () {
      final tile = Tile.decode(_bigTile());
      final first = tile.text(tile.cellName[0]);
      expect(first, isNotEmpty);
      expect(identical(tile.text(tile.cellName[0]), first), isTrue);
      expect(tile.text(Tile.noName), '');
    });
  });
}

/// 층이 첫 장면에 읽는 만큼 열을 연다(칸 · 띠의 모든 열).
double _touch(Tile tile) {
  var sum = 0.0;
  for (final col in [0, 1]) {
    sum += tile.section(Tile.secCell).f(col)[0] + tile.section(Tile.secBand).f(col)[0];
  }
  for (final col in [2, 3, 4, 5, 6, 7, 8]) {
    sum += tile.section(Tile.secCell).u(col)[0] + tile.section(Tile.secBand).u(col)[0];
  }
  return sum;
}

/// 100만 건의 성긴 단계 타일과 비슷한 크기(55만 바이트 · 칸 5,620)의 타일.
Uint8List _bigTile() {
  final b = TileBuilder(level: 11, x: 0, chunk: 0);
  // 이름은 64가지만 돌려 쓴다 — 검사용 짜개가 이름을 찾을 때 훑기라 가짓수가 많으면 짜는 데만 오래 걸린다.
  String name(int i) => '칸 ${i % 64}';
  for (int i = 0; i < 400; i++) {
    b.band(i + 1, i % 200, i * 100.0, i * 100.0 + 5000, name(i));
  }
  for (int i = 0; i < 5620; i++) {
    b.cell(i + 1, i % 200, i * 50.0, i * 50.0 + 400, name(i), kind: i % 8, lane: i % 3);
  }
  for (int i = 0; i < 2000; i++) {
    b.event(i + 1, i % 200, i * 120.0, name(i));
  }
  // 일반 구역(이름표 · 막대 · 관계선 …)도 그만큼 실린다 — 열이 열넷이라 바이트가 가장 크게 붙는 자리다.
  for (int i = 0; i < 4600; i++) {
    b.item(16 + i % 8, i + 1, i % 200, i * 60.0, i * 60.0 + 300, name: name(i), text2: name(i + 1));
  }
  return b.build();
}

/// 그림을 진짜로 그려 픽셀을 본다(80×80).
Future<ByteData> _draw(void Function(ui.Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(80, 80);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return data!;
}

/// 그리기 호출을 세는 가짜 화폭.
class _SpyCanvas implements ui.Canvas {
  int vertices = 0;

  @override
  void drawVertices(ui.Vertices v, ui.BlendMode mode, ui.Paint paint) => vertices++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 글자 그리기를 흉내 내는 가짜 — 글자 줄이 담은 것을 그대로 넘기는지만 본다.
class _FakeText extends SceneText {
  int flushes = 0;
  String? refuse;

  @override
  int newThisFrame = 0;
  @override
  bool starved = false;
  @override
  double get spentMs => 0;
  @override
  bool get canFade => true;
  @override
  void beginFrame() {}
  @override
  double? widthOf(String text, TextLook look) => text.length * look.size;
  @override
  bool paint(ui.Canvas canvas, String text, TextLook look, double x, double y, {double alpha = 1}) => text != refuse;
  @override
  void flush(ui.Canvas canvas) => flushes++;
  @override
  void setScale(double scale) {}
  @override
  void dispose() {}
}

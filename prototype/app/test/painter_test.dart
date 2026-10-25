import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show TagEnd, TagLook;
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/tile_cache.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

SceneLayout layout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1)]}],
  'epochs': [{'id': 1, 'pack': 1, 'start': 0, 'end': 900000000, 'color': 0xc8b193, 'name': '첫째 시대'}],
});

const m = 1000000.0; // 백만 분

/// 단계 9의 타일 0과 1. 1번 띠는 두 타일에 걸치고 화면 왼쪽 밖에서 시작한다.
Map<(int, int), Uint8List> tiles() {
  final left = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, 50 * m, 67108864, '별여울국', flags: Tile.clipRight)
    ..cell(10, 0, 55 * m, 67108864, '첫째 지도자', flags: Tile.clipRight)
    // 끝 미정인 띠의 바탕은 제 색의 6%뿐이라, 꼬리의 짙기를 재려면 종이와 또렷이 다른 색이어야 한다.
    ..band(3, 1, 60 * m, 65 * m, '은빛 나루', color: 0x202020, flags: Tile.fuzzyEnd);
  final right = TileBuilder(level: 9, x: 1, chunk: 0)
    ..band(1, 0, 0, 2 * m, '별여울국', flags: Tile.clipLeft)
    ..cell(10, 0, 0, 2 * m, '첫째 지도자', flags: Tile.clipLeft)
    ..band(2, 0, 2.5 * m, 4.5 * m, '해솔국')
    ..cell(11, 0, 2.5 * m, 2.7 * m, '해솔 내각', kind: 2);
  final top = TileBuilder(level: 11, x: 0, chunk: 0)..band(1, 0, 50 * m, 69.108864 * m, '별여울국');
  return {(9, 0): left.build(), (9, 1): right.build(), (11, 0): top.build()};
}

/// 1920×1080 · 통 32px(단계 9) · 타일 경계(67.1백만 분)가 화면 안에 오는 보기.
(TimelineScene, TimelinePainter, List<(int, int)>) make({Set<(int, int)>? only}) {
  final controller = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(284);
  final span = (1920 - SceneView.gutter) / (32 / bucketMinutes(9));
  controller.showRange(57.1 * m, 57.1 * m + span);
  final asked = <(int, int)>[];
  final data = tiles();
  final scene = TimelineScene(
    controller: controller,
    layout: layout(),
    fetchTile: (level, x, chunk, packs) async {
      asked.add((level, x));
      final bytes = data[(level, x)];
      if (bytes == null || chunk != 0 || (only != null && !only.contains((level, x)))) {
        return (TileBuilder(level: level, x: x, chunk: chunk)).build();
      }
      return bytes;
    },
  );
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true, asked);
}

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
}

Future<void> loadAll(TimelineScene scene) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
}

void main() {
  test('타일에 걸친 띠는 조각마다 그리되 잘린 쪽에는 모서리와 테두리가 없다', () async {
    final (scene, painter, _) = make();
    await loadAll(scene);
    scene.prepare();
    expect(scene.level, 9);
    expect(scene.stats.blanks, 0);
    paint(painter);
    final pieces = painter.debugBands;
    expect(pieces.map((b) => b.id).toList()..sort(), [1, 1, 2, 3]);
    final first = pieces.where((b) => b.id == 1).toList()..sort((a, b) => a.rect.left.compareTo(b.rect.left));
    // 왼쪽 조각은 화면 왼쪽 밖에서 시작하므로(지금 연표의 clip-l) 그쪽 귀도 펴진다. 오른쪽은 꼬리표(갈래 E)라 진짜 끝도 늘 직각.
    expect((first[0].roundLeft, first[0].roundRight), (false, false));
    expect((first[1].roundLeft, first[1].roundRight), (false, false));
    expect(pieces.firstWhere((b) => b.id == 2).roundLeft, isTrue, reason: '화면 안에서 시작한 띠는 왼쪽 귀가 모따기(5)');
    expect(pieces.firstWhere((b) => b.id == 2).roundRight, isFalse, reason: '꼬리표의 오른쪽 끝은 직각');
    expect(first[0].rect.right, first[1].rect.left, reason: '이음매는 같은 정수 px에서 만난다');
    expect(first[0].rect.right, first[0].rect.right.roundToDouble());
    // 띠의 세로 자리: 날짜 칸 밑에서 줄의 띠 자리 19, 둘째 줄은 142 아래.
    final head = scene.controller.view.head;
    expect(first[0].rect.top, head + 19);
    expect(first[0].rect.height, 123);
    expect(pieces.firstWhere((b) => b.id == 3).rect.top, head + 142 + 19);
    expect(pieces.firstWhere((b) => b.id == 3).fadeRight, isTrue, reason: '끝 미정은 옅은 끝');
  });

  test('띠 이름은 한 번만, 화면 왼쪽 밖에서 시작한 띠는 가장자리에 붙는다', () async {
    final (scene, painter, _) = make();
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    final tabs = painter.debugLabels.where((l) => l.kind == 'tab').toList();
    expect(tabs.map((l) => l.text).toList()..sort(), ['별여울국', '은빛 나루', '해솔국']);
    final stuck = tabs.firstWhere((l) => l.text == '별여울국');
    // 꼬리표 갈래 E: 이름은 띠 안 머리에 — 띠 시작이 화면 밖이면 화면 가장자리 6px 안쪽에 붙는다(탭 어깨 · 안 여백 없음).
    expect(stuck.at.dx, SceneView.gutter + 6);
    final free = tabs.firstWhere((l) => l.text == '해솔국');
    final view = scene.controller.view;
    // 화면 안에서 시작한 띠의 이름은 구멍에서 7 오른쪽(설계 4-1 '구멍과 꼬리 마름모'). 리메이크 2부 '두 장 ㄴ'부터 구멍은 띠 전체 키가 아니라
    // 이름 색줄(G.head 14)의 귀에 맞춘다 — 모따기 5 + 2 = 7(키 123인 이 띠의 귀 12로 재면 7px 더 밀린다).
    final x0 = view.xOf(67108864 + 2.5 * m);
    expect(TagLook.holeAt(TagEnd.cham, G.head), TagLook.holeX);
    expect(free.at.dx, closeTo(x0 + TagLook.holeAt(TagEnd.cham, G.head) + TagLook.nameGap, .5));
    // 트랙 이름은 왼쪽 칸 층이 세로 글로 한 글자씩 놓는다(자세한 것은 gutter_test).
    expect(painter.debugLabels.where((l) => l.kind == 'track').map((l) => l.text).join().replaceAll(' ', ''), '해솔갈래');
  });

  test('칸 이름은 들어갈 때만 그린다', () async {
    final (scene, painter, _) = make();
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    final names = painter.debugLabels.where((l) => l.kind == 'cell').toList();
    // 걸친 칸의 이름은 한 번만. 좁은 칸은 들 만큼의 앞글자로 잘라 그린다(지금 연표의 is-clip — 자세한 것은 strips_paint_test · 명세 01의 3-6 라).
    // 칸 글이 8.5px(꼬리표 갈래 E의 흰 층)라 23px 남짓한 내각 칸에도 앞의 두 글자가 든다.
    expect(names.where((l) => l.text == '첫째 지도자').length, 1);
    expect(names.every((l) => l.text == '첫째 지도자' || ('해솔 내각'.startsWith(l.text) && l.text.length < '해솔 내각'.length)), isTrue,
        reason: '온 이름이 아니면 그 이름의 앞토막뿐: ${names.map((l) => l.text)}');
    // 잘린 이름도 제 칸 안에서 시작한다.
    final cabinet = [for (final v in painter.debugSink.notes['칸'] ?? const <Object>[]) '$v'].firstWhere((s) => s.startsWith('2:0:0 '));
    final box = cabinet.split(' ')[1].split(',').map((s) => int.parse(s) / 10).toList();
    for (final l in names.where((l) => l.text != '첫째 지도자')) {
      expect(l.at.dx, inInclusiveRange(box[0], box[0] + box[2]), reason: '${l.text} — 내각 칸 안');
    }
  });

  test('새 글줄은 장면마다 정해진 만큼만 준비하고 다음 장면에 이어 간다', () async {
    final (scene, painter, _) = make();
    painter.text.maxNewPerFrame = 2;
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    expect(scene.stats.newParagraphs, 2);
    expect(painter.text.starved, isTrue);
    expect(scene.busy.value, isTrue, reason: '못 그린 이름이 있으면 다음 장면을 청한다');
    int frames = 1;
    while (painter.text.starved && frames < 100) {
      paint(painter);
      expect(scene.stats.newParagraphs, lessThanOrEqualTo(2));
      frames++;
    }
    expect(frames, greaterThan(10), reason: '날짜 칸의 이름까지 수십 개를 두 개씩 나눠 준비한다');
    final body = painter.debugLabels.where((l) => const ['tab', 'cell', 'track'].contains(l.kind)).toList();
    expect(body.length, greaterThanOrEqualTo(5), reason: '띠 이름 3 + 칸 이름 1 + 트랙 이름(세로 글 — 글자마다 하나)');
    paint(painter);
    expect(scene.stats.newParagraphs, 0, reason: '한 번 모양을 잡은 글줄은 다시 만들지 않는다');
  });

  test('제 단계의 타일이 없으면 윗단계 타일을 그 자리만큼만 잘라 메운다', () async {
    final (scene, painter, asked) = make(only: {(11, 0)});
    // 단계 9의 응답은 비어 있고 단계 11에만 띠가 있다 → 먼저 단계 11만 받아 둔 상태를 만든다.
    scene.cache.want([TileKey(11, 0, 0, scene.layout.version)], const []);
    await pumpEventQueue();
    scene.prepare();
    expect(scene.draw.where((d) => d.isCover).length, 2, reason: '보이는 단계 9 타일 둘을 단계 11이 메운다');
    expect(scene.draw.every((d) => d.clip != null), isTrue);
    expect(scene.stats.blanks, 0);
    paint(painter);
    expect(painter.debugBands.where((b) => b.id == 1).length, 2, reason: '메움은 타일 자리마다 한 번씩, 잘라서');
    expect(asked.first, (11, 0));
  });

  test('막 도착한 타일은 200ms 동안 떠오르고 그동안 시계가 돈다', () async {
    var now = 0.0;
    final controller = TimelineController()
      ..resize(1920, 1080)
      ..setExtent(-2000 * m, 2000 * m)
      ..setContentHeight(284);
    controller.showRange(57.1 * m, 57.1 * m + (1920 - SceneView.gutter) / (32 / bucketMinutes(9)));
    final data = tiles();
    final scene = TimelineScene(
      controller: controller,
      layout: layout(),
      clock: () => now,
      fetchTile: (level, x, chunk, packs) async => data[(level, x)] ?? TileBuilder(level: level, x: x, chunk: chunk).build(),
    );
    await loadAll(scene);
    now = 50;
    scene.prepare();
    final fresh = scene.draw.where((d) => !d.isCover).first;
    expect(fresh.alpha, closeTo(.25, .01));
    expect(scene.fading, isTrue);
    now = 250;
    scene.prepare();
    expect(scene.draw.every((d) => d.alpha == 1), isTrue);
    expect(scene.fading, isFalse);
  });

  // 날짜 칸(연도 눈금 · 시대 구분 · 간지)의 검사는 axis_model_test · axis_paint_test로 옮겼다 — 줄 구성과 높이를 자료가 정하게 되어 여기의 굳은 값(높이 74)이 맞지 않는다.

  test('이름은 띠의 진짜 끝을 넘지 않고, 같은 단에서 겹치는 이름은 뒤의 것을 그리지 않는다', () async {
    final controller = TimelineController()
      ..resize(1920, 1080)
      ..setExtent(-2000 * m, 2000 * m)
      ..setContentHeight(284);
    final ppm = 32 / bucketMinutes(9);
    // 타일 경계(67.1백만 분)가 그림 영역 왼쪽에서 60px 자리에 오게 한다.
    controller.showRange(67108864 - 60 / ppm, 67108864 - 60 / ppm + (1920 - SceneView.gutter) / ppm);
    final left = TileBuilder(level: 9, x: 0, chunk: 0)..band(1, 0, 67108864 - 40 / ppm, 67108864, '별여울 은빛 나루 연맹국', flags: Tile.clipRight);
    final right = TileBuilder(level: 9, x: 1, chunk: 0)
      ..band(1, 0, 0, 30 / ppm, '별여울 은빛 나루 연맹국', flags: Tile.clipLeft) // 띠 전체는 70px뿐 — 이름(126px)이 들어가지 않는다
      ..band(2, 1, 100 / ppm, 900 / ppm, '해솔국')
      ..cell(20, 1, 100 / ppm, 500 / ppm, '첫째 지도자')
      // 자료가 겹쳐 와도 이름은 겹쳐 그리지 않는다 — 두 칸의 가운데가 15px뿐이라 이름(칸 글 8.5px · 40px 남짓)이 겹친다.
      ..cell(21, 1, 110 / ppm, 520 / ppm, '겹친 지도자');
    final data = {(9, 0): left.build(), (9, 1): right.build()};
    final scene = TimelineScene(
      controller: controller,
      layout: layout(),
      fetchTile: (level, x, chunk, packs) async => data[(level, x)] ?? TileBuilder(level: level, x: x, chunk: chunk).build(),
    );
    final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
    await loadAll(scene);
    paint(painter);
    final names = painter.debugLabels.map((l) => l.text).toList();
    expect(names, isNot(contains('별여울 은빛 나루 연맹국')), reason: '왼쪽 조각만 보면 화면 끝까지 자리가 있어 보이지만 띠는 70px에서 끝난다');
    expect(names, contains('해솔국'));
    expect(names, contains('첫째 지도자'));
    expect(names, isNot(contains('겹친 지도자')));
  });

  test('띠의 채움: 온전한 쪽 모서리는 둥글고, 잘린 쪽은 끝까지 차고, 끝 미정인 쪽은 바탕으로 스며든다', () async {
    final (scene, painter, _) = make();
    await loadAll(scene);
    scene.hide.add('fade'); // 떠오르는 중이 아닌 다 뜬 모습을 본다
    final pixels = await render(painter);
    int at(double x, double y) => pixels.getUint32((y.floor() * 1920 + x.floor()) * 4);
    final whole = painter.debugBands.firstWhere((b) => b.id == 2).rect; // 양쪽이 온전한 띠
    // 띠의 맨 윗단(테두리 아래 · 칸 위)은 채움만 보인다. 윗 모서리에는 책갈피 탭이 비치므로 아래 모서리로 본다.
    final y = whole.top + 2.5, low = whole.bottom - 2.5, fill = at(whole.center.dx, y);
    expect(fill, isNot(at(whole.center.dx, whole.bottom + 3)));
    expect(at(whole.left + .5, low), at(whole.left + .5, whole.bottom + 3), reason: '왼쪽 아래 귀는 모따기(꼬리표 갈래 E)라 끝 px에는 바탕이 보인다');
    // 오른쪽 끝은 꼬리표라 늘 직각이다(bands_paint_test). 이 띠의 오른쪽은 화면 밖(오른쪽 끝 = 화면 끝 + 1)이라 여기서는 보지 않는다 —
    // 예전의 '오른쪽 아래 모서리' 검사는 화면 밖 x(1920.5)를 읽어 다음 줄의 화소끼리 견주고 있었다.
    expect(whole.right, 1921);
    expect(at(whole.left + 12, y), fill, reason: '귀를 지나면 채움');
    final cut = painter.debugBands.firstWhere((b) => b.id == 1 && !b.roundRight).rect; // 오른쪽이 타일 경계에서 잘린 조각
    expect(at(cut.right - .5, cut.top + 2.5), at(cut.center.dx, cut.top + 2.5), reason: '잘린 쪽은 끝까지 차 있다');
    final fuzzy = painter.debugBands.firstWhere((b) => b.id == 3).rect; // 끝 미정(띠 폭에 44px 꼬리가 더해진다)
    // 높이 18px인 책갈피 탭 때문에 띠 위 15.5px는 더 이상 빈 바탕이 아니다.
    // 채움만 숨긴 같은 장면의 같은 화소를 기준으로 삼아 눈금 · 테두리 · 탭을 셈에서 뺀다.
    scene.hide.add('bandFill');
    final background = await render(painter);
    scene.hide.remove('bandFill');
    int bare(double x) => background.getUint32(((fuzzy.top + 2.5).floor() * 1920 + x.floor()) * 4);
    // 한 색 채널의 차이가 작아(13쯤) 반올림에 휘둘리므로 세 채널의 차이를 더해 견준다. 그림판 바탕이 회색(건의 2026-10-15 1번)이라
    // 옅은 미정 띠(6%)는 바탕보다 밝을 수 있다 — 차이의 크기로 본다.
    double ink(double x) => [24, 16, 8].fold(0.0, (sum, shift) => sum + ((bare(x) >> shift) & 0xff) - ((at(x, fuzzy.top + 2.5) >> shift) & 0xff)).abs();
    final full = ink(fuzzy.left + 20);
    expect(full, greaterThan(3), reason: '꼬리 밖은 띠의 바탕이 보인다');
    expect(ink(fuzzy.right - 3.5), lessThan(full * .25), reason: '끝에서는 거의 바탕');
    // 가운데 쪽은 끝에서 26px 자리에서 본다 — 끝의 22px는 둥근 모서리 조각(반지름 22 · 조각 하나에 옅기 하나)이라 그 경계에서는 값이 계단으로 뛴다.
    expect(ink(fuzzy.right - 26), closeTo(full * .5, full * .25), reason: '44px의 가운데 쪽은 반쯤');
    expect(ink(fuzzy.right - 50), closeTo(full, 1), reason: '꼬리 밖은 그대로');
  });

  test('띠의 채움은 띠마다 따로 그리지 않고 네모 묶음과 모서리 조각으로 한 번에 그린다', () async {
    final (scene, painter, _) = make();
    await loadAll(scene);
    final spy = _SpyCanvas();
    painter.paint(spy, const Size(1920, 1080));
    expect(painter.debugBands.length, 4);
    expect(spy.filledRRects, 0, reason: '둥근 네모 채움은 하나하나가 따로 처리돼 돋보기 60%에서 칠하기가 한도를 넘었다');
  });

  test('타일이 둘이어도 그리기 호출은 타일 수만큼 늘지 않는다', () async {
    final (scene, painter, _) = make();
    await loadAll(scene);
    scene.hide.add('fade'); // 다 뜬 타일(떠오르는 중이면 제 자리를 층으로 감싸야 해서 타일마다 따로 돈다)
    scene.prepare();
    expect(scene.draw.length, 2, reason: '보이는 타일 둘');
    expect(scene.draw.every((d) => d.clip == null && d.alpha == 1), isTrue, reason: '메움도 떠오르는 중도 아니다');
    final spy = _SpyCanvas();
    painter.paint(spy, const Size(1920, 1080));
    // 타일은 서로 겹치지 않으므로 층을 바깥 · 타일을 안쪽으로 돈다 → 내보내기가 (층 × 타일)이 아니라 (층)이다.
    // 이 장면의 걸음은 열둘(뒤 판 3 · 앞 판 8 · 표식 판 1)이고 여기에 눈금 · 사건 · 왼쪽 칸 · 날짜 칸의 몫이 더해진다.
    // ignore: avoid_print
    print('타일 ${scene.draw.length}장 · 묶음 그리기 호출 ${spy.batchDraws}번');
    expect(spy.batchDraws, lessThanOrEqualTo(18), reason: '타일마다 층을 다 돌던 옛 판은 같은 장면에서 21번이었다');
  });
}

Future<ByteData> render(TimelinePainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1920, 1080);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return data!;
}

/// 그리기 호출을 세는 가짜 화폭.
class _SpyCanvas implements ui.Canvas {
  int filledRRects = 0;

  /// 묶음이 내보낸 그리기 호출(네모 · 무늬 묶음 = drawVertices, 조각 · 글자 그림판 = drawRawAtlas).
  int batchDraws = 0;

  @override
  void drawRRect(ui.RRect rrect, ui.Paint paint) {
    if (paint.style == ui.PaintingStyle.fill) filledRRects++;
  }

  @override
  void drawVertices(ui.Vertices v, ui.BlendMode mode, ui.Paint paint) => batchDraws++;

  @override
  void drawRawAtlas(ui.Image atlas, Float32List transforms, Float32List rects, Int32List? colors, ui.BlendMode? mode, ui.Rect? cull, ui.Paint paint) => batchDraws++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

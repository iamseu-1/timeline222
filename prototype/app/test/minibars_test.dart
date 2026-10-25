import 'load_app_fonts.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/glyph_atlas.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:flutter/services.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/context.dart';
import 'package:archive_prototype/scene/paint/minibars.dart';
import 'package:archive_prototype/scene/paint/patterns.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 접힌 트랙 · 접힌 민족 줄의 가는 막대(명세 05의 5.3절 · 실측 9.2 · 9.3).
// 자리의 정답은 기준 덤프의 숫자다(트랙 위 469 기준): 단 0 → 474(= +5) · 단 1 → 482(+8) · 단 2 → 490 · 높이 6.
// 조감(접힌 트랙 22): 단 0 → 474.5(= 469 + (22 − 11)/2) · 단 1 → 478.5 · 높이 3.
// 단은 자료(구역 45의 a · b)로 미리 정해져 온다 — 화면이 정하지 않는다.

const m = 1000000.0;
const level = 9;

/// 지금 연표의 해 좌표 → 1970년 기준 분(render_scene_test와 같은 투영).
double minuteOfYear(double y) {
  final year = y.floor();
  final a = DateTime.utc(year < 0 ? year + 1 : year), b = DateTime.utc(year == -1 ? 1 : (year < 0 ? year + 2 : year + 1));
  return (a.millisecondsSinceEpoch + (b.millisecondsSinceEpoch - a.millisecondsSinceEpoch) * (y - year)) / 60000;
}

Map<String, dynamic> rowSpec(int id, {bool groupStart = false}) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 40, 'text_lines': 1, 'rail_top': 61, 'organ_top': -1,
  'kind': 0, 'group_start': groupStart ? 1 : 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'dep': 0, 'zones': 0, 'hem': 0,
};

SceneLayout makeLayout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xa0bcc5, 'rail_levels': 2,
      'rows': [for (int i = 0; i < 4; i++) rowSpec(i, groupStart: i == 1)],
      'groups': [
        {'depth': 0, 'first': 1, 'count': 3, 'name': '해솔 사람', 'color': 0xdab195, 'kind': 0},
      ],
    },
  ],
});

/// 구역 45: 띠마다 (a = 접힌 트랙용 단 · b = 접힌 민족 줄용 단).
Uint8List makeTile() => (TileBuilder(level: level, x: 0, chunk: 0)
      ..item(45, 1, 0, 2 * m, 20 * m, ref: 1, name: '해솔국', color: 0xa0bcc5, a: 0, b: 0)
      ..item(45, 2, 1, 4 * m, 18 * m, ref: 2, name: '별목국', color: 0xdab195, a: 1, b: 0)
      ..item(45, 3, 2, 6 * m, 8 * m, ref: 3, name: '흰계단국', color: 0x9dbea8, a: 2, b: 1)
      // 아주 짧은 띠도 막대는 3px보다 좁아지지 않는다.
      ..item(45, 4, 3, 10 * m, 10.001 * m, ref: 4, name: '잔닻국', color: 0xd7c18e, a: 0, b: 2))
    .build();

class Rig {
  Rig(this.scene, this.layer, this.c, this.tile);
  final TimelineScene scene;
  final MiniBarLayer layer;
  final PaintContext c;
  final Tile tile;

  void paint() {
    layer.beginFrame(c);
    layer.paintTile(c, tile);
  }
}

Rig make({int density = 0}) {
  final layout = makeLayout();
  if (density != 0) layout.setConditions(layout.conditions.copyWith(density: density));
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(layout.totalHeight);
  final span = (1920 - 240) / (32 / bucketMinutes(level));
  controller.showRange(0, span);
  final scene = TimelineScene(controller: controller, layout: layout, fetchTile: (l, x, chunk, packs) async => TileBuilder(level: l, x: x, chunk: chunk).build());
  final recorder = ui.PictureRecorder();
  final c = PaintContext(
    canvas: ui.Canvas(recorder), scene: scene, text: ParagraphText(), w: 1920, h: 1080,
    quads: Quads(), dividers: Lines(Look.line), later: TextQueue(), patterns: Patterns(),
  );
  return Rig(scene, MiniBarLayer(), c, Tile.decode(makeTile()));
}

void main() {
  test('접힌 트랙의 막대는 트랙 위 + 5에서 단마다 8px씩 · 높이 6', () {
    final rig = make();
    addTearDown(rig.scene.dispose);
    rig.scene.layout.foldTrack(rig.scene.layout.tracks[0].id, true);
    rig.paint();
    final bars = rig.layer.bars;
    expect(bars.length, 4, reason: '그 트랙의 띠마다 막대 하나');
    final top = rig.c.v.yOf(rig.scene.layout.trackTop(0));
    for (final bar in bars) {
      expect(bar.height, Mini.height);
      expect(bar.top, closeTo(top + Mini.top + bar.lane * Mini.pitch, 1e-6));
    }
    // 단은 자료의 a(접힌 트랙용)를 그대로 쓴다.
    expect({for (final b in bars) b.band: b.lane}, {1: 0, 2: 1, 3: 2, 4: 0});
    // 기준 덤프의 자리: 트랙 위 + 5 · +13 · +21
    final lanes = {for (final b in bars) b.lane: b.top - top};
    expect(lanes[0], 5);
    expect(lanes[1], 13);
    expect(lanes[2], 21);
  });

  test('접힌 민족 줄의 막대는 그 줄의 단(자료의 b)을 쓰고 묶음의 머리 줄에 모인다', () {
    final rig = make();
    addTearDown(rig.scene.dispose);
    // 트랙 0의 묶음 0(줄 1~3)
    final track = rig.scene.layout.tracks[0];
    rig.scene.layout.foldGroup(track, track.groups[0], true);
    rig.paint();
    final bars = rig.layer.bars;
    // 묶음 밖의 줄 0은 막대가 아니라 띠로 그린다.
    expect(bars.map((b) => b.band).toSet(), {2, 3, 4});
    expect({for (final b in bars) b.band: b.lane}, {2: 0, 3: 1, 4: 2});
    final head = rig.c.v.yOf(rig.scene.layout.rowTop(1) + rig.scene.layout.geo(1).bandTop);
    for (final bar in bars) {
      expect(bar.top, closeTo(head + Mini.top + bar.lane * Mini.pitch, 1e-6), reason: '묶음의 머리 줄(1)에 모인다');
    }
  });

  // 리메이크 2부(목업 서고의 닫힌 폴더 · 상자): 접힌(닫힌) 그릇 = 대범위 가지는 **가지의 줄만** 한 줄로 모으되 막대 · 줄무늬를 그리지 않는다 —
  // 윗변에 매단 작은 꼬리표만(paint/scopes.dart). 민족 묶음 · 접힌 트랙의 막대는 그대로다(위 두 검사).
  test('닫힌 그릇(접힌 대범위 가지)은 **가지의 줄만** 모으고 막대 · 줄무늬를 그리지 않는다 — 사이에 낀 줄은 제 띠로 남는다', () {
    // 줄 0 · 2를 한 가지로 모으고(줄 번호가 이어지지 않는다) 줄 1 · 3은 그대로 둔다.
    final layout = SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
      'tracks': [
        {
          'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xa0bcc5, 'rail_levels': 2,
          'rows': [for (int i = 0; i < 4; i++) rowSpec(i)],
          'groups': <dynamic>[],
        },
      ],
      'variants': [
        {
          'id': 1, 'key': 'scope:s1', 'kind': 2, 'track': 1, 'band': 0, 'uid': 's1', 'name': '빈 왕좌의 할거',
          'rows': [
            {'row': 0, 'after': -1, 'ord': 0, 'new': 0, 'scope_pad': 16, 'group_start': 0},
            {'row': 2, 'after': 0, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
            {'row': 1, 'after': 2, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
          ],
          'groups': [
            {'key': '__scope:s1', 'depth': 0, 'name': '빈 왕좌의 할거', 'color': 0xd4a39b, 'kind': 2, 'rows': [0, 2]},
          ],
        },
      ],
    })
      ..reduceMotion = true;
    final rig = make()..scene.dispose();
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(1920, 1080)
      ..setExtent(-2000 * m, 2000 * m)
      ..setContentHeight(layout.totalHeight);
    controller.showRange(0, (1920 - 240) / (32 / bucketMinutes(level)));
    final scene = TimelineScene(controller: controller, layout: layout, fetchTile: (l, x, chunk, packs) async => TileBuilder(level: l, x: x, chunk: chunk).build());
    addTearDown(scene.dispose);
    final recorder = ui.PictureRecorder();
    final c = PaintContext(
      canvas: ui.Canvas(recorder), scene: scene, text: ParagraphText(), w: 1920, h: 1080,
      quads: Quads(), dividers: Lines(Look.line), later: TextQueue(), patterns: Patterns(),
    );
    final layer = MiniBarLayer();
    void paint() {
      layer.beginFrame(c);
      layer.paintTile(c, rig.tile);
    }

    layout.openScope('s1', true);
    paint();
    expect(layer.bars, isEmpty, reason: '펴진 가지에는 막대가 없다 — 띠로 그린다');

    expect(layout.foldVariantGroup(0, '__scope:s1', true), isTrue);
    controller.setContentHeight(layout.totalHeight);
    paint();
    // 가지에 든 줄 0 · 2만 첫 줄(0)에 모이고, 사이에 낀 줄 1 · 뒤의 줄 3은 제 띠로 남는다.
    expect(layout.mergedRows.keys.toList(), [0]);
    expect(layout.mergedRows[0], contains(2), reason: '가지의 둘째 줄(흰계단국)이 첫 줄에 모인다');
    expect(layout.isVisible(0), isTrue);
    expect(layout.mergedRows[0], isNot(contains(1)), reason: '사이에 낀 줄(별목국)은 모이지 않는다');
    expect(layout.mergedRows[0], isNot(contains(3)));
    expect(layout.foldedVariantOf(0), startsWith('scope:'), reason: '모인 줄은 그릇 변형의 가지');
    // 닫힌 그릇에는 가는 막대가 없다(예전: 줄 0의 해솔국 · 줄 2의 흰계단국이 첫 줄의 막대로).
    expect(layer.bars, isEmpty, reason: '닫힌 그릇은 막대 없이 작은 꼬리표만');
    // 몸통 쪽 접힌 줄의 줄무늬도 없다(민족 묶음만 줄무늬).
    final before = c.quads.count;
    layer.paintFoldedRows(c);
    expect(c.quads.count, before, reason: '닫힌 그릇은 줄무늬 없이');
  });

  test('조감에서는 세 단이 낮은 칸의 가운데에 — 높이 3 · 사이 4', () {
    final rig = make(density: 2);
    addTearDown(rig.scene.dispose);
    rig.scene.layout.foldTrack(rig.scene.layout.tracks[0].id, true);
    rig.paint();
    final top = rig.c.v.yOf(rig.scene.layout.trackTop(0));
    // 접힌 트랙 22 · 세 단(3 + 4 + 4) → 첫 단은 (22 − 11) / 2 = 5.5
    expect(rig.scene.layout.foldedHeight, 22);
    for (final bar in rig.layer.bars) {
      expect(bar.height, Mini.birdHeight);
      expect(bar.top, closeTo(top + rig.scene.layout.miniTop(bar.lane), 1e-6));
    }
    final lanes = {for (final b in rig.layer.bars) b.lane: b.top - top};
    expect(lanes[0], 5.5);
    expect(lanes[1], 9.5);
    expect(lanes[2], 13.5);
  });

  // 그림으로 확인: 이 층은 그리개(painter.dart)에 아직 걸려 있지 않아(총괄의 몫) render_scene_test로는 뜰 수 없다.
  // 진짜 저장소로 장면을 그린 뒤 이 층을 손으로 돌려 같은 그림판에 덧그리고, 기준 그림(results/dom-r5/접힌-민족-전체.png)과 나란히 놓는다.
  //
  // **접힌 트랙은 아직 이 길로도 못 뜬다**: 장면이 타일을 고르는 `_chunkVisible`(scene.dart)이 `layout.isVisible(줄)`만 보는데
  // 트랙을 접으면 그 트랙의 줄이 모두 보이지 않게 되어 타일을 아예 받지 않는다(막대의 자료도 오지 않는다). 남의 파일이라 보고에만 적었다.
  test('진짜 자료로 접힌 민족 줄을 떠서 기준 그림과 견준다', () async {
    final dll = File('../engine/target/release/archive_engine.dll');
    final db = File(File('../data/moonwake3/archive.db').existsSync() ? '../data/moonwake3/archive.db' : '../data/moonwake3-gutter2/archive.db');
    if (!dll.existsSync() || !db.existsSync()) return;
    await loadAppFonts();
    for (final (family, path) in [('Noto Sans KR', 'C:/Windows/Fonts/NotoSansKR-VF.ttf')]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length)))).load();
    }
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    final info = await engine.start(db.absolute.path);
    final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
    final layout = SceneLayout.fromJson(Map<String, dynamic>.from((await engine.call({'op': 'layout'}))['data'] as Map));
    const width = 1920.0, height = 1080.0, top = 60.0;
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(width, height - top)
      ..setExtent(double.parse(meta['min'] as String), double.parse(meta['max'] as String))
      ..setContentHeight(layout.totalHeight);
    final scene = TimelineScene(
      controller: controller, layout: layout, fetchTile: engine.tile,
      ask: (query) async => Map<String, dynamic>.from((await engine.call(query))['data'] as Map),
    );
    addTearDown(scene.dispose);
    // 기준 장면 '접힌-민족-전체'와 같게: 유리해안의 '월흔해의 백성'을 접는다.
    final track = layout.tracks.firstWhere((t) => t.name == '유리해안');
    final group = track.groups.firstWhere((g) => g.name == '월흔해의 백성');
    expect(layout.foldGroup(track, group, true), isTrue);
    layout.finishFlow();
    controller.setContentHeight(layout.totalHeight);
    scene.applyLayoutToView();
    controller.resize(width, height - top);
    // 기준 그림과 같은 장면: 전체(−1500~1500년).
    controller.showRange(minuteOfYear(-1500), minuteOfYear(1500));
    controller.scrollTo(0);
    final text = AtlasText()
      ..maxNewPerFrame = 4000
      ..budgetMicros = 2000000;
    addTearDown(text.dispose);
    final painter = TimelinePainter(scene, text: text)..debug = true;
    final layer = MiniBarLayer();
    ui.Image? image;
    for (int i = 0; i < 200; i++) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(const ui.Rect.fromLTWH(0, 0, width, height), ui.Paint()..color = const ui.Color(0xfff4eee4));
      canvas.save();
      canvas.translate(0, top);
      canvas.clipRect(const ui.Rect.fromLTWH(0, 0, width, height - top));
      painter.paint(canvas, const ui.Size(width, height - top));
      // 이 층은 아직 그리개에 걸려 있지 않다 — 같은 그림판에 손으로 덧그린다(총괄이 걸면 이 줄은 없어진다).
      final c = PaintContext(
        canvas: canvas, scene: scene, text: text, w: width, h: height - top,
        quads: Quads(), dividers: Lines(Look.line), later: TextQueue(), patterns: Patterns(),
      );
      layer.beginFrame(c);
      for (final d in scene.draw) {
        layer.paintTile(c, d.tile);
      }
      layer.paintFoldedRows(c);
      c.flushShapes();
      layer.flush(c);
      canvas.restore();
      final picture = recorder.endRecording();
      final s = scene.stats;
      if (s.blanks == 0 && s.covers == 0 && !scene.fading && scene.settled && !text.starved && i > 6) {
        image = await picture.toImage(width.toInt(), height.toInt());
        picture.dispose();
        break;
      }
      picture.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      scene.tick(20);
    }
    expect(image, isNotNull, reason: '장면이 가라앉지 않았습니다');
    expect(layer.bars, isNotEmpty, reason: '접힌 민족 줄의 정권마다 가는 막대가 있어야 한다');
    final png = await image!.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final folder = Directory('../results/render-gutter2')..createSync(recursive: true);
    File('${folder.path}/접힌-민족-막대.png').writeAsBytesSync(png!.buffer.asUint8List());
    // 자리: 접힌 민족 줄의 띠 윗변 + 5 · 단마다 8 · 높이 6(명세 05의 5.3절).
    final head = layout.mergedGroups.keys.first;
    final rowTop = controller.view.yOf(layout.rowTop(head) + layout.geo(head).bandTop);
    for (final bar in layer.bars) {
      expect(bar.top, closeTo(rowTop + 5 + bar.lane * 8, .01));
      expect(bar.height, 6);
      expect(bar.lane, lessThan(3));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('아주 짧은 띠도 3px · 화면 밖은 잘리고 접히지 않은 자리에는 막대가 없다', () {
    final rig = make();
    addTearDown(rig.scene.dispose);
    rig.scene.layout.foldTrack(rig.scene.layout.tracks[0].id, true);
    rig.paint();
    final tiny = rig.layer.bars.firstWhere((b) => b.band == 4);
    expect(tiny.right - tiny.left, greaterThanOrEqualTo(Mini.minWidth));
    // 접힌 것이 하나도 없으면 막대도 없다.
    final plain = make();
    addTearDown(plain.scene.dispose);
    plain.paint();
    expect(plain.layer.bars, isEmpty);
  });
}

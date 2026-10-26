import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/paint/context.dart';
import 'package:archive_prototype/scene/paint/links.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/patterns.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 받침 카드(paint/bands.dart `paintHostSheets`)와 띠 뒤 승계선(paint/links.dart — 그리개의 걸음 'links-back')의 쌓임.
// 감독 지적(2026-10-25 "근데 등불왕국 부분 계승 줄이 끊겨있는데"): 등불 왕국 → 검은물 의병 · 남강 임시정부의 부흥선은 세로 통로
// (qEnd + 9 + 5k — 명세 04 3-6 hv)가 같은 줄에 맞붙은 속국 하연 총관부 밑을 지난다. 총관부 꼬리표는 사건 칸을 남의 칸 층만큼 올린
// 짧은 몸통인데, 받침 카드와 그 둘레의 바탕빛 틈을 줄 몫(띠 아랫변)까지 칠해 꼬리표 밑 ~ 띠 아랫변에서 선이 지워졌다(선이 허공에서 시작).
// 받침 카드 걸음은 승계선 걸음보다 뒤라, 카드 · 틈이 꼬리표의 보이는 몸통 밖으로 나오면 그 밑의 선을 덮는다.

const m = 1000000.0;

/// 구역 21(승계선)의 a 비트 — links_test와 같은 값.
const lkDown = 1 << 4, lkQFirst = 1 << 5;

/// 두 장 꼬리표 줄 하나(줄 값이 실린 새 저장소 — 비트 19 · 막대 단 + 1 비트 3). [leader]면 그 줄에 지도자 층(비트 17), [raised]면 받침 카드가 솟는 줄(비트 14).
Map<String, dynamic> row(int id, {bool leader = false, bool raised = false}) => {
  'id': id, 'height': 160, 'band_top': 19, 'band_h': 141, 'dyn_top': -1, 'lead_top': 23, 'cab_top': 46, 'text_top': 66, 'text_lines': 2,
  'rail_top': 108, 'organ_top': -1, 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0,
  'fig_wide': (1 << 3) | (leader ? 1 << 17 : 0) | (raised ? 1 << 14 : 0) | (1 << 19), 'dep': 0, 'zones': 0, 'hem': 0,
};

/// 줄 0: 선대(지도자 층을 가진 띠) + 맞붙은 속국(칸 없음 — 사건 칸을 지도자 층만큼 올린 짧은 꼬리표) · 줄 1: 후대.
SceneLayout layout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'leader': 0, 'rows': [row(0, leader: true, raised: true), row(1)]},
  ],
});

const t0 = 6 * m, host = 0x8b6f47, ink = 0xabb3c9;

/// 선대 '앞 나라'(1)가 t0에 끝나고 같은 줄에 속국 '갈대 공국'(2 — 상국 '하연 왕국'의 받침 카드)이 맞붙는다. 앞 나라 → 아랫 줄 '뒷 나라'(3)의
/// 승계선은 세로 통로가 갈대 공국 밑을 지난다(등불 왕국 → 하연 총관부 밑 → 검은물 의병의 꼴).
Uint8List tile() => (TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(1, 0, 1 * m, t0, '앞 나라', look: 1 << 20 | 1 << (21 + 5))
      ..band(2, 0, t0, 12 * m, '갈대 공국')
      ..band(3, 1, t0 + 2 * m, 13 * m, '뒷 나라')
      ..item(LinkLayer.secSquare, 101, 0, 1 * m, t0, ref: 1, name: '앞 나라', color: ink)
      ..item(LinkLayer.secSquare, 103, 1, t0 + 2 * m, 13 * m, ref: 3, name: '뒷 나라', color: 0x9ab5a0)
      ..item(BandLayer.sectionHostTab, 52, 0, t0, 12 * m, ref: 2, name: '하연 왕국', color: host, a: 1, d: 99, text2: 'p/hayeon')
      ..item(LinkLayer.secLink, 201, 0, t0, t0 + 2 * m, row2: 1, ref: 1, b: 3, color: ink, a: lkQFirst | lkDown))
    .build();

(TimelineScene, TimelinePainter) make() {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(480);
  final ppm = 32 / bucketMinutes(9);
  controller.showRange(0, (1920 - SceneView.gutter) / ppm);
  final bytes = tile();
  final scene = TimelineScene(
    controller: controller,
    layout: layout(),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  scene.hide.add('fade');
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
  scene.prepare();
  for (int i = 0; i < 20 && (i == 0 || painter.text.starved); i++) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }
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

/// 0xAARRGGBB → 그림이 돌려주는 0xRRGGBBAA(불투명).
int rgba(int argb) => ((argb & 0x00ffffff) << 8 | 0xff) & 0xffffffff;

int px(ByteData p, int x, int y) => p.getUint32((y * 1920 + x) * 4);

/// '선' 기록('x,y x,y … 짙기 1.00')의 꺾은 점들.
List<Offset> pointsOf(String note) => [
  for (final pair in note.split(' 짙기').first.split(' '))
    Offset(double.parse(pair.split(',')[0]), double.parse(pair.split(',')[1])),
];

void main() {
  // 0.1.1 다-1(감독 고름 2026-10-26): 선 길 route는 기본 끔 — 이 파일은 새 길의 값을 `--paint-on=route`와 같은 뜻(route = true)으로 지킨다(끈 꼴은 제 시험이 route = false로).
  setUp(() => PaintPick.route = true);
  tearDown(PaintPick.reset);
  test('받침 카드 · 바탕빛 틈은 속국 꼬리표의 보이는 몸통까지 — 그 밑을 지나는 띠 뒤 승계선이 끊기지 않는다', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    await settle(scene, painter);
    expect(painter.debugSink.notes['뒤장'], hasLength(1), reason: '속국 띠 뒤의 받침 카드 한 장');
    final geo = scene.layout.geo(0), band = painter.debugBands.firstWhere((b) => b.id == 2).rect;
    final full = band.top + geo.bandHeight; // 줄 몫의 띠 아랫변(예전 카드 · 틈의 아랫변)
    expect(full - band.bottom, G.floor, reason: '속국 꼬리표는 남의 지도자 층만큼 짧다(TagLook.eventLift)');

    // 승계선: 앞 나라의 꼬리 마름모 → 세로 통로(hv) → 뒷 나라의 구멍. 세로 통로는 갈대 공국 꼬리표 안을 지난다.
    final lines = [for (final v in painter.debugSink.notes['선'] ?? const <Object>[]) '$v'];
    expect(lines, hasLength(1), reason: '띠 뒤 승계선 한 가닥: $lines');
    final pts = pointsOf(lines.single);
    expect(pts, hasLength(4), reason: '꺾은선 hv: $pts');
    final xm = pts[1].dx;
    expect(pts[2].dx, xm, reason: '세로 통로');
    expect(xm, inExclusiveRange(band.left + 2, band.right - 2), reason: '세로 통로가 속국 꼬리표 밑을 지난다');
    expect(pts[2].dy, greaterThan(full + 4), reason: '선은 아랫 줄까지 내려간다');

    final pixels = await render(painter);
    final x = xm.floor();
    // 기준: 같은 기둥에서 줄 0의 띠 아랫변 밑(카드 · 틈이 예전에도 닿지 않던 바탕) — 바탕 위의 선 빛깔. 점선 눈금이 지나도 홀짝을 맞춰 견준다.
    final y0 = (full + 3).ceil();
    final ref = [px(pixels, x, y0), px(pixels, x, y0 + 1)];
    for (final r in ref) {
      expect(r, isNot(rgba(Look.ground)), reason: '바탕 위에는 선이 보인다(기둥 $x)');
    }
    final card = rgba(mixOklab(0xff000000 | host, Look.paper, BandLayer.sheetMix[1]));
    // 꼬리표 몸통 밑 ~ 줄 몫의 띠 아랫변: 선이 바탕 위와 같은 빛깔로 이어진다(예전: 카드 칠 · 바탕빛 틈이 덮어 끊김).
    for (int y = (band.bottom + 2).ceil(); y <= (full - 2).floor(); y++) {
      final got = px(pixels, x, y);
      expect(got, isNot(card), reason: '꼬리표 밑($y)에 받침 카드가 나와 선을 덮는다');
      expect(got, isNot(rgba(Look.ground)), reason: '꼬리표 밑($y)에 바탕빛 틈이 나와 선을 지운다');
      expect(got, ref[(y - y0) & 1], reason: '꼬리표 밑($y)의 선이 바탕 위의 선과 같다');
    }

    // 카드는 그대로 띠 위로 5 드러나고(카드 칠), 띠 윗변 바로 위 1.5는 바탕빛 틈이다 — 승계선 · 눈금을 비킨 기둥에서 본다.
    final xs = [for (int x = (band.left + 40).floor(); x < band.right - 40; x++) x];
    expect(xs.any((x) => px(pixels, x, (band.top - BandLayer.sheetRise + 2).floor()) == card), isTrue, reason: '카드의 드러난 윗단');
    expect(xs.any((x) => px(pixels, x, (band.top - 1).floor()) == rgba(Look.ground)), isTrue, reason: '띠와 카드 사이의 바탕빛 틈');
  });

  // 0.1.1 이어 주는 선 미룸 1(스위치 mend — route에서 뗌): 구멍 · 마름모 x는 띠가 정하므로 관문 · 통로의 세로 획이 우연히 연도 세로줄과 같은 x에 서면
  // 점선 세로줄이 획에 섞인다 — 구멍 · 마름모를 옮기지 않고 그 세로줄 열을 획의 세로 범위만큼 바탕색 종이로 걷는다.
  test('띠 뒤 선의 세로 획과 같은 자리(덮거나 1px 안)의 연도 세로줄 열만 획의 세로 범위만큼 걷는다 — 먼 열 · 스위치 끔은 그대로', () async {
    final (scene, painter) = make();
    addTearDown(scene.dispose);
    addTearDown(PaintPick.reset);
    await settle(scene, painter);
    final pts = pointsOf('${(painter.debugSink.notes['선'] ?? const <Object>[]).single}');
    final xm = pts[1].dx, top = math.min(pts[1].dy, pts[2].dy), bottom = math.max(pts[1].dy, pts[2].dy);
    final host = scene.draw.firstWhere((d) => !d.isCover && d.alpha >= 1).tile;
    List<String> masked(List<double> columns) {
      final c = PaintContext(
        canvas: Canvas(ui.PictureRecorder()), scene: scene, text: unbudgetedText(), w: 1920, h: 1080, quads: Quads(), dividers: Lines(Look.line),
        later: TextQueue(), patterns: Patterns(), debug: DebugSink(),
      );
      painter.grid.columns
        ..clear()
        ..addAll(columns);
      painter.links.paintTile(c, host);
      return [for (final o in c.debug!.notes['세로줄 걷기'] ?? const <Object>[]) '$o'];
    }

    final col = xm.floorToDouble();
    final hit = masked([col - 6, col, col + 1, col + 6]);
    expect(hit, hasLength(2), reason: '획 열과 맞닿은 열 — $hit');
    expect(hit.first, contains('열 $col'));
    expect(hit.first, endsWith('${top.toStringAsFixed(1)} ~ ${bottom.toStringAsFixed(1)}'), reason: '세로 통로의 범위만');
    expect(masked([col - 6, col + 6]), isEmpty, reason: '먼 세로줄은 그대로');
    // 0.1.1 떼어서 살림(감독 고름 2026-10-26): route를 꺼도 걷는다 — 끄는 것은 스위치 mend.
    PaintPick.route = false;
    expect(masked([col]), hasLength(1), reason: 'route 끔 기본에서도 걷는다');
    PaintPick.mend = false;
    expect(masked([col]), isEmpty, reason: 'mend를 끄면 예전 그대로');
  });
}

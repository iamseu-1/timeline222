import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/chains.dart';
import 'package:archive_prototype/scene/paint/gutter.dart';
import 'package:archive_prototype/scene/paint/hangs.dart';
import 'package:archive_prototype/scene/paint/ink.dart';
import 'package:archive_prototype/scene/paint/links.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 꼬리표 밑 흰 사슬의 그림(감독 고름 G5 #9 나 · 차례 걸음 15 — docs/계획-리메이크-4단계.md · 고르기 판 `themes/g-g5-9b.js` chain() · below() ·
// subLabels() · 기준 그림 `out/shots/g9b-na.png`): 흰 종이(둥근 3 · 테 먹 45) · 칸 사이 세로 금 먹 25 · 글 8.5 굵게 먹 85(드는 만큼 줄임) ·
// 왕조의 가문 색 막대 3 × 8 · 지위의 서열 눈금(폭 2 · 간격 4 · 먹 45) · 꼬리표 시작에서 비롯하는 사슬의 구멍(띠 왼쪽 + 7) · 꼬리표 아랫변의 점에서
// 마지막 구멍까지 내려오는 실(종이 뒤 — 사슬 사이 틈에서만 보임) · 왼쪽 칸의 사슬 이름('왕조' · '지위' + 6px 금). 매단 속국 실은 종이 뒤로 지난다.
// 스위치 chain을 끄면(`--paint-off=chain`) 쌓기가 예전 칸 층이라 이 그림이 하나도 없다.

/// 단계 9에서 통 하나가 32px일 때의 1분 폭 — 자리는 모두 '그림 영역 왼쪽에서 몇 px'로 적고 분으로 바꾼다(strips_paint_test와 같은 식).
final ppm = 32 / bucketMinutes(9);
double at(double px) => px / ppm;

/// 엔진 답 꼴의 줄 하나(줄 값이 실린 새 저장소 — chain_layout_test와 같은 꼴): 왕조 · 지위 · 지도자 칸이 있고, [hang]이면 매단 속국 줄 하나.
Map<String, dynamic> row(int id, {int hang = 0}) => {
  'id': id,
  'height': 0,
  'band_top': 0,
  'band_h': 0,
  'dyn_top': -1,
  'lead_top': -1,
  'cab_top': -1,
  'text_top': 0,
  'text_lines': 1,
  'rail_top': 0,
  'organ_top': -1,
  'kind': 0,
  'group_start': 0,
  'scope_pad': 0,
  'phase': 0,
  'rank': 1,
  'cats': <int>[],
  'fig': 0,
  'fig_wide': 0,
  'dep': 0,
  'zones': hang,
  'hem': 0,
  'variant': 0,
  'rail': 0,
  'cell_rows': 1,
  'dynasty': 1,
  'leader': 1,
  'cabinet': 0,
  'hang': hang,
};

SceneLayout layoutOf({int hang = 0}) => SceneLayout.fromJson({
  'packs': [
    {'id': 1, 'name': '사슬 견본', 'events': 0},
  ],
  'tracks': [
    {
      'id': 1,
      'pack': 1,
      'ord': 0,
      'name': '하연 갈래',
      'color': 0xa0bcc5,
      'key': 'chain-a',
      'dynasty': 1,
      'leader': 1,
      'cabinet': 0,
      'organ': 0,
      'rail_levels': 2,
      'rows': [row(0, hang: hang)],
    },
  ],
  'epochs': <dynamic>[],
  'categories': <dynamic>[],
  'axis': <dynamic>[],
})..reduceMotion = true;

/// 띠 look: 비트 20 = 칸이 있다 · 21 + 0 왕조 · 21 + 2 지위 · 21 + 5 지도자.
const both = 1 << 20 | 1 << 21 | 1 << 23 | 1 << 26;

/// style: 순번(비트 15~26 = 순번 + 1) · 지위 서열(비트 8~10 = 단계 + 1).
int st({int seq = -1, int rank = -1}) => (seq < 0 ? 0 : (seq + 1) << 15) | (rank < 0 ? 0 : (rank + 1) << 8);

const peach = 0xd9a57a, lav = 0xa48fc9;

/// 하연 왕국(그림 영역 100 ~ 1500 px): 왕조 둘(100 ~ 700 · 700 ~ 1500 — 꼬리표 시작에서 비롯) · 지위 둘(왕국 서열 0 · 제국 서열 2) · 지도자 둘.
/// 그림 영역 1505 ~ 1580에 좁은 띠 — 띠 시작에서 47px 뒤(이 배율에서 통 하나 32px = 2^18분 ≒ 반년이라 반년보다 멀리)에 비롯하는 왕조 칸 하나
/// (1552 ~ 1580 · 구멍 없음 — 드는 만큼 줄임).
Uint8List chainTile({List<void Function(TileBuilder)> more = const []}) {
  final t = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, at(100), at(1500), '하연 왕국', look: both)
    ..band(2, 0, at(1505), at(1580), '좁은 나라', look: 1 << 20 | 1 << 21, color: 0xc8b193)
    ..cell(20, 0, at(100), at(700), '온씨 왕조', kind: 0, style: st(seq: 0), color: peach)
    ..cell(21, 0, at(700), at(1500), '서씨 왕조', kind: 0, style: st(seq: 1), color: lav)
    ..cell(30, 0, at(100), at(1000), '왕국', kind: 5, style: st(seq: 0, rank: 0))
    ..cell(31, 0, at(1000), at(1500), '제국', kind: 5, style: st(seq: 1, rank: 2))
    ..cell(10, 0, at(100), at(700), '온 하람', kind: 1, style: st(seq: 0))
    ..cell(11, 0, at(700), at(1500), '서 무진', kind: 1, style: st(seq: 1))
    ..cell(40, 0, at(1552), at(1580), '아주긴좁은왕조', kind: 0, style: st(seq: 0), color: peach);
  for (final f in more) {
    f(t);
  }
  return t.build();
}

(TimelineScene, TimelinePainter) make({Uint8List? data, double from = 0, int hang = 0}) {
  final layout = layoutOf(hang: hang);
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..setContentHeight(layout.totalHeight + 200);
  controller.showRange(at(from), at(from + 1920 - SceneView.gutter));
  final tile = data ?? chainTile();
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? tile : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
  for (int i = 0; i < 6; i++) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
    if (!painter.text.starved) break;
  }
  expect(painter.text.starved, isFalse, reason: '글줄 준비가 모자란 장면이다');
}

/// 장면을 그림으로 떠서 RGBA 바이트(1920×1080).
Future<Uint8List> pixelsOf(TimelinePainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1920, 1080);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// 그 픽셀의 0xRRGGBB(불투명 그림 — 알파는 뺌).
int rgbAt(Uint8List px, num x, num y) {
  final i = (y.floor() * 1920 + x.floor()) * 4;
  return px[i] << 16 | px[i + 1] << 8 | px[i + 2];
}

/// 회색 픽셀의 밝기(빨강 채널).
int grayAt(Uint8List px, num x, num y) => rgbAt(px, x, y) >> 16;

List<String> noted(TimelinePainter painter, String kind) => [for (final v in painter.debugSink.notes[kind] ?? const <Object>[]) '$v'];

/// 기록 '… x,y …'의 0.1px 값을 px로.
List<double> numbers(String part) => [for (final v in part.split(',')) int.parse(v) / 10];

/// 줄 0의 자리(화면 px): 띠 위 · 띠 아랫변(= 꼬리표 아랫변 — 띠 하나뿐이라 사건 칸 올림 0) · 왕조 사슬 위 · 지위 사슬 위.
({double bandTop, double bottom, double dyn, double rank}) placeOf(TimelineScene scene) {
  final layout = scene.layout, geo = layout.geo(0), v = scene.controller.view;
  final top = v.yOf(layout.rowTop(0) + geo.bandTop), bottom = top + geo.bandHeight;
  return (bandTop: top, bottom: bottom, dyn: bottom + G.chainGap, rank: bottom + G.chainPitch + G.chainGap);
}

const paper = 0xffffff, ground = Look.ground & 0xffffff;
final edge = CanvasInk.gray(ChainLook.edge) & 0xffffff;

void main() {
  tearDown(PaintPick.reset);

  test('꼴의 값 — 고르기 판 chain() 그대로(먹은 그림판 단계: 테 · 실 · 눈금 45 · 금 22 → 25 · 글 80 → 85)', () {
    expect(ChainLook.radius, 3);
    expect([CanvasInk.step(ChainLook.edge), CanvasInk.step(ChainLook.divider), CanvasInk.step(ChainLook.text)], [.45, .25, .85]);
    expect(edge, 0x8c8c8c);
    expect(ChainLook.textLook.size, 8.5);
    expect(ChainLook.textLook.weight, ui.FontWeight.w700);
    expect(ChainLook.textLook.color, CanvasInk.k85);
    expect([ChainLook.holeX, ChainLook.holeR, ChainLook.holeText, ChainLook.dotR], [7, 1.5, 13, 1.5]);
    expect([ChainLook.barW, ChainLook.barH, ChainLook.barAdvance], [3, 8, 7]);
    expect([ChainLook.tickW, ChainLook.tickPitch, ChainLook.tickGap], [2, 4, 5]);
    expect([ChainLook.labelRight, ChainLook.labelSize, ChainLook.lineFrom - ChainLook.lineTo], [12, 10, 6]);
    expect(ChainLook.labelOf(0), '왕조');
    expect(ChainLook.labelOf(1), '지위');
    expect(ChainLook.labelOf(1, leaders: true), '지도자');
    expect(
      [
        for (final l in [-1, 0, 1, 2, 4, 5]) ChainLook.ticksOf(l),
      ],
      [0, 0, 1, 2, 4, 4],
    );
  });

  test('이름 줄임 — 온 이름 → 왕조의 짧은 이름 → 첫 글자 → 없음(드는 만큼)', () {
    double? w(String s) => s.length * 8.0;
    expect(ChainLook.fit('온씨 왕조', 100, w, short: '온씨'), ('온씨 왕조', 40.0));
    expect(ChainLook.fit('온씨 왕조', 30, w, short: '온씨'), ('온씨', 16.0));
    expect(ChainLook.fit('온씨 왕조', 10, w, short: '온씨'), ('온', 8.0));
    expect(ChainLook.fit('온씨 왕조', 5, w, short: '온씨'), ('', 0.0));
    expect(ChainLook.fit('제국', 10, w), ('제', 8.0));
    expect(ChainLook.fit('제국', 0, w), ('', 0.0));
    expect(ChainLook.fit('제국', 100, (_) => null), isNull, reason: '글자 폭이 아직이면 다음 장면에');
  });

  test('종이 · 테 · 칸 사이 금 · 둥근 귀 — 흰 종이(둥근 3 · 테 먹 45)가 띠 테 그 자리부터 · 맞닿은 왕조 칸은 한 종이(세로 금 먹 25)', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final p = placeOf(scene);
    final left = scene.controller.view.xOf(at(100)); // 띠 시작 = 340
    expect(left, closeTo(340, 1e-6));
    // 왕조 사슬: 위 · 아래 테(먹 45) · 안은 흰 종이 · 왼쪽 테는 꼬리표 왼쪽 테와 같은 열.
    expect(rgbAt(px, 900, p.dyn), edge, reason: '윗 테');
    expect(rgbAt(px, 900, p.dyn + G.chain - 1), edge, reason: '아랫 테');
    for (final y in [1, 5, 9, 12]) {
      expect(rgbAt(px, 900, p.dyn + y), paper, reason: '종이 y+$y');
    }
    expect(rgbAt(px, 340, p.dyn + 7), edge, reason: '왼쪽 테 = 띠 테의 열(340)');
    expect(rgbAt(px, 340, p.bandTop + 20), isNot(paper), reason: '같은 열의 꼬리표 왼쪽 테');
    // 둥근 귀(3): 바깥 귀 픽셀은 거의 바탕, 귀 안쪽은 종이.
    expect(grayAt(px, 340, p.dyn), greaterThan(0xd8), reason: '왼쪽 위 귀 밖');
    expect(grayAt(px, 340, p.dyn + G.chain - 1), greaterThan(0xd8), reason: '왼쪽 아래 귀 밖');
    expect(rgbAt(px, 342, p.dyn + 2), paper, reason: '귀 안쪽');
    // 맞닿은 두 왕조 칸(700 = x 940): 한 종이 — 그 자리에 세로 금(먹 25 · 위아래 테 안) · 위 테는 끊기지 않음.
    expect(rgbAt(px, 940, p.dyn + 7), 0xbfbfbf, reason: '칸 사이 세로 금 먹 25');
    expect(rgbAt(px, 940, p.dyn), edge, reason: '이어 붙은 자리도 윗 테는 이어진다');
    expect(rgbAt(px, 939, p.dyn + 7), paper);
    expect(rgbAt(px, 941, p.dyn + 7), paper);
    // 오른쪽 끝(1500 = x 1740): 오른쪽 테(마지막 열 1739)와 둥근 귀 · 그 밖은 바탕.
    expect(rgbAt(px, 1739, p.dyn + 7), edge, reason: '오른쪽 테');
    expect(rgbAt(px, 1741, p.dyn + 7), ground, reason: '사슬 밖');
    expect(grayAt(px, 1739, p.dyn), greaterThan(0xd8), reason: '오른쪽 위 귀 밖');
    // 사슬 사이 틈(3)과 꼬리표 밑 틈은 바탕(실 · 점 자리 밖).
    expect(rgbAt(px, 900, p.dyn + G.chain + 1), ground, reason: '사슬 사이 틈');
    expect(rgbAt(px, 900, p.bottom + 1), ground, reason: '꼬리표 밑 틈');
    // 지위 사슬도 같은 꼴 — 지위 칸 둘(1000 = x 1240)도 한 종이.
    expect(rgbAt(px, 900, p.rank), edge);
    expect(rgbAt(px, 1240, p.rank + 7), 0xbfbfbf);
    // 기록: 사슬 칸은 종이 윗변부터 높이 14(칸 층의 윗선 + 1 들임 없음) · 이어 붙은 쪽은 귀가 없다.
    final chains = noted(painter, '사슬');
    expect(chains.where((n) => n.startsWith('0:0:1 ')).length, 2);
    expect(chains.firstWhere((n) => n.startsWith('0:0:1 3400,')), contains('jl=false jr=true 귀=3/0'));
    expect(chains.firstWhere((n) => n.startsWith('0:0:1 9400,')), contains('jl=true jr=false 귀=0/3'));
  });

  test('구멍과 실 — 꼬리표 시작에서 비롯하는 사슬의 첫 칸에 구멍(띠 왼쪽 + 7) · 꼬리표 아랫변의 점에서 마지막 구멍까지 실(종이 뒤)', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final p = placeOf(scene);
    const col = 340 + 7; // 실 · 구멍의 열
    // 구멍: 왕조 · 지위 사슬 모두 꼬리표 시작(100)에서 비롯 — 가운데 (347.5, 사슬 위 + 7).
    final holes = noted(painter, '사슬구멍');
    expect(holes, ['1 3475,${((p.dyn + 7) * 10).round()}', '1 3475,${((p.rank + 7) * 10).round()}']);
    // 구멍의 테(먹 45 언저리)는 종이보다 짙고, 구멍 가운데는 종이빛.
    var darkest = 255;
    for (int x = col - 2; x <= col + 2; x++) {
      for (int y = -2; y <= 2; y++) {
        final g = grayAt(px, x, p.dyn + 7 + y);
        if (g < darkest) darkest = g;
      }
    }
    expect(darkest, lessThan(0xd0), reason: '구멍 테');
    expect(grayAt(px, col - 4, p.dyn + 7), 0xff, reason: '구멍 왼쪽은 종이');
    // 실: 사슬 사이 틈(왕조 사슬 아래 테 밑 ~ 지위 사슬 위 테 위)의 그 열만 먹 45 — 종이 안(구멍 밑)에서는 보이지 않는다.
    for (int y = 0; y < G.chainGap; y++) {
      expect(rgbAt(px, col, p.dyn + G.chain + y), edge, reason: '사슬 사이 틈의 실 y+$y');
      expect(rgbAt(px, col - 1, p.dyn + G.chain + y), ground);
      expect(rgbAt(px, col + 1, p.dyn + G.chain + y), ground);
    }
    expect(rgbAt(px, col, p.dyn + 11), paper, reason: '실은 종이 뒤(구멍 밑 종이에서 보이지 않는다)');
    expect(rgbAt(px, col, p.rank + G.chain + 1), ground, reason: '실은 마지막 구멍에서 끝난다');
    // 꼬리표 아랫변의 점(반지름 1.5 — 꼬리표와 첫 사슬 사이 틈 3을 메움).
    expect(grayAt(px, col, p.bottom + 1), lessThan(0xc0), reason: '점');
    expect(rgbAt(px, col - 3, p.bottom + 1), ground);
    final thread = noted(painter, '사슬실').single.split(' ');
    expect(thread[0], '1');
    expect(numbers(thread[1]), [col, p.bottom, p.rank + 7]);
    // 실과 글자 겹침 0: 구멍 테 오른쪽 끝(가운데 + 2)이 구멍 칸의 글(띠 왼쪽 + 13 — 왕조는 막대)보다 왼쪽.
    final names = {for (final l in painter.debugLabels.where((l) => l.kind == 'cell' && l.at.dy > p.bottom)) l.text: l.at.dx};
    expect(names['왕국'], 340 + ChainLook.holeText, reason: '지위 사슬의 구멍 칸 — 글이 띠 왼쪽 + 13');
    expect(names['온씨 왕조'], 340 + ChainLook.holeText + ChainLook.barAdvance, reason: '왕조 사슬의 구멍 칸 — 막대 뒤 7');
    expect(col + .5 + ChainLook.holeR + .5, lessThan(names['왕국']!));
  });

  test('왕조 막대 · 지위 눈금 · 글 — 막대 3 × 8(그 칸 색의 테 빛깔 · 둥근 1) · 눈금은 이름 끝 + 5에서 폭 2 · 4마다 서열 수만큼 · 글 8.5 굵게 먹 85', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final p = placeOf(scene);
    // 막대: 구멍 칸이라 띠 왼쪽 + 13(= 353)에서 3 × 8 · 사슬 위 + 3.
    final bar = mixOklab(0xff000000 | peach, Look.ink, .84) & 0xffffff;
    expect(noted(painter, '사슬막대').first, startsWith('1 3530,${((p.dyn + 3) * 10).round()} '));
    for (int x = 353; x < 356; x++) {
      for (int y = 4; y < 10; y++) {
        final got = rgbAt(px, x, p.dyn + y);
        for (final shift in [16, 8, 0]) {
          expect((got >> shift) & 0xff, closeTo((bar >> shift) & 0xff, 1), reason: '막대 ($x, +$y)');
        }
      }
    }
    expect(grayAt(px, 353, p.dyn + 3), greaterThan(grayAt(px, 354, p.dyn + 3) - 1), reason: '둥근 1 — 귀는 사분원 몫만');
    expect(rgbAt(px, 352, p.dyn + 6), paper);
    expect(rgbAt(px, 356, p.dyn + 6), paper);
    // 두 번째 왕조 칸(구멍 없음): 칸 왼쪽(940) + 5에 막대 · 그 색(라벤더).
    final bar2 = mixOklab(0xff000000 | lav, Look.ink, .84) & 0xffffff;
    expect(noted(painter, '사슬막대')[1], startsWith('1 9450,'));
    expect((rgbAt(px, 946, p.dyn + 6) >> 16) & 0xff, closeTo((bar2 >> 16) & 0xff, 1));
    // 글: 8.5 굵게 먹 85 · 사슬 세로 가운데.
    final label = painter.debugLabels.firstWhere((l) => l.kind == 'cell' && l.text == '서씨 왕조');
    expect(label.at.dx, 945 + ChainLook.barAdvance);
    expect(label.at.dy, closeTo(p.dyn + (G.chain - 8.5 * 1.2) / 2, 1e-6));
    // 눈금: '제국'(서열 2)만 둘 · '왕국'(서열 0)은 없음.
    final ticks = noted(painter, '사슬눈금');
    expect(ticks.length, 1);
    final rx = int.parse(ticks.single.split(' ')[1]) / 10;
    expect(ticks.single.split(' ').last, '2');
    final w = painter.text.widthOf('제국', ChainLook.textLook)!;
    expect(rx, closeTo(1245 + w + ChainLook.tickGap, 1e-6), reason: '이름 끝 + 5(구멍 없는 칸 — 칸 왼쪽 1240 + 5)');
    // 이 견본에서 눈금 첫 열(x0)은 세로 눈금(해 눈금의 점선 — 판 위에 그림)과 겹친다 — 그 열은 '먹 45보다 옅지 않음'만 보고, 나머지 열로 꼴을 잰다.
    final x0 = rx.roundToDouble();
    expect(grayAt(px, x0, p.rank + 5), lessThanOrEqualTo(0x8c), reason: '눈금 +0');
    for (final (dx, want) in [(1, edge), (2, paper), (3, paper), (4, edge), (5, edge), (6, paper), (8, paper)]) {
      expect(rgbAt(px, x0 + dx, p.rank + 6), want, reason: '눈금 +$dx');
    }
    expect(rgbAt(px, x0 + 1, p.rank + 3), paper, reason: '눈금 위(사슬 위 + 4부터)');
    expect(rgbAt(px, x0 + 1, p.rank + 4), edge);
    expect(rgbAt(px, x0 + 1, p.rank + 9), edge);
    expect(rgbAt(px, x0 + 1, p.rank + 10), paper, reason: '눈금 아래(높이 6)');
  });

  test('드는 만큼 줄임 — 좁은 칸은 첫 글자만 · 그보다 좁으면 글 없이 막대만(눈금은 다 들 때만)', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    // 좁은 띠(1505 ~ 1580): 칸 1552 ~ 1580(꼬리표 시작에서 비롯하지 않음 — 구멍 없음) — 왼쪽 + 5에 막대 · + 7에 이름 · 오른쪽 − 4까지: 28 − 5 − 7 − 4 = 12 → 첫 글자 하나.
    final narrow = painter.debugLabels.where((l) => l.kind == 'cell' && l.at.dx > 1790).map((l) => l.text).toList();
    expect(narrow, ['아'], reason: '온 이름(아주긴좁은왕조) · 짧은 이름(아주긴좁은)이 안 들면 첫 글자');
    expect(noted(painter, '사슬막대').where((n) => n.startsWith('2 ')), isNotEmpty, reason: '막대는 든다');
  });

  test('누름 — 사슬 칸을 누르면 그 칸(칸 창 · dynasty:n · rank:n), 사슬 사이 틈은 칸이 아니다', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final p = placeOf(scene);
    final dyn = painter.strips.hitStrips(600, p.dyn + 7)!;
    expect([dyn.kind, dyn.ref, dyn.band, dyn.row], [0, 'dynasty:0', 1, 0]);
    expect(dyn.rect.top, p.dyn);
    expect(dyn.rect.bottom, p.dyn + G.chain);
    final dyn2 = painter.strips.hitStrips(1000, p.dyn + 1)!;
    expect([dyn2.kind, dyn2.ref], [0, 'dynasty:1']);
    final rank = painter.strips.hitStrips(1300, p.rank + 12)!;
    expect([rank.kind, rank.ref], [5, 'rank:1']);
    expect(painter.strips.hitStrips(600, p.dyn + G.chain + 1), isNull, reason: '사슬 사이 틈');
    expect(painter.strips.hitStrips(600, p.bottom + 1), isNull, reason: '꼬리표 밑 틈');
    expect(painter.strips.hitStrips(1745, p.dyn + 7), isNull, reason: '사슬 오른쪽 끝 밖');
  });

  test('왼쪽 칸 — 사슬마다 칸 오른쪽 끝 − 12에 왕조 · 지위(10 · 틀 먹 50 · 오른쪽 맞춤 · 사슬 가운데) + 6px 금(틀 먹 20)', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final p = placeOf(scene);
    final labels = [
      for (final l in painter.debugLabels)
        if (l.kind == 'chainLabel') l,
    ];
    expect([for (final l in labels) l.text], ['왕조', '지위']);
    const look = TextLook(ChainLook.labelSize, ui.FontWeight.w400, 0xff000000);
    for (final (l, y) in [(labels[0], p.dyn + 7), (labels[1], p.rank + 7)]) {
      final w = painter.text.widthOf(l.text, look)!;
      expect(l.at.dx + w, closeTo(GutLook.width - ChainLook.labelRight, 1e-6), reason: '${l.text} 오른쪽 맞춤');
      expect(l.at.dy, Gut.textTopAt(y - 10 * Gut.lineRatio / 2, 10 * Gut.lineRatio, 10), reason: '${l.text} 사슬 가운데');
      for (int x = 232; x < 238; x++) {
        expect(rgbAt(px, x, y), 0xcccccc, reason: '${l.text} 금 x $x');
      }
      expect(rgbAt(px, 231, y), paper);
      expect(rgbAt(px, 238, y), paper);
    }
    expect(painter.strips.chainMarks.length, 2, reason: '줄 하나 · 사슬 둘(좁은 띠의 왕조 사슬은 같은 줄 · 같은 사슬 — 왼쪽 것 하나)');
    // 사슬이 화면 밖이면 이름도 없다(그린 사슬만).
    scene.controller.showRange(at(1600), at(1600 + 1680));
    await settle(scene, painter);
    expect(painter.debugLabels.where((l) => l.kind == 'chainLabel'), isEmpty);
  });

  test('잘린 쪽 — 띠 시작이 화면 왼쪽 밖이면 구멍 · 실 · 점이 없고, 사슬 왼쪽은 화면 끝에서 테 없이 열린다', () async {
    final (scene, painter) = make(from: 400);
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final p = placeOf(scene);
    expect(noted(painter, '사슬구멍'), isEmpty);
    expect(noted(painter, '사슬실'), isEmpty);
    expect(rgbAt(px, 240, p.dyn + 7), paper, reason: '화면 왼쪽 끝 — 세로 테 없이 종이');
    expect(rgbAt(px, 240, p.dyn), edge, reason: '윗 테는 화면 끝까지(둥근 귀 없음)');
    final label = painter.debugLabels.firstWhere((l) => l.kind == 'cell' && l.text == '온씨 왕조');
    expect(label.at.dx, 240 + ChainLook.textPad + ChainLook.barAdvance, reason: '글은 화면 왼쪽 + 5(막대) + 7');
  });

  test('매단 속국 실은 사슬 종이 뒤 — 사슬 글자 자리에서 실이 보이지 않고 사슬 사이 틈에서만 보인다(글자 가림 0)', () async {
    // 매단 꼬리표의 구멍(왼쪽 + 6)이 '온씨 왕조' 글자 자리(x 360 ~)에 오게 — 꼬리표 왼쪽 그림 영역 130(x 370 · 실 x 376).
    final data = chainTile(
      more: [(t) => t.item(16, 501, 0, at(130), at(600), ref: 1, name: '갈대 공국', color: 0xb1a0c9, a: 0, b: 0, d: 9, text2: '속국:갈대')],
    );
    final (scene, painter) = make(data: data, hang: 1);
    await settle(scene, painter);
    expect(scene.applyViewState(scene.layout.viewState.withHangsOpen(0, true)), isTrue);
    await settle(scene, painter);
    final geo = scene.layout.geo(0);
    expect(geo.hangOpen, isTrue);
    expect(geo.zoneTop, geo.chainTop + geo.chainDepth, reason: '매단 줄은 사슬 단 밑');
    final px = await pixelsOf(painter);
    final p = placeOf(scene);
    final x = (370 + HangLook.tagHoleX).floorToDouble();
    final label = painter.debugLabels.firstWhere((l) => l.kind == 'cell' && l.text == '온씨 왕조');
    final w = painter.text.widthOf('온씨 왕조', ChainLook.textLook)!;
    expect(x, inInclusiveRange(label.at.dx, label.at.dx + w), reason: '실이 사슬 글자 자리를 지난다');
    // 사슬 종이 안(글자 위 · 아래 1px 줄)에서는 종이빛, 사슬 사이 틈에서는 실(먹 45).
    expect(rgbAt(px, x, p.dyn + 1), paper, reason: '왕조 사슬 안 — 실이 종이 뒤');
    expect(rgbAt(px, x, p.rank + 1), paper, reason: '지위 사슬 안');
    expect(rgbAt(px, x, p.dyn + G.chain + 1), edge, reason: '사슬 사이 틈의 매단 실');
  });

  test('타일 경계 — 경계에서 끝나는 칸과 다음 타일에서 시작하는 칸도 한 종이(세로 금) · 경계에 걸쳐 잘린 칸은 이음매 없이', () async {
    // 단계 9의 타일 하나 = 통 256개 = 8192px(이 배율) — 타일 0 끝(8192)이 화면 x 840에 오게 본다.
    final tile0 =
        (TileBuilder(level: 9, x: 0, chunk: 0)
              ..band(1, 0, at(7700), at(8192), '하연 왕국', look: both, flags: Tile.clipRight)
              ..cell(20, 0, at(7700), at(8192), '온씨 왕조', kind: 0, style: st(seq: 0), color: peach)
              ..cell(30, 0, at(7700), at(8192), '왕국', kind: 5, style: st(seq: 0, rank: 0), flags: Tile.clipRight))
            .build();
    final tile1 =
        (TileBuilder(level: 9, x: 1, chunk: 0)
              ..band(1, 0, at(0), at(500), '하연 왕국', look: both, flags: Tile.clipLeft)
              ..cell(21, 0, at(0), at(500), '서씨 왕조', kind: 0, style: st(seq: 1), color: lav)
              ..cell(30, 0, at(0), at(400), '왕국', kind: 5, style: st(seq: 0, rank: 0), flags: Tile.clipLeft)
              ..cell(31, 0, at(400), at(500), '제국', kind: 5, style: st(seq: 1, rank: 2)))
            .build();
    final layout = layoutOf();
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(1920, 1080)
      ..setExtent(-at(100000), at(100000))
      ..setContentHeight(layout.totalHeight + 200);
    controller.showRange(at(8192 - 600), at(8192 - 600 + 1920 - SceneView.gutter));
    final scene = TimelineScene(
      controller: controller,
      layout: layout,
      fetchTile: (level, x, chunk, packs) async => level == 9 && chunk == 0 && x == 0 ? tile0 : (level == 9 && chunk == 0 && x == 1 ? tile1 : TileBuilder(level: level, x: x, chunk: chunk).build()),
    );
    final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final p = placeOf(scene);
    expect(controller.view.xOf(at(8192)), closeTo(840, 1e-6));
    final chains = noted(painter, '사슬');
    expect(chains.firstWhere((n) => n.startsWith('0:0:1 3480,')), contains('jl=false jr=true 귀=3/0'), reason: '타일 0의 왕조 칸 — 다음 타일의 칸과 맞닿음');
    expect(chains.firstWhere((n) => n.startsWith('0:0:1 8400,')), contains('jl=true jr=false 귀=0/3'), reason: '타일 1의 왕조 칸 — 앞 타일의 칸과 맞닿음');
    expect(rgbAt(px, 840, p.dyn + 7), 0xbfbfbf, reason: '타일 경계의 칸 사이 세로 금');
    expect(rgbAt(px, 839, p.dyn + 7), paper);
    for (final x in [838, 839, 840, 841]) {
      expect(rgbAt(px, x, p.dyn), edge, reason: '윗 테가 경계에서 끊기지 않음(둥근 귀 없음) x $x');
    }
    // 경계에 걸친 지위 칸(타일마다 잘린 조각): 이음매에 세로 금도 테도 없다.
    for (final x in [839, 840]) {
      expect(rgbAt(px, x, p.rank + 7), paper, reason: '잘린 조각의 이음매 x $x');
      expect(rgbAt(px, x, p.rank), edge);
    }
    expect(painter.debugLabels.where((l) => l.kind == 'cell' && l.text == '왕국').length, 1, reason: '잘린 칸의 이름은 한 번');
  });

  test('스위치 chain을 끄면(--paint-off=chain) 사슬 그림이 하나도 없다 — 종이 · 구멍 · 실 · 막대 · 눈금 · 왼쪽 칸 이름', () async {
    PaintPick.chain = false;
    final (scene, painter) = make();
    await settle(scene, painter);
    for (final kind in ['사슬', '사슬구멍', '사슬실', '사슬막대', '사슬눈금', '사슬이름']) {
      expect(noted(painter, kind), isEmpty, reason: kind);
    }
    expect(painter.strips.chainMarks, isEmpty);
    expect(painter.debugLabels.where((l) => l.kind == 'chainLabel'), isEmpty);
    expect(scene.layout.geo(0).chainTop, -1);
  });

  // 검토 지적(2026-10-25 · 차례 걸음 10 ~ 16의 검토): 띠 뒤 판의 선(소속선 · 승계선의 내림줄 · 오름줄)이 꼬리표 밑 흰 사슬을 모르고 셈해
  // 사슬 종이 뒤로 끊기거나 매단 이름표 줄 위에서 시작하고, 보이지 않는 선이 사슬 누름을 가로챘다. 사슬은 띠 밑에 덧붙은 단으로 센다.
  group('선과 사슬 — 띠 뒤 선은 사슬 단을 띠 밑 단으로 센다(검토 2026-10-25)', () {
    /// 두 줄: 줄 0 = 왕조 · 지위 · 지도자(+ 매단 속국 줄 [hang]) · 줄 1 = 지도자만(사슬 없음).
    SceneLayout twoRows({int hang = 0}) => SceneLayout.fromJson({
      'packs': [
        {'id': 1, 'name': '사슬 견본', 'events': 0},
      ],
      'tracks': [
        {
          'id': 1,
          'pack': 1,
          'ord': 0,
          'name': '하연 갈래',
          'color': 0xa0bcc5,
          'key': 'chain-a',
          'dynasty': 1,
          'leader': 1,
          'cabinet': 0,
          'organ': 0,
          'rail_levels': 2,
          'rows': [
            row(0, hang: hang),
            {...row(1), 'dynasty': 0, 'rank': 0},
          ],
        },
      ],
      'epochs': <dynamic>[],
      'categories': <dynamic>[],
      'axis': <dynamic>[],
    })..reduceMotion = true;

    (TimelineScene, TimelinePainter) make2(Uint8List data, {int hang = 0}) {
      final layout = twoRows(hang: hang);
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 1080)
        ..setExtent(-at(100000), at(100000))
        ..setContentHeight(layout.totalHeight + 200);
      controller.showRange(0, at(1920 - SceneView.gutter));
      final scene = TimelineScene(
        controller: controller,
        layout: layout,
        fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? data : TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
    }

    const leaderOnly = 1 << 20 | 1 << 26, reed = 0xb1a0c9;

    /// 줄 0의 하연 왕국(그림 영역 100 ~ 1500 — 왕조 · 지위 · 지도자 칸)과 줄 1의 갈대 공국(600 ~ 1200 — 지도자 칸).
    TileBuilder hosts() => TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(1, 0, at(100), at(1500), '하연 왕국', look: both)
      ..cell(20, 0, at(100), at(1500), '온씨 왕조', kind: 0, style: st(seq: 0), color: peach)
      ..cell(30, 0, at(100), at(1500), '왕국', kind: 5, style: st(seq: 0, rank: 0))
      ..cell(10, 0, at(100), at(1500), '온 하람', kind: 1, style: st(seq: 0))
      ..band(3, 1, at(600), at(1200), '갈대 공국', look: leaderOnly, color: reed)
      ..cell(50, 1, at(600), at(1200), '갈대 공', kind: 1, style: st(seq: 0));

    /// 관계선 층 기록(0.1px까지 적은 소수 — '352.0,123.5 …')의 수만. 글(가는 · 짙기)은 버린다.
    List<double> nums(String text) => [for (final s in text.split(RegExp('[ ,]'))) double.tryParse(s) ?? double.nan].where((v) => !v.isNaN).toList();

    /// 기록 '소속선'의 (x, 위 끝, 아래 끝).
    List<double> partOf(TimelinePainter painter) => nums(noted(painter, '소속선').single);

    test('소속선(아래로)은 상국의 사슬 단 · 매단 속국 줄 밑에서 내려온다 — 띠 아랫변 + 사슬 깊이 + 1 + 매단 깊이(스위치 chain을 끄면 예전 식)', () async {
      for (final chain in [true, false]) {
        PaintPick.chain = chain;
        final data = (hosts()
              // 매단 속국 이름표(줄 0 · 단 0)와 소속선(상국 1 → 속국 3 · 아래로 · 매단 줄 1).
              ..item(HangLayer.sectionHang, 501, 0, at(600), at(1200), ref: 1, name: '갈대 공국', color: reed, a: 0, b: 0, d: 3, text2: '속국:갈대')
              ..item(LinkLayer.secPart, 601, 0, at(600), at(1200), row2: 1, ref: 3, b: 1, a: 1, c: 1, color: reed))
            .build();
        final (scene, painter) = make2(data, hang: 1);
        addTearDown(scene.dispose);
        await settle(scene, painter);
        expect(scene.applyViewState(scene.layout.viewState.withHangsOpen(0, true)), isTrue);
        await settle(scene, painter);
        final layout = scene.layout, v = scene.controller.view, geo = layout.geo(0);
        expect(geo.hangOpen, isTrue);
        expect(geo.chainDepth, chain ? 2 * G.chainPitch : 0, reason: '사슬 $chain');
        final bandBottom = geo.bandTop + geo.bandHeight;
        final part = partOf(painter);
        expect(part[0], closeTo(v.xOf(at(600)) + 12, .05), reason: '띠 안쪽 12px');
        // 기록은 0.1px로 반올림한 값.
        expect(part[1], closeTo(v.yOf(layout.rowTop(0) + bandBottom + geo.chainDepth) + 1 + geo.hangDepth, .051), reason: '사슬 $chain — 위 끝');
        expect(part[1], closeTo(v.yOf(layout.rowTop(0) + geo.zoneTop) + 1 + geo.hangDepth, .051), reason: '매단 줄 자리(zoneTop)와 같은 셈');
        expect(part[2], closeTo(v.yOf(layout.rowTop(1) + layout.geo(1).bandTop) - 2.5, .051), reason: '속국 띠 윗변 − 2.5');
      }
    });

    test('소속선(위로)은 속국의 사슬 단 밑에서 멎는다 — 끝의 점이 사슬 종이에 가리지 않게', () async {
      // 속국(줄 0의 하연 왕국)이 상국(줄 1의 갈대 공국)보다 위 — 선은 상국 윗변 − 1에서 속국 띠 아랫변 + 사슬 깊이 + 2.5까지 오른다.
      // 맞닿은 두 줄은 사이가 2px 아래라 선을 긋지 않는다(사슬이 없을 때와 같다) — 줄 0의 매단 속국 줄(하나)을 펴 두 줄 사이를 벌린다.
      final data = (hosts()..item(LinkLayer.secPart, 602, 0, at(100), at(1500), row2: 1, ref: 1, b: 3, a: 0, color: peach)).build();
      final (scene, painter) = make2(data, hang: 1);
      addTearDown(scene.dispose);
      await settle(scene, painter);
      expect(scene.applyViewState(scene.layout.viewState.withHangsOpen(0, true)), isTrue);
      await settle(scene, painter);
      final layout = scene.layout, v = scene.controller.view, geo = layout.geo(0);
      final part = partOf(painter);
      expect(part[1], closeTo(v.yOf(layout.rowTop(0) + geo.bandTop + geo.bandHeight + geo.chainDepth) + 2.5, .051), reason: '속국 사슬 밑 + 2.5');
      expect(part[2], closeTo(v.yOf(layout.rowTop(1) + layout.geo(1).bandTop) - 1, .051), reason: '상국 띠 윗변 − 1');
      final p = placeOf(scene);
      expect(part[1], greaterThan(p.rank + G.chain + 2), reason: '점(반지름 2)이 지위 사슬 아랫변 밑');
    });

    /// 합류(흡수): 줄 0의 앞 나라(100 ~ 700)가 끝나며 줄 1에 이미 있던 뒤 나라(400 ~ 1300)로 부분 승계 — links_test '합류'와 같은 꼴.
    /// 앞 나라의 왕조 칸은 [dynTo]까지(사슬 자리).
    Uint8List absorbTile(double dynTo) => (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, at(100), at(700), '앞 나라', look: 1 << 20 | 1 << 21 | 1 << 26)
          ..cell(20, 0, at(100), at(dynTo), '온씨 왕조', kind: 0, style: st(seq: 0), color: peach)
          ..cell(10, 0, at(100), at(700), '온 하람', kind: 1, style: st(seq: 0))
          ..band(2, 1, at(400), at(1300), '뒤 나라', look: leaderOnly, color: reed)
          ..cell(50, 1, at(400), at(1300), '뒤 임금', kind: 1, style: st(seq: 0))
          ..item(LinkLayer.secSquare, 101, 0, at(100), at(700), ref: 1, name: '앞 나라', color: 0xabb3c9)
          ..item(LinkLayer.secSquare, 102, 1, at(400), at(1300), ref: 2, name: '뒤 나라', color: reed)
          ..item(LinkLayer.secLink, 201, 0, at(400), at(700), row2: 1, ref: 1, b: 2, color: 0xabb3c9, a: 3 | (3 << 2) | 1 << 4 | 1 << 7))
        .build();

    /// 기록 '선'의 점들(x, y …)과 멸망 네모의 x.
    (List<double>, double) lineOf(TimelinePainter painter) {
      final pts = nums(noted(painter, '선').single.split(' 짙기').first);
      final ec = nums(noted(painter, '네모').firstWhere((s) => s.startsWith('멸망 1')).split(' ')[2])[0];
      return (pts, ec);
    }

    test('내림줄은 사슬 칸을 지나지 않는다 — 앞 나라의 왕조 사슬이 멸망 네모 밑까지 있으면 띠 밖 세로 통로로 돌고, 그 사슬을 누르면 칸이 잡힌다', () async {
      // ① 왕조 칸이 일찍 끝남(400) — 멸망 네모 ± 10px이 비어 내림줄로 곧게 합류(사슬이 있어도 그 자리에 없으면 막지 않는다).
      final (early, earlyPainter) = make2(absorbTile(400));
      addTearDown(early.dispose);
      await settle(early, earlyPainter);
      final (pts1, ec1) = lineOf(earlyPainter);
      expect(pts1.length, 4, reason: '곧은 세로 한 획(두 점): $pts1');
      expect(pts1[0], closeTo(ec1, .05));
      expect(noted(earlyPainter, '합류'), hasLength(1));
      // ② 왕조 칸이 띠 끝(700)까지 — 사슬이 멸망 네모 밑에 있으므로 내림줄을 긋지 않는다(가로 → 세로 통로의 세 점).
      final (full, painter) = make2(absorbTile(700));
      addTearDown(full.dispose);
      await settle(full, painter);
      final (pts2, ec2) = lineOf(painter);
      expect(pts2.length, 6, reason: '가로 → 세로의 세 점: $pts2');
      expect(pts2[0], closeTo(ec2, .05), reason: '마름모 가운데에서 나온다');
      expect(pts2[1], closeTo(pts2[3], .05), reason: '첫 획은 가로');
      expect(pts2[2], greaterThan(ec2 + 7), reason: '세로 통로는 앞 나라 띠 끝 밖 — 사슬(띠 끝까지) 밖');
      // 멸망 네모 밑의 사슬을 누르면 왕조 칸(관계선이 가로채지 않는다).
      final y = placeOf(full).dyn + 7;
      expect(painter.links.hitLinks(ec2, y), isNull);
      final hit = painter.strips.hitStrips(ec2, y)!;
      expect([hit.kind, hit.ref, hit.band], [0, 'dynasty:0', 1]);
      // ③ 스위치 chain을 끄면 왕조는 띠 안 칸 층이라 예전처럼 내림줄로 합류한다(띠 밑 단이 아님).
      PaintPick.chain = false;
      final (off, offPainter) = make2(absorbTile(700));
      addTearDown(off.dispose);
      await settle(off, offPainter);
      final (pts3, ec3) = lineOf(offPainter);
      expect(pts3.length, 4, reason: '끈 길은 예전 그대로 — 곧은 세로 한 획: $pts3');
      expect(pts3[0], closeTo(ec3, .05));
    });

    test('띠 뒤로 지나는 선은 사슬 종이 위에서 맞히지 않는다 — 세로 통로가 같은 줄 다른 띠의 사슬 뒤를 지나면 그 자리는 사슬 칸', () async {
      // 줄 0: 앞 나라(100 ~ 500 · 칸 없음) 뒤에 바로 하연 왕국(500 ~ 1500 · 왕조 사슬). 줄 1의 뒤 나라(800 ~ 1300)로 직접 승계 —
      // 세로 통로(앞 나라 끝 + 9)가 하연 왕국의 꼬리표와 왕조 사슬 뒤를 지난다.
      final data = (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, at(100), at(500), '앞 나라', color: 0xabb3c9)
            ..band(4, 0, at(500), at(1500), '하연 왕국', look: 1 << 20 | 1 << 21 | 1 << 26)
            ..cell(20, 0, at(500), at(1500), '온씨 왕조', kind: 0, style: st(seq: 0), color: peach)
            ..cell(10, 0, at(500), at(1500), '온 하람', kind: 1, style: st(seq: 0))
            ..band(2, 1, at(800), at(1300), '뒤 나라', look: leaderOnly, color: reed)
            ..cell(50, 1, at(800), at(1300), '뒤 임금', kind: 1, style: st(seq: 0))
            ..item(LinkLayer.secSquare, 101, 0, at(100), at(500), ref: 1, name: '앞 나라', color: 0xabb3c9)
            ..item(LinkLayer.secSquare, 102, 1, at(800), at(1300), ref: 2, name: '뒤 나라', color: reed)
            ..item(LinkLayer.secLink, 201, 0, at(500), at(800), row2: 1, ref: 1, b: 2, color: 0xabb3c9, a: 1 << 4 | 1 << 5))
          .build();
      final (scene, painter) = make2(data);
      addTearDown(scene.dispose);
      await settle(scene, painter);
      final pts = nums(noted(painter, '선').single.split(' 짙기').first);
      expect(pts.length, 8, reason: '가로 → 세로 → 가로: $pts');
      final xm = pts[2], p = placeOf(scene);
      expect(xm, greaterThan(scene.controller.view.xOf(at(500))), reason: '세로 통로는 하연 왕국 안 x');
      expect(pts[3], lessThan(p.dyn), reason: '세로 통로가 왕조 사슬 위에서 시작');
      expect(pts[5], greaterThan(p.dyn + G.chain), reason: '그리고 사슬 밑까지');
      // 사슬 종이 위: 선이 아니라 왕조 칸 · 사슬 사이 틈(사슬 밑 바탕)과 꼬리표 위는 예전처럼 선.
      expect(painter.strips.chainAt(xm, p.dyn + 7), isTrue);
      expect(painter.links.hitLinks(xm, p.dyn + 7), isNull);
      expect(painter.strips.hitStrips(xm, p.dyn + 7)?.kind, 0);
      expect(painter.links.hitLinks(xm, p.dyn + G.chain + 1)?.kind, LinkHitKind.link, reason: '사슬 밑 바탕에서는 선');
      expect(painter.links.hitLinks(xm, p.bandTop + 20)?.kind, LinkHitKind.link, reason: '꼬리표 안(사슬이 아님)은 그대로');
      // 스위치 chain을 끄면 사슬이 없어 그 자리(띠 밑 바탕)도 선이다 — 예전 그대로.
      PaintPick.chain = false;
      final (off, offPainter) = make2(data);
      addTearDown(off.dispose);
      await settle(off, offPainter);
      expect(offPainter.strips.chainAt(xm, p.dyn + 7), isFalse);
    });
  });
}

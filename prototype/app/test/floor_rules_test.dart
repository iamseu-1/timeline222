import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show BandKind;
import 'package:archive_prototype/scene/paint/context.dart';
import 'package:archive_prototype/scene/paint/floor_rules.dart';
import 'package:archive_prototype/scene/paint/ink.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/patterns.dart';
import 'package:archive_prototype/scene/paint/strips.dart' show CellStyle, StripLayer;
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/schema4_items.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:archive_prototype/scene/tile.dart' show Tile;
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 칸 층 사이 흐린 가로선(감독 지적 2026-10-25 "등불왕국 명목기 부분에 가로선도 흐릿하게라도 보이면 좋겠는데 지금은 너무 세로 구분선만 보여서" —
// scene/paint/floor_rules.dart · 칸 층 paint/strips.dart). 감독이 고를 꼴 셋(스위치 `--paint-rows=a|b|c|off`)을 장면 하나로 그려 본다:
//   · 자리 — 층의 윗선 줄(첫 층은 이름 색줄 아랫변의 금 줄) · 층 아랫줄(다음 층의 윗선 · 마지막 층이면 흰 사건 칸의 윗줄) · 칸이 놓인 가로 폭만
//   · 없음 — 빈 층(칸이 없는 자리) · 꼬리표 밑 흰 사슬 단 · 꼬리표 밖 · 조감(모양 c 포함) · 빌린 칸의 윗변 · 꼴 off
//   · 짙기 — a · b 먹 12 실선(b는 세로 칸 구분선도 12) · c 먹 25 점선 1 · 2 / 띠 칠 위에 얹힘 · 같은 줄의 두 칸(위 층 아랫선 · 아래 층 윗선)은 한 번만
// 감독 결정(2026-10-25 "b로 하고, 왕 세로선부분이랑 가로선 부분이랑 딱 맞닿게 해줘 틈 없게" · "모든 가로세로 구분선은 맞닿게"): 기본 꼴 b ·
//   · 맞닿음 — 세로 칸 구분선은 위 가로 금(첫 층은 색줄 아랫금) 바로 아랫줄부터 아래 가로 금 바로 윗줄까지(빌린 칸은 제 윗변 파선 아래부터) ·
//     만나는 점은 먹 한 번 · 가로선 끝은 그 칸의 구분선 열까지(1px 꼬리 없음) · 띠 테에 닿는 끝은 테 바로 옆 열부터(소수 자리에서도) ·
//     띠 층의 층 사이 금 · 직각 테 귀 · 사슬 종이 테도 정수 열(흐린 띠의 귀에 먹 두 번 없음) · 꼴 off는 이 갈래 전 그림 그대로
//   · 검토 고침 — 점선 띠 테 × 가로 금의 T자(무늬가 빈 줄은 테 빛깔 한 점) · 세로 소수 자리의 직각 귀 · 타일 이음매에 딱 놓인 칸 경계 ·
//     집권 단 2px 밑줄의 정수 끝

final ppm = 32 / bucketMinutes(9);
double at(double px) => px / ppm;

/// style에 함께 실리는 값(계약 6-2): 비트 15~26 순번 + 1.
int st(int style, {int seq = -1}) => style | ((seq < 0 ? 0 : seq + 1) << 15);

/// 줄 값이 실린 두 장 꼬리표 줄 하나 — 시기 1단 · 지도자 · 내각 층(줄 값 비트 17 · 18 · 19) + 왕조(비트 16 — 꼬리표 밑 흰 사슬).
/// [power]면 집권 단(비트 7 — 시기 층 아래 · 지도자 층 위)도.
SceneLayout shape({bool power = false}) => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xa0bcc5, 'rail_levels': 2,
      'rows': [
        {
          'id': 0, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': 4, 'lead_top': 23, 'cab_top': 46, 'text_top': 66, 'text_lines': 2,
          'rail_top': 108, 'organ_top': -1, 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 1, 'rank': 0, 'cats': <int>[], 'fig': 0, 'dep': 0,
          'zones': 0, 'hem': 0, 'fig_wide': (1 << 3) | (1 << 16) | (1 << 17) | (1 << 18) | (1 << 19) | (power ? 1 << 7 : 0),
        },
      ],
    },
  ],
});

/// 띠 look: 비트 20 칸이 있다 · 21 + k 그 띠의 칸 층(0 왕조 · 1 시기 · 5 지도자 · 6 내각).
const bandLook = 1 << 20 | 1 << 21 | 1 << (21 + 1) | 1 << (21 + 5) | 1 << (21 + 6);

/// 띠 하나 · 시기 한 칸(긴 칸) · 지도자 두 칸(잇지 않음 — 0.5px 틈) · 내각 한 칸(앞쪽만 — 뒤는 빈 층) · 왕조 한 칸(꼬리표 밑 사슬).
/// [borrowedLeaders]면 지도자 칸이 빌린 직위 줄의 칸(27비트 — 칸 전체 .72 · 윗변 파선). [fromStart]면 내각 · 왕조 칸이 띠 시작부터(띠 테에 닿는 칸).
/// [bandKind]는 띠 종류(look 아래 5비트 — 조직체면 점선 테).
Uint8List cells({bool borrowedLeaders = false, bool fromStart = false, bool twoDynasties = false, int bandKind = 0}) {
  final b = borrowedLeaders ? Schema4.borrowed : 0, from = at(fromStart ? 100 : 150);
  final builder = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, at(100), at(1600), '첫불 성채국', look: bandLook | bandKind)
    ..cell(20, 0, at(150), at(1400), '장부 학파\t복구기', kind: 4, lane: 0, style: st(32, seq: 0))
    ..cell(10, 0, at(150), at(700), '은결 나나나', kind: 1, style: st(0, seq: 0) | b)
    ..cell(11, 0, at(700), at(1400), '둘째 지도자', kind: 1, style: st(0, seq: 1) | b)
    ..cell(30, 0, from, at(500), '서목 윤 대재상', kind: 2, style: st(0, seq: 0));
  if (twoDynasties) {
    // 맞닿은 왕조 칸 둘 — 한 사슬 종이에 칸 사이 세로 금 하나(chains_paint_test와 같은 꼴).
    builder
      ..cell(40, 0, from, at(700), '은결 왕조', kind: 0, style: st(0, seq: 0))
      ..cell(41, 0, at(700), at(1400), '해결 왕조', kind: 0, style: st(0, seq: 1));
  } else {
    builder.cell(40, 0, from, at(1400), '은결 왕조', kind: 0, style: st(0, seq: 0));
  }
  return builder.build();
}

/// [shift]는 보기의 왼쪽을 그만큼(px) 오른쪽으로 — 띠 · 칸이 픽셀 사이(소수 px)에 놓인다. [more]는 단계 9 · 묶음 0의 다른 타일(가로 번호 → 자료 —
/// 타일 이음매 견본) · [layout]은 줄 생김새(없으면 [shape]).
(TimelineScene, TimelinePainter) make(Uint8List data, {double shift = 0, Map<int, Uint8List> more = const {}, SceneLayout? layout}) {
  final controller = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..setContentHeight(600)
    ..reduceMotion = true;
  controller.showRange(at(shift), at(shift + 1920 - SceneView.gutter));
  final scene = TimelineScene(
    controller: controller,
    layout: layout ?? shape(),
    fetchTile: (level, x, chunk, packs) async =>
        level == 9 && x == 0 && chunk == 0 ? data : (level == 9 && chunk == 0 ? more[x] : null) ?? (TileBuilder(level: level, x: x, chunk: chunk)).build(),
  );
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

Future<void> loadAll(TimelineScene scene) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
}

/// 장면을 [rule] 꼴로 그려 (그리개 · RGBA 바이트 1920×1080)를 돌려준다. [bird]면 조감 모양 c. [dim]이면 다른 띠를 고른 동안(이 띠는 .58로 흐림).
/// [dy]면 몸통의 세로 자리(view.top)를 그만큼 — 관성 스크롤 뒤처럼 띠 · 칸이 줄 사이(소수 px)에 놓인다. [data]를 주면 [cells] 대신 그 타일.
Future<(TimelinePainter, Uint8List)> drawn(FloorRule rule,
    {bool borrowedLeaders = false, bool bird = false, bool fromStart = false, double shift = 0, bool dim = false, bool twoDynasties = false,
    int bandKind = 0, double dy = 0, Uint8List? data, Map<int, Uint8List> more = const {}, SceneLayout? layout}) async {
  PaintPick.rows = rule;
  final (scene, painter) = make(data ?? cells(borrowedLeaders: borrowedLeaders, fromStart: fromStart, twoDynasties: twoDynasties, bandKind: bandKind),
      shift: shift, more: more, layout: layout);
  if (bird) {
    scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2, birdShape: BirdShape.c));
    scene.controller.setContentHeight(scene.layout.totalHeight);
  }
  if (dim) {
    em.Emphasis.of(scene)
      ..reduceMotion = true
      ..set(const em.Look(band: 99));
  }
  await loadAll(scene);
  if (dy != 0) scene.controller.view.top = dy;
  scene.prepare();
  ui.Picture? picture;
  for (int i = 0; i < 50; i++) {
    picture?.dispose();
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    picture = recorder.endRecording();
    if (!painter.text.starved) break;
  }
  expect(painter.text.starved, isFalse, reason: '글줄이 다 준비된 장면으로 잰다');
  final image = await picture!.toImage(1920, 1080);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return (painter, bytes!.buffer.asUint8List());
}

/// 그 픽셀(배율 1)의 0xRRGGBBAA.
int pixelAt(Uint8List px, double x, double y) {
  final i = (y.floor() * 1920 + x.floor()) * 4;
  return px[i] << 24 | px[i + 1] << 16 | px[i + 2] << 8 | px[i + 3];
}

/// [after]가 [before] 위에 먹을 [alpha]만큼 얹은 색인가(채널마다 ±2).
void expectInk(int after, int before, double alpha, {String? reason}) {
  for (final shift in const [24, 16, 8]) {
    final b = (before >> shift) & 0xff, c = (Look.ink >> (shift - 8)) & 0xff, a = (after >> shift) & 0xff;
    expect(a, closeTo(b + (c - b) * alpha, 2), reason: '${reason ?? ''} 채널 ${shift ~/ 8}: ${before.toRadixString(16)} → ${after.toRadixString(16)}');
  }
}

/// 기록 '층선': '띠 y×10 x0×10,x1×10 밝기×1000'.
class Rule {
  Rule(String text)
    : band = int.parse(text.split(' ')[0]),
      y = int.parse(text.split(' ')[1]) / 10,
      x0 = int.parse(text.split(' ')[2].split(',')[0]) / 10,
      x1 = int.parse(text.split(' ')[2].split(',')[1]) / 10,
      alpha = int.parse(text.split(' ')[3]) / 1000;
  final int band;
  final double y, x0, x1, alpha;
  @override
  String toString() => '$band y$y $x0~$x1 ($alpha)';
}

List<Rule> rulesOf(TimelinePainter painter) => [for (final v in painter.debugSink.notes['층선'] ?? const <Object>[]) Rule('$v')];

List<String> noted(TimelinePainter painter, String kind) => [for (final v in painter.debugSink.notes[kind] ?? const <Object>[]) '$v'];

/// 칸 기록 '종류:줄:단 l,t,w,h'(0.1px).
({int kind, double l, double t, double r}) cellOf(TimelinePainter painter, int kind, {int nth = 0}) {
  final all = [
    for (final v in painter.debugSink.notes['칸'] ?? const <Object>[])
      if (int.parse('$v'.split(' ')[0].split(':')[0]) == kind) '$v',
  ];
  final list = [
    for (final s in all)
      (
        kind: kind,
        l: int.parse(s.split(' ')[1].split(',')[0]) / 10,
        t: int.parse(s.split(' ')[1].split(',')[1]) / 10,
        r: (int.parse(s.split(' ')[1].split(',')[0]) + int.parse(s.split(' ')[1].split(',')[2])) / 10,
      ),
  ]..sort((a, b) => a.l.compareTo(b.l));
  return list[nth];
}

/// 칸 상자([l], [r])의 세로 칸 구분선 열 — 왼쪽 round(l) · 오른쪽 round(r − 1)(strips.dart `_floorDividers`).
double divL(double l) => l.roundToDouble();
double divR(double r) => (r - 1).roundToDouble();

/// 한 층에 그은 세로 칸 구분선의 열(그은 차례) — [_floorDividers]와 같은 건너뜀: 층의 두 끝([lo] · [hi]) 가까이 · 앞 금에서 2.5px 안.
List<({double x, bool left})> dividersOf(List<({int kind, double l, double t, double r})> cells, double lo, double hi) {
  final out = <({double x, bool left})>[];
  var last = double.negativeInfinity;
  for (final c in cells) {
    for (final (q, left) in [(divL(c.l), true), (divR(c.r), false)]) {
      if ((q - last).abs() < 2.5 || q < lo + 2 || q > hi - 3) continue;
      out.add((x: q, left: left));
      last = q;
    }
  }
  return out;
}

/// 이 견본의 세 층(시기 · 지도자 · 내각): 위 가로 금 줄(첫 층은 색줄 아랫금) · 아래 가로 금 줄(다음 층 윗선 · 흰 사건 칸 윗줄) · 그 층의 칸.
List<({double lineTop, double lineBottom, List<({int kind, double l, double t, double r})> cells})> floorsOf(TimelinePainter painter, double stripB) => [
  (lineTop: stripB - 1, lineBottom: stripB + G.floor, cells: [cellOf(painter, 4)]),
  (lineTop: stripB + G.floor, lineBottom: stripB + 2 * G.floor, cells: [cellOf(painter, 1), cellOf(painter, 1, nth: 1)]),
  (lineTop: stripB + 2 * G.floor, lineBottom: stripB + 3 * G.floor, cells: [cellOf(painter, 2)]),
];

/// 줄 0의 몸통 윗변(= 이름 색줄 아랫변 — 정수 px인 견본).
double stripBOf(TimelinePainter painter) {
  final scene = painter.scene, layout = scene.layout, geo = layout.geo(0), v = scene.controller.view;
  final stripB = v.yOf(layout.rowTop(0) + geo.bodyTop);
  expect(stripB, stripB.roundToDouble(), reason: '이 견본은 몸통 윗변이 정수 px — 줄 자리를 그대로 견준다');
  return stripB;
}

void main() {
  tearDown(PaintPick.reset);

  test('스위치: 기본 꼴 b(감독 결정 2026-10-25) · --paint-rows=a|c|off로 고름 · --paint-off=rows와 all은 끔(끔이 이김) · 모르는 값은 돌려줌', () {
    expect(PaintPick.rows, FloorRule.b);
    expect(PaintPick.applyArguments(['--paint-rows=a']), isEmpty);
    expect(PaintPick.rows, FloorRule.a);
    expect(PaintPick.applyArguments(['--paint-rows= C ']), isEmpty);
    expect(PaintPick.rows, FloorRule.c);
    expect(PaintPick.allOn, isTrue, reason: '꼴이 무엇이든 끄지 않았으면 켬');
    expect(PaintPick.applyArguments(['--paint-off=rows', '--paint-rows=a']), isEmpty);
    expect(PaintPick.rows, FloorRule.off, reason: '꼴 고르기를 먼저 읽고 끄기를 나중에 — 끔이 이긴다');
    expect(PaintPick.off, ['rows']);
    PaintPick.reset();
    expect(PaintPick.rows, FloorRule.b);
    expect(PaintPick.applyArguments(['--paint-off=all']), isEmpty);
    expect(PaintPick.rows, FloorRule.off);
    PaintPick.reset();
    expect(PaintPick.applyArguments(['--paint-rows=d', '--paint-rows=', '--paint-rowsx=a']), ['d']);
    expect(PaintPick.rows, FloorRule.b);
    expect(PaintPick.applyArguments(['--paint-rows=off']), isEmpty);
    expect(PaintPick.allOn, isFalse);
  });

  test('꼴 b(기본): 층 사이 · 색줄과 첫 층 사이 · 마지막 층과 사건 칸 사이에 먹 12 가로선 — 칸이 놓인 폭(끝은 그 칸의 구분선 열) · 같은 줄은 한 번 · 띠 칠 위', () async {
    final (off, pxOff) = await drawn(FloorRule.off);
    expect(rulesOf(off), isEmpty, reason: '꼴 off는 가로선을 하나도 긋지 않는다');
    PaintPick.reset();
    final (painter, px) = await drawn(PaintPick.rows);
    final scene = painter.scene, layout = scene.layout, geo = layout.geo(0), v = scene.controller.view;
    final base = layout.rowTop(0);
    final stripB = stripBOf(painter);
    expect(geo.floorTops, [geo.phaseTop, geo.leaderTop, geo.cabinetTop], reason: '몸통의 칸 층: 시기 · 지도자 · 내각(왕조는 꼬리표 밑 사슬)');
    expect(geo.phaseTop, geo.bodyTop);
    final phase = cellOf(painter, 4), lead0 = cellOf(painter, 1), lead1 = cellOf(painter, 1, nth: 1), cab = cellOf(painter, 2);
    final rules = rulesOf(painter);
    final ys = rules.map((r) => r.y).toSet().toList()..sort();
    expect(ys, [stripB - 1, stripB + G.floor, stripB + 2 * G.floor, stripB + 3 * G.floor],
        reason: '색줄 아랫변의 금 줄(첫 층 위) · 시기|지도자 · 지도자|내각 · 내각|사건 칸 — 띠 층의 층 사이 금과 같은 줄');
    expect(rules.every((r) => r.band == 1), isTrue);
    Rule only(double y) {
      final at = rules.where((r) => r.y == y).toList();
      expect(at.length, 1, reason: '줄 $y의 선은 하나로 합쳐진다(두 칸의 조각 · 0.5px 틈 메움): $at');
      return at.single;
    }

    // 끝은 그 칸이 그은 세로 칸 구분선의 열 — 왼쪽은 그 열부터 · 오른쪽은 그 열 다음까지(맞닿음 · 1px 꼬리 없음).
    final head = only(stripB - 1);
    expect([head.x0, head.x1], [divL(phase.l), divR(phase.r) + 1], reason: '첫 층(시기) 윗선 — 시기 칸의 두 구분선 사이');
    final mid1 = only(stripB + G.floor);
    expect([mid1.x0, mid1.x1], [divL(lead0.l), divR(lead1.r) + 1], reason: '시기 아랫선 ∪ 지도자 윗선 — 지도자 두 칸 사이(구분선 하나)도 이어진다');
    final mid2 = only(stripB + 2 * G.floor);
    expect([mid2.x0, mid2.x1], [divL(lead0.l), divR(lead1.r) + 1], reason: '지도자 아랫선 ∪ 내각 윗선');
    final last = only(stripB + 3 * G.floor);
    expect([last.x0, last.x1], [divL(cab.l), divR(cab.r) + 1], reason: '내각 아랫선 — 내각 칸이 놓인 자리만(뒤쪽 빈 층에는 없다)');
    expect(rules.map((r) => r.alpha), everyElement(1.0), reason: '고름 · 흐림이 없으면 칸 밝기 1');

    // 띠 안쪽 · 몸통 안에만(꼬리표 밖 · 꼬리표 밑 사슬 단에는 없다).
    final band = painter.debugBands.single.rect;
    final bandTop = v.yOf(base + geo.bandTop), bandBottom = v.yOf(base + geo.bandTop + geo.bandHeight);
    expect(geo.chainKinds, [0], reason: '왕조는 꼬리표 밑 흰 사슬');
    for (final rule in rules) {
      expect(rule.x0, greaterThanOrEqualTo(band.left + 1), reason: '$rule — 띠 테 안쪽');
      expect(rule.x1, lessThanOrEqualTo(band.right - 1), reason: '$rule — 띠 테 안쪽');
      expect(rule.y, greaterThan(bandTop + G.head - 2), reason: '$rule — 이름 색줄 위로 새지 않음');
      expect(rule.y, lessThan(bandBottom - 1), reason: '$rule — 띠 아랫변 · 사슬 단에 닿지 않음');
    }

    // 픽셀: 가로선 줄은 꼴 off 그림 위에 먹 12를 얹은 색 · 선 끝 밖(구분선 열 너머)과 빈 층(내각 뒤쪽)의 아랫줄은 그대로.
    for (final rule in [head, mid1, mid2, last]) {
      for (final x in [rule.x0 + 2, (rule.x0 + rule.x1) / 2 + .5, rule.x1 - 3]) {
        expectInk(pixelAt(px, x, rule.y), pixelAt(pxOff, x, rule.y), CanvasInk.a12, reason: '$rule x=$x');
      }
      expect(pixelAt(px, rule.x0 - 1, rule.y), pixelAt(pxOff, rule.x0 - 1, rule.y), reason: '$rule 왼쪽 끝 밖 — 1px 꼬리 없음');
      expect(pixelAt(px, rule.x1, rule.y), pixelAt(pxOff, rule.x1, rule.y), reason: '$rule 오른쪽 끝 밖 — 1px 꼬리 없음');
    }
    final empty = v.xOf(at(1000));
    expect(empty, greaterThan(last.x1 + 10));
    expect(pixelAt(px, empty, last.y), pixelAt(pxOff, empty, last.y), reason: '빈 층(내각 칸이 없는 자리)의 아랫줄에는 가로선이 없다');
  });

  test('맞닿음(꼴 b — 감독 결정 2026-10-25): 세로 칸 구분선은 위 가로 금(첫 층은 색줄 아랫금) 바로 아랫줄부터 아래 가로 금 바로 윗줄까지 틈 없이 · 만나는 점은 먹 한 번', () async {
    final (_, pxOff) = await drawn(FloorRule.off);
    final (painter, px) = await drawn(FloorRule.b);
    final stripB = stripBOf(painter);
    final band = painter.debugBands.single.rect, lo = band.left + 1, hi = band.right - 1;
    var seen = 0;
    for (final f in floorsOf(painter, stripB)) {
      final divs = dividersOf(f.cells, lo, hi);
      expect(divs, isNotEmpty);
      for (final d in divs) {
        final q = d.x, inward = d.left ? 3.0 : -3.0;
        // 꼴 off의 그 열 · 위 가로 금 바로 아랫줄은 바탕(옛 1px 들임 — 첫 층은 2px)이라 구분선 밑의 바탕 빛깔로 쓴다.
        final ground = pixelAt(pxOff, q, f.lineTop + 1);
        expect(pixelAt(pxOff, q, f.lineTop + 1), isNot(pixelAt(pxOff, q, (f.lineTop + f.lineBottom) / 2)), reason: '꼴 off는 위아래 들임이 있었다(x=$q)');
        for (double y = f.lineTop + 1; y < f.lineBottom; y++) {
          expectInk(pixelAt(px, q, y), ground, CanvasInk.a12, reason: '구분선 x=$q y=$y — 위 금 ${f.lineTop} · 아래 금 ${f.lineBottom} 사이를 틈 없이');
        }
        // 만나는 점(가로 금 줄)은 먹 한 번 — 가로선 안쪽 이웃 픽셀과 같고, 꼴 off 위에 먹 12 하나.
        for (final y in [f.lineTop, f.lineBottom]) {
          expect(pixelAt(px, q, y), pixelAt(px, q + inward, y), reason: '만나는 점 ($q, $y)은 가로선과 같은 짙기(먹이 두 번 얹히지 않음)');
          expectInk(pixelAt(px, q, y), pixelAt(pxOff, q, y), CanvasInk.a12, reason: '만나는 점 ($q, $y)');
        }
        seen++;
      }
    }
    expect(seen, 7, reason: '시기 둘 · 지도자 셋(두 칸 사이는 하나) · 내각 둘');
  });

  test('꼴 a: off와 다른 픽셀은 가로선 위와 세로 칸 구분선이 늘어난 자리(위아래 가로 금에 맞닿음)뿐 — 구분선 먹(25)은 그대로', () async {
    final (_, pxOff) = await drawn(FloorRule.off);
    final (painter, px) = await drawn(FloorRule.a);
    final stripB = stripBOf(painter);
    final band = painter.debugBands.single.rect, lo = band.left + 1, hi = band.right - 1;
    final rules = rulesOf(painter);
    final floors = floorsOf(painter, stripB);
    final columns = [for (final f in floors) dividersOf(f.cells, lo, hi).map((d) => d.x).toSet()];
    bool grown(int x, int y) {
      for (int k = 0; k < floors.length; k++) {
        if (y > floors[k].lineTop && y < floors[k].lineBottom && columns[k].contains(x.toDouble())) return true;
      }
      return false;
    }

    var changed = 0, onDivider = 0;
    final view = painter.scene.controller.view;
    for (int y = 0; y < 1080; y++) {
      for (int x = 0; x < 1920; x++) {
        final i = (y * 1920 + x) * 4;
        if (px[i] == pxOff[i] && px[i + 1] == pxOff[i + 1] && px[i + 2] == pxOff[i + 2] && px[i + 3] == pxOff[i + 3]) continue;
        if (y < view.head) {
          // 날짜 칸 머리 단: 모서리 칸 오른쪽 선이 구분선 줄까지 이어진 열뿐(맞닿음 걸음 2 — joints_paint_test.dart).
          expect(x, view.left - 1, reason: '머리 단에서 꼴 off와 다른 픽셀 ($x, $y)은 모서리 칸 선의 열');
          continue;
        }
        changed++;
        final on = rules.any((rule) => rule.y == y && x >= rule.x0 && x < rule.x1);
        if (!on) {
          expect(grown(x, y), isTrue, reason: '꼴 off와 다른 픽셀 ($x, $y)은 가로선 위이거나 구분선이 늘어난 자리여야 한다');
          onDivider++;
        }
      }
    }
    expect(changed, greaterThan(0));
    // 구분선마다 위 1줄 · 아래 1줄(첫 층은 위 2줄)이 늘었다: 시기 둘 × 3 · 지도자 셋 × 2 · 내각 둘 × 2.
    expect(onDivider, 2 * 3 + 3 * 2 + 2 * 2);
    // 늘어난 자리도 꼴 a의 구분선 먹 25.
    final lead0 = cellOf(painter, 1);
    final q = divL(lead0.l), ground = pixelAt(pxOff, q, stripB + G.floor + 1);
    expectInk(pixelAt(px, q, stripB + G.floor + 1), ground, CanvasInk.a25, reason: '지도자 층 왼쪽 구분선의 맨 윗줄');
    expectInk(pixelAt(px, q, stripB + 2 * G.floor - 1), ground, CanvasInk.a25, reason: '지도자 층 왼쪽 구분선의 맨 아랫줄');
  });

  test('꼴 b: 가로선은 a와 같고 세로 칸 구분선만 먹 25 → 12로 낮춤', () async {
    final (a, pxA) = await drawn(FloorRule.a);
    final (b, pxB) = await drawn(FloorRule.b);
    expect(rulesOf(b).map((r) => '$r'), rulesOf(a).map((r) => '$r'), reason: '가로선은 같다');
    // 지도자 두 칸 사이의 세로 금(지도자 층 가운데 줄).
    final lead0 = cellOf(a, 1), lead1 = cellOf(a, 1, nth: 1);
    final y = lead0.t + 6, bg = pixelAt(pxA, lead0.r - 30, y);
    var seen = 0;
    for (double x = lead0.r - 3; x <= lead1.l + 3; x++) {
      final pa = pixelAt(pxA, x, y);
      if (pa == bg) {
        expect(pixelAt(pxB, x, y), bg, reason: '금이 아닌 자리는 그대로 x=$x');
        continue;
      }
      seen++;
      expectInk(pa, bg, CanvasInk.a25, reason: '꼴 a 세로 금 x=$x');
      expectInk(pixelAt(pxB, x, y), bg, CanvasInk.a12, reason: '꼴 b 세로 금 x=$x');
    }
    expect(seen, 1, reason: '두 칸 사이 세로 금은 하나');
  });

  test('꼴 c: 먹 25 점선(1 긋고 2 띄움 — 세계에 붙은 무늬) · 세로 금은 그대로', () async {
    final (off, pxOff) = await drawn(FloorRule.off);
    final (c, pxC) = await drawn(FloorRule.c);
    final rules = rulesOf(c);
    expect(rules.length, 4);
    final v = c.scene.controller.view, phase = v.xOf(0).roundToDouble();
    final mid = rules[1];
    var dots = 0;
    for (double x = mid.x0 + 3; x < mid.x0 + 60; x++) {
      final on = ((x - phase) % 3 + 3) % 3 == 0;
      if (on) {
        dots++;
        expectInk(pixelAt(pxC, x, mid.y), pixelAt(pxOff, x, mid.y), CanvasInk.a25, reason: '점 x=$x');
      } else {
        expect(pixelAt(pxC, x, mid.y), pixelAt(pxOff, x, mid.y), reason: '틈 x=$x');
      }
    }
    expect(dots, 19);
    final lead0 = cellOf(off, 1);
    for (double x = lead0.r - 3; x <= lead0.r + 3; x++) {
      expect(pixelAt(pxC, x, lead0.t + 6), pixelAt(pxOff, x, lead0.t + 6), reason: '세로 금은 그대로 x=$x');
    }
  });

  test('빌린 칸(지도자 층 — 둘째 층)의 층 윗줄은 제 파선이 맡는다 — 그 자리의 가로선은 비우고, 구분선은 파선 바로 밑부터 · 아랫선은 띠의 밝기 그대로(칸의 .72를 타지 않음)', () async {
    final (off, pxOff) = await drawn(FloorRule.off, borrowedLeaders: true);
    final (painter, px) = await drawn(FloorRule.b, borrowedLeaders: true);
    final stripB = stripBOf(painter);
    final rules = rulesOf(painter);
    final lead0 = cellOf(painter, 1), lead1 = cellOf(painter, 1, nth: 1), phase = cellOf(painter, 4);
    final top = rules.where((r) => r.y == stripB + G.floor).toList();
    // 시기 칸의 아랫선(밝기 1)은 지도자 칸 자리에서 지워지고 그 바깥(시기 칸만 있는 자리 — 여기서는 없음)에만 남는다.
    expect(top.where((r) => r.x1 > (lead0.l - .5).roundToDouble() && r.x0 < (lead1.r + .5).roundToDouble()), isEmpty,
        reason: '빌린 지도자 칸의 윗변 자리에는 가로선이 없다: $top');
    expect([phase.l, phase.r], [lead0.l, lead1.r], reason: '이 견본은 시기 칸과 지도자 칸의 폭이 같다');
    final x = (lead0.l + lead0.r) / 2;
    expect(pixelAt(px, x, stripB + G.floor), pixelAt(pxOff, x, stripB + G.floor), reason: '빌린 칸 윗변(파선 줄)은 그대로');
    final below = rules.where((r) => r.y == stripB + 2 * G.floor).toList();
    expect(below.length, 1, reason: '지도자 아랫선 ∪ 내각 윗선 — 한 선: $below');
    expect([below.single.x0, below.single.x1], [divL(lead0.l), divR(lead1.r) + 1]);
    expect(below.single.alpha, 1.0, reason: '가로선은 띠의 밝기 — 빌린 칸의 .72를 타지 않는다');
    expect(rules.map((r) => r.alpha), everyElement(1.0));
    expect(StripLayer.borrowedAlpha, lessThan(1), reason: '빌린 칸은 칸 전체가 옅다(가로선은 그대로)');
    expect(noted(painter, '빌린칸').length, 2, reason: '파선은 그대로 둘');
    expect(noted(off, '빌린칸'), noted(painter, '빌린칸'), reason: '파선은 꼴과 상관없이 같다');
    // 빌린 칸의 구분선: 파선 줄(층 윗줄)은 칠하지 않고(파선과 겹친 짙은 점 없음) 그 바로 아랫줄(칸 윗줄)부터 아래 가로 금 바로 윗줄까지 — 먹 12 × .72.
    for (final q in [divL(lead0.l), divR(lead0.r), divR(lead1.r)]) {
      expect(pixelAt(px, q, stripB + G.floor), pixelAt(pxOff, q, stripB + G.floor), reason: '파선 줄 x=$q는 그대로');
      final ground = pixelAt(pxOff, q, stripB + G.floor + 1);
      for (double y = stripB + G.floor + 1; y < stripB + 2 * G.floor; y++) {
        expectInk(pixelAt(px, q, y), ground, CanvasInk.a12 * StripLayer.borrowedAlpha, reason: '빌린 칸 구분선 x=$q y=$y');
      }
    }
  });

  test('꼬리표 밑 흰 사슬 단: 칸 사이 세로 금은 종이 위 · 아래 테에 맞닿고(틈 0 · 테 줄은 한 번) 가로선은 없다 — 꼴과 상관없이 같은 그림(정수 자리)', () async {
    final (off, pxOff) = await drawn(FloorRule.off, twoDynasties: true);
    final (painter, px) = await drawn(FloorRule.b, twoDynasties: true);
    final chains = noted(painter, '사슬');
    expect(chains.length, 2, reason: '맞닿은 왕조 칸 둘');
    expect(chains.last, contains('jl=true'), reason: '뒤 칸은 앞 칸에 이어 붙는다(한 종이)');
    final box = chains.last.split(' ')[1].split(',');
    final x = int.parse(box[0]) / 10, top = int.parse(box[1]) / 10, bottom = top + G.chain - 1;
    expect(x, x.roundToDouble(), reason: '이 견본은 칸 경계가 정수 px');
    final divider = pixelAt(px, x, top + G.chain / 2), paper = pixelAt(px, x + 20, top + G.chain / 2);
    expect(divider, isNot(paper), reason: '칸 사이 세로 금이 있다');
    for (double y = top + 1; y < bottom; y++) {
      expect(pixelAt(px, x, y), divider, reason: '세로 금 y=$y — 위 테 $top · 아래 테 $bottom 사이를 틈 없이');
    }
    for (final y in [top, bottom]) {
      expect(pixelAt(px, x, y), pixelAt(px, x + 5, y), reason: '만나는 점 ($x, $y)은 테와 같은 짙기(먹 한 번)');
    }
    expect(rulesOf(painter).where((r) => r.y >= top - 1), isEmpty, reason: '사슬 단에는 칸 층 가로선이 없다');
    expect(noted(off, '사슬'), chains, reason: '사슬 자리는 꼴과 상관없이 같다');
    for (double y = top - 1; y <= bottom + 1; y++) {
      for (double dx = -30; dx <= 30; dx++) {
        expect(pixelAt(px, x + dx, y), pixelAt(pxOff, x + dx, y), reason: '정수 자리의 사슬 종이는 꼴 b와 off가 같다 ($dx, $y)');
      }
    }
  });

  test('조감(모양 c)에는 칸이 없어 가로선도 없다 — 꼴 b와 off의 그림이 같다(날짜 칸 머리 단의 모서리 칸 선만 다름)', () async {
    final (off, pxOff) = await drawn(FloorRule.off, bird: true);
    final (painter, px) = await drawn(FloorRule.b, bird: true);
    expect(painter.scene.layout.birdShape, BirdShape.c);
    expect(rulesOf(painter), isEmpty);
    // 머리 단의 모서리 칸 오른쪽 선은 꼴 off가 아니면 구분선 줄까지 잇는다(맞닿음 걸음 2 — joints_paint_test.dart). 그 열 밖은 같다.
    final view = painter.scene.controller.view;
    var corner = 0;
    for (int y = 0; y < 1080; y++) {
      for (int x = 0; x < 1920; x++) {
        if (pixelAt(px, x.toDouble(), y.toDouble()) == pixelAt(pxOff, x.toDouble(), y.toDouble())) continue;
        expect((x, y < view.head), (view.left - 1, true), reason: '꼴 off와 다른 픽셀 ($x, $y)');
        corner++;
      }
    }
    expect(corner, lessThan(5), reason: '머리 단 구분선 줄 몇 점');
  });

  test('소수 자리(띠 · 칸이 픽셀 사이) · 흐린 띠: 가로선 · 띠 층 금은 띠 테 바로 옆 열부터 · 직각 테 귀는 세로 테 하나만 · 사슬 종이 테는 꼬리표 테의 열', () async {
    final (_, pxOff) = await drawn(FloorRule.off, fromStart: true, shift: .4, dim: true);
    final (painter, px) = await drawn(FloorRule.b, fromStart: true, shift: .4, dim: true);
    final band = painter.debugBands.single.rect;
    expect(band.left, closeTo(339.6, 1e-6), reason: '띠 왼쪽이 픽셀 사이');
    expect(band.right, closeTo(1839.6, 1e-6));
    final frameL = band.left.floorToDouble(), frameR = (band.right - 1).floorToDouble(); // 띠 테의 열(339 · 1838)
    final stripB = stripBOf(painter), top = band.top, bottom = band.bottom;
    final rules = rulesOf(painter);
    expect(rules.map((r) => r.alpha), everyElement(closeTo(.58, 1e-3)), reason: '흐린 띠 — 가로선도 띠의 밝기');

    // (1) 띠 테에 닿는 내각 칸의 가로선(내각 윗선 · 아랫선)은 테 바로 옆 열(340)부터 — 예전 ceil(lo)은 341부터라 340이 비었다.
    for (final y in [stripB + 2 * G.floor, stripB + 3 * G.floor]) {
      final r = rules.where((r) => r.y == y).toList();
      expect(r.first.x0, frameL + 1, reason: '줄 $y의 가로선 왼끝 = 테 열 + 1');
      expect(pixelAt(px, frameL + 1, y), pixelAt(px, frameL + 6, y), reason: '줄 $y — 테 옆 열부터 같은 짙기');
    }
    // (2) 띠 층의 금(색줄 아랫금 — 칸이 없는 자리)도 테 옆 열부터 · 오른쪽은 테 열 앞까지(테 열에 겹쳐 짙어지지 않음).
    expect(pixelAt(px, frameL + 1, stripB - 1), pixelAt(px, frameL + 20, stripB - 1), reason: '색줄 아랫금이 테 옆 열부터');
    expect(pixelAt(pxOff, frameL + 1, stripB - 1), isNot(pixelAt(pxOff, frameL + 20, stripB - 1)), reason: '꼴 off(소수 끝)는 테 옆 열이 달랐다 — 견본이 헛돌지 않게');
    for (final y in [stripB + G.floor, stripB + 2 * G.floor]) {
      expect(pixelAt(px, frameR, y), pixelAt(px, frameR, y - 1), reason: '층 사이 금 줄 $y의 오른쪽 테 열은 테 하나(금이 겹치지 않음)');
      expect(pixelAt(pxOff, frameR, y), isNot(pixelAt(pxOff, frameR, y - 1)), reason: '꼴 off는 금이 테 열에 겹쳐 짙었다');
    }
    // (3) 직각 귀(오른쪽 위 · 아래): 귀 픽셀은 세로 테 하나 · 가로 테가 테 밖 열로 번지지 않음(그 열은 띠 칠 번짐만 — 아래 줄과 같음).
    for (final (y, inner) in [(top, top + 4), (bottom - 1, bottom - 4)]) {
      expect(pixelAt(px, frameR, y), pixelAt(px, frameR, inner), reason: '귀 ($frameR, $y)는 세로 테 하나 — 흐린 띠에서 먹 두 번 없음');
      expect(pixelAt(px, frameR + 1, y), pixelAt(px, frameR + 1, inner), reason: '귀 바깥 열 ($frameR + 1, $y)에 가로 테가 번지지 않음');
      expect(pixelAt(pxOff, frameR, y), isNot(pixelAt(pxOff, frameR, inner)), reason: '꼴 off는 귀에 먹이 두 번 얹혔다');
    }
    // (4) 띠 시작부터의 왕조 사슬: 종이 왼쪽 테 = 꼬리표 왼쪽 테의 열(339) · 그 옆은 종이 · 오른쪽 테는 칸 끝의 반올림 열.
    final chain = noted(painter, '사슬').single.split(' ')[1].split(',');
    final chainTop = int.parse(chain[1]) / 10, mid = chainTop + G.chain / 2;
    final rightEdge = v(painter, 1400).roundToDouble() - 1; // 왕조 칸 끝(띠 안 — 반올림 열)의 오른쪽 테
    expect(pixelAt(px, frameL, mid), pixelAt(px, rightEdge, mid), reason: '사슬 왼쪽 테(띠 테 열)와 오른쪽 테가 같은 테');
    expect(pixelAt(px, frameL + 1, mid), pixelAt(px, 900, mid), reason: '테 옆 열은 종이');
    expect(pixelAt(pxOff, frameL + 1, mid), isNot(pixelAt(pxOff, 900, mid)), reason: '꼴 off(소수 자리)는 테가 한 열 오른쪽(340)이었다');
  });

  test('점선 띠 테(조직체) × 몸통 안 가로 금(색줄 아랫금 · 층 사이 금 · 사건 칸 윗줄)의 T자: 테 무늬가 빈 줄이면 만나는 점 하나를 테 빛깔로 — 틈 없음 · 먹 한 번(세로 소수 자리 · 흐린 띠도)', () async {
    for (final dy in [0.0, -.6]) {
      for (final dim in [false, true]) {
        final (_, pxOff) = await drawn(FloorRule.off, bandKind: BandKind.org, dy: dy, dim: dim);
        final (painter, px) = await drawn(FloorRule.b, bandKind: BandKind.org, dy: dy, dim: dim);
        final band = painter.debugBands.single.rect;
        final frameL = band.left.floorToDouble(), frameR = (band.right - 1).floorToDouble(), top = band.top.floorToDouble();
        final rows = painter.bands.innerRows[1]!;
        expect(rows, [for (final y in rows) y.floorToDouble()]..sort(), reason: '정수 줄 · 오름차순');
        expect(rows.length, 4, reason: '색줄 아랫금 · 시기|지도자 · 지도자|내각 · 내각|사건 칸');
        bool on(double y) => (y - top) % 2 == 0; // 점선 1 · 1 — 무늬는 윗변 줄(정수)부터
        var tees = 0;
        for (final y in rows) {
          if (on(y)) continue;
          // 흐린 띠에서는 바탕(칠)이 같은 줄끼리만 견준다 — 색줄 아랫금(색줄 칠 · 바로 위 줄도 색줄)만. 흐리지 않으면 테가 불투명이라 모든 T자.
          if (dim && y != rows.first) continue;
          for (final x in [frameL, frameR]) {
            expect(pixelAt(px, x, y), pixelAt(px, x, y - 1), reason: 'dy $dy dim $dim: T자 ($x, $y)는 바로 위 점과 같은 짙기(틈 없음 · 먹 한 번)');
            // 꼴 off(무늬는 소수 윗변에서)는 정수 자리에서 그 점이 비었다.
            if (dy == 0) expect(pixelAt(pxOff, x, y), isNot(pixelAt(pxOff, x, y - 1)), reason: 'dim $dim: 꼴 off는 T자 ($x, $y)가 비었다');
            tees++;
          }
        }
        expect(tees, greaterThanOrEqualTo(2), reason: 'dy $dy dim $dim: 견본에 무늬가 빈 줄에 닿는 가로 금이 있다(색줄 아랫금 — 윗변에서 13줄)');
      }
    }
  });

  test('세로 소수 자리(관성 스크롤 뒤 — 띠 윗변 소수부 .6): 직각 테 귀는 세로 테가 맡아 비지 않고 · 아랫변 밑 줄로 세로 테가 삐져나오지 않는다', () async {
    final (_, pxOff) = await drawn(FloorRule.off, dy: -.6);
    final (painter, px) = await drawn(FloorRule.b, dy: -.6);
    expect(painter.scene.controller.view.top, -.6, reason: '견본: 세로 자리가 소수');
    final band = painter.debugBands.single.rect;
    expect(band.top - band.top.floorToDouble(), closeTo(.6, 1e-6), reason: '띠 윗변이 줄 사이');
    final frameR = (band.right - 1).floorToDouble(), top = band.top.floorToDouble(), bottom = (band.bottom - 1).floorToDouble();
    final edge = pixelAt(px, frameR, top + 4);
    expect(pixelAt(px, frameR, top), edge, reason: '오른쪽 위 귀 ($frameR, $top) — 가로 테는 귀 앞에서 멈추고 세로 테가 윗변 줄부터');
    expect(pixelAt(px, frameR, bottom), edge, reason: '오른쪽 아래 귀');
    expect(pixelAt(px, frameR, bottom + 1), pixelAt(px, frameR - 6, bottom + 1), reason: '아랫변 밑 줄에 세로 테가 없다(띠 칠 번짐만 — 옆 열과 같음)');
    expect(pixelAt(pxOff, frameR, bottom + 1), isNot(pixelAt(pxOff, frameR - 6, bottom + 1)), reason: '꼴 off는 세로 테가 아랫변 밑으로 한 줄 삐져나왔다');
  });

  test('타일 이음매에 딱 놓인 칸 경계(앞 칸은 이음매에서 끝 · 뒤 칸은 다음 타일 0에서 시작): 두 타일이 저마다 구분선을 그어도 그 사이 가로선이 비지 않고 겹치지 않는다 · 이웃이 없으면 꼬리 없음', () async {
    const seamPx = 8192.0; // 단계 9 타일 너비(통 256 × 32px)
    expect(at(seamPx), tileSpan(9).toDouble());
    Uint8List left({bool neighbor = true}) {
      final t = TileBuilder(level: 9, x: 0, chunk: 0)..band(1, 0, at(seamPx - 1400), at(seamPx), '첫불 성채국', look: bandLook, flags: Tile.clipRight);
      if (neighbor) t.cell(10, 0, at(seamPx - 900), at(seamPx), '은결 나나나', kind: 1, style: st(0, seq: 0));
      return t.build();
    }

    final right = (TileBuilder(level: 9, x: 1, chunk: 0)
          ..band(1, 0, 0, at(1400), '첫불 성채국', look: bandLook, flags: Tile.clipLeft)
          ..cell(11, 0, 0, at(900), '둘째 지도자', kind: 1, style: st(0, seq: 1)))
        .build();
    for (final nudge in [0.0, .3, .6]) {
      final shift = seamPx - (1080 - SceneView.gutter) - nudge; // 이음매가 화면 x 1080 + nudge
      final (painter, px) = await drawn(FloorRule.b, data: left(), more: {1: right}, shift: shift);
      final seam = painter.scene.controller.view.xOf(at(seamPx));
      expect(seam, closeTo(1080 + nudge, 1e-6));
      final stripB = stripBOf(painter);
      final rules = rulesOf(painter);
      for (final y in [stripB + G.floor, stripB + 2 * G.floor]) {
        final pieces = rules.where((r) => r.y == y).toList();
        expect(pieces.length, 2, reason: 'nudge $nudge 줄 $y: 타일마다 한 조각 — $pieces');
        for (double x = seam.roundToDouble() - 4; x <= seam.roundToDouble() + 4; x++) {
          final n = pieces.where((r) => x >= r.x0 && x < r.x1).length;
          expect(n, 1, reason: 'nudge $nudge 줄 $y x=$x는 가로선 한 조각(틈 · 겹침 없음): $pieces');
          expect(pixelAt(px, x, y), pixelAt(px, seam.roundToDouble() - 8, y), reason: 'nudge $nudge 줄 $y x=$x는 가로선 짙기');
        }
      }
      // 이웃이 없으면(앞 타일에 칸이 없음) 뒤 칸의 가로선은 제 구분선 열부터 — 구분선 밖 1px 꼬리 없음.
      final (alone, _) = await drawn(FloorRule.b, data: left(neighbor: false), more: {1: right}, shift: shift);
      final lead = cellOf(alone, 1);
      for (final y in [stripB + G.floor, stripB + 2 * G.floor]) {
        final first = rulesOf(alone).where((r) => r.y == y).map((r) => r.x0).reduce(math.min);
        expect(first, divL(lead.l), reason: 'nudge $nudge 줄 $y: 이웃 없는 이음매 칸의 가로선은 제 구분선 열(${divL(lead.l)})부터');
      }
    }
  });

  test('집권 단의 2px 밑줄: 두 끝은 칸 구분선 열(띠 테에 닿거나 테 가까이라 구분선을 테가 맡는 끝은 테 바로 옆 열)의 정수 px · 아래 가로 금 바로 위 두 줄 — 구분선 끝을 받고 이웃 칸 · 테 옆으로 반 픽셀 번지지 않음', () async {
    const power = CellStyle.groupOne << 27;
    final data = (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, at(100), at(1600), '첫불 성채국', look: bandLook | 1 << (21 + 3))
          ..cell(20, 0, at(150), at(1400), '장부 학파\t복구기', kind: 4, lane: 0, style: st(32, seq: 0))
          ..cell(50, 0, at(100), at(500), '푸\t푸른 집안', kind: 8, lane: 2, style: power | st(0, seq: 0), color: 0x6a8fb0)
          ..cell(51, 0, at(600), at(1000), '붉\t붉은 집안', kind: 8, lane: 2, style: power | st(0, seq: 1), color: 0xb06a6a)
          // 띠 끝 2px 앞에서 끝남 — 오른쪽 구분선은 띠 테 가까이라 긋지 않고 띠 테가 맡는다
          ..cell(52, 0, at(1200), at(1598), '푸\t푸른 집안', kind: 8, lane: 2, style: power | st(0, seq: 2), color: 0x6a8fb0)
          ..cell(10, 0, at(150), at(1400), '은결 나나나', kind: 1, style: st(0, seq: 0)))
        .build();
    final (off, _) = await drawn(FloorRule.off, data: data, layout: shape(power: true), shift: .25);
    final (painter, px) = await drawn(FloorRule.b, data: data, layout: shape(power: true), shift: .25);
    final geo = painter.scene.layout.geo(0);
    expect(geo.powerTop, greaterThan(0), reason: '견본: 집권 단이 있다');
    final stripB = stripBOf(painter), band = painter.debugBands.single.rect;
    final under = [for (final n in noted(painter, '단체밑줄')) n.split(' ')[1].split(',').map((v) => int.parse(v) / 10).toList()];
    expect(under.length, 3);
    final c0 = cellOf(painter, 8), c1 = cellOf(painter, 8, nth: 1);
    expect(c1.l - c1.l.floorToDouble(), closeTo(.25, .051), reason: '견본: 둘째 칸의 왼쪽 끝이 소수(.25 — 칸 틈 0.5 + 보기 .75)');
    // 첫 칸은 띠 시작에 닿는다: 테 바로 옆 열부터 · 오른쪽은 구분선 열까지.
    expect(under[0][0], band.left.floorToDouble() + 1, reason: '띠 테에 닿은 끝 — 테 열 + 1');
    expect(under[0][0] + under[0][2], divR(c0.r) + 1, reason: '첫 칸 오른쪽 — 구분선 열까지');
    expect(under[1][0], divL(c1.l), reason: '둘째 칸 왼쪽 — 구분선 열부터');
    expect(under[1][0] + under[1][2], divR(c1.r) + 1, reason: '둘째 칸 오른쪽 — 구분선 열까지');
    final frameR = (band.right - 1).floorToDouble(), c2 = cellOf(painter, 8, nth: 2);
    expect(divR(c2.r) + 1, lessThan(frameR), reason: '견본: 셋째 칸의 구분선 열 셈은 띠 테 앞에서 1px 넘게 모자람');
    expect(under[2][0] + under[2][2], frameR, reason: '셋째 칸 오른쪽(구분선을 띠 테가 맡음) — 테 바로 앞 열까지(가로선 끝과 같음)');
    final lineBelow = stripB + G.floor + G.floor; // 집권 층 아래 가로 금(지도자 층 윗선)
    for (final u in under) {
      expect([u[1], u[3]], [lineBelow - 2, 2.0], reason: '아래 가로 금 바로 위 두 줄');
    }
    // 둘째 칸 왼쪽 구분선은 밑줄 위에서 멈추고 밑줄이 그 열을 받는다.
    final q = divL(c1.l);
    expect(pixelAt(px, q, lineBelow - 3), isNot(pixelAt(px, q - 3, lineBelow - 3)), reason: '구분선이 밑줄 바로 위 줄까지');
    expect(pixelAt(px, q, lineBelow - 2), pixelAt(px, q + 5, lineBelow - 2), reason: '구분선 열의 밑줄 줄은 밑줄 하나');
    // 꼴 off는 칸 상자 그대로(소수 끝).
    final offUnder = [for (final n in noted(off, '단체밑줄')) n.split(' ')[1].split(',').map((v) => int.parse(v) / 10).toList()];
    expect(offUnder[1][0], closeTo(cellOf(off, 8, nth: 1).l, .051), reason: '꼴 off — 칸 왼쪽 그대로(소수)');
  });

  test('합치기: 겹친 조각은 밝은 쪽 · 긋지 않는 조각이 이김 · 이웃한 같은 밝기는 한 선 · 다른 띠 · 다른 줄은 따로', () {
    final rules = FloorRules()
      ..add(1, 10.4, 0, 10, .5)
      ..add(1, 10, 5, 20, 1)
      ..add(1, 10, 20, 30, 1)
      ..exclude(1, 10, 24, 26)
      ..add(2, 10, 0, 10, 1)
      ..add(1, 11, 0, 3, .3)
      ..add(1, 12, 0, 3, 0);
    expect(rules.length, 6, reason: '밝기 0은 버림');
    // 그리개 없이 맨 그리기 문맥으로 — 기록만 본다.
    final (scene, _) = make(cells());
    final recorder = ui.PictureRecorder(), sink = DebugSink();
    final c = PaintContext(
      canvas: ui.Canvas(recorder), scene: scene, text: ParagraphText(), w: 1920, h: 1080,
      quads: Quads(), dividers: Lines(Look.line), later: TextQueue(), patterns: Patterns(), debug: sink,
    );
    rules.emit(c, FloorRule.a, 0);
    recorder.endRecording().dispose();
    expect(rules.isEmpty, isTrue, reason: '긋고 나면 비운다');
    expect(sink.notes['층선']!.map((n) => '$n').toList(), [
      '1 100 0,50 500',
      '1 100 50,240 1000',
      '1 100 260,300 1000',
      '1 110 0,30 300',
      '2 100 0,100 1000',
    ]);
  });
}

/// 그 분(px 자리 — 그림 영역 왼쪽에서 [px])의 화면 x.
double v(TimelinePainter painter, double px) => painter.scene.controller.view.xOf(at(px));

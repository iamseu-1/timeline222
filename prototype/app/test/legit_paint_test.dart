import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show LegitLook;
import 'package:archive_prototype/scene/paint/ink.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/strips.dart' show CellStyle;
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 두 단 지도자 층의 조각 그림(칸 그림 갈래 걸음 2 · 정통성 넷 가 다듬은 꼴 lg2-ga — 다듬기 판 `.claude/research/stage4-choose/themes/g-legit2.js`
// paintCells): 두 단 띠의 지도자 칸(모든 단)을 칸 경계로 끊은 조각 — 혼자인 조각은 층 전체(2 × 14), 겹친 조각만 제 단 14(칸 종류 1의 lane).
// 겹친 조각에는 단 사이 금(먹 25 · 양 끝 세로 금 화소까지). 칸 금은 칸의 시작 · 끝에서 그 조각 안 제 자리에만 · 위아래 가로 금에 닿게.
// 이름은 칸이 시작하는 조각부터 이름과 여백이 드는 첫 조각의 제 자리 가운데. 누름 자리는 조각마다 제 자리. 섭정 칸(구역 57)은 조각을 끊지 않는다.
// 한 단 띠와 스위치 legit을 끈 그림은 지금 길 그대로(paint/strips.dart).

/// 단계 9에서 통 하나가 32px일 때의 1분 폭 — 자리는 모두 '그림 영역 왼쪽에서 몇 px'로 적고 분으로 바꾼다(chains_paint_test와 같은 식).
final ppm = 32 / bucketMinutes(9);
double at(double px) => px / ppm;

/// 엔진 답 꼴의 줄 하나(줄 값이 실린 새 저장소): 지도자 칸만 · 줄 fig_wide 26 ~ 27 = [lanes] − 1(비트 3 ~ 5 · 17과 함께).
Map<String, dynamic> row(int id, {int lanes = 2}) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1,
  'text_top': 0, 'text_lines': 1, 'rail_top': 0, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[],
  'fig': 0, 'fig_wide': 1 << 3 | 1 << 17 | (lanes - 1) << 26, 'dep': 0, 'zones': 0, 'hem': 0, 'variant': 0,
  'rail': 0, 'cell_rows': 1, 'dynasty': 0, 'leader': 1, 'cabinet': 0, 'hang': 0,
};

SceneLayout layoutOf({int lanes = 2}) => SceneLayout.fromJson({
  'packs': [
    {'id': 1, 'name': '두 단 견본', 'events': 0},
  ],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '하연 갈래', 'color': 0xa0bcc5, 'key': 'legit-a', 'dynasty': 0, 'leader': 1, 'cabinet': 0, 'organ': 0, 'rail_levels': 2,
      'rows': [row(0, lanes: lanes)],
    },
  ],
  'epochs': <dynamic>[],
  'categories': <dynamic>[],
  'axis': <dynamic>[],
})..reduceMotion = true;

/// 띠 look: 비트 20 = 칸이 있다 · 21 + 5 지도자. sub 22 ~ 23 = 띠의 지도자 단 수 − 1.
const leaderLook = 1 << 20 | 1 << 26, twoLanes = 1 << 22;

/// style: 비트 2 = 앞 칸과 같은 무리 · 15 ~ 26 = 순번 + 1.
int st(int seq, {bool join = false}) => (join ? 4 : 0) | (seq + 1) << 15;

/// 하연 왕국(그림 영역 100 ~ 1500 px · 두 단 띠): 단 0 — 서하 100 ~ 400 · 온결 400 ~ 700 · 무령 900 ~ 1300 · 태후 서리(섭정) 900 ~ 1050 · 하늘 1460 ~ 1500,
/// 단 1 — 다빈(공동) 550 ~ 900 · 단공(주장) 1290 ~ 1450. 조각: 온결 · 다빈은 550 ~ 700(150px)이 겹침, 무령 · 단공은 1290 ~ 1300(10px)이 겹침.
/// 이웃 띠 외톨 왕국(1520 ~ 1900 · 한 단 띠) — 같은 줄의 한 단 띠는 지금 길.
Uint8List legitTile({int sub = twoLanes}) {
  final t = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, at(100), at(1500), '하연 왕국', look: leaderLook, sub: sub)
    ..band(2, 0, at(1520), at(1900), '외톨 왕국', look: leaderLook, color: 0xc8b193)
    // 칸은 (줄 · 종류 · 단 · 시작) 차례(엔진 타일과 같은 약속).
    ..cell(10, 0, at(100), at(400), '서하왕', style: st(0))
    ..cell(11, 0, at(400), at(700), '온결왕', style: st(1, join: true))
    ..cell(13, 0, at(900), at(1300), '무령왕', style: st(3, join: true))
    ..cell(14, 0, at(900), at(1050), '태후 서리', style: st(4))
    ..cell(16, 0, at(1460), at(1500), '하늘', style: st(6))
    ..cell(20, 0, at(1520), at(1900), '외톨왕', style: st(0))
    ..cell(12, 0, at(550), at(900), '다빈왕', lane: 1, style: st(2))
    ..cell(15, 0, at(1290), at(1450), '단공', lane: 1, style: st(5))
    // 구역 57(칸의 정통성 — a 종류 · b 단 · c 순번 + 1 · d 정통성 + 1): 다빈 공동(2) · 단공 주장(5) · 태후 서리 섭정(3).
    ..item(57, 50, 0, at(550), at(900), a: 1, b: 1, c: 3, d: 3, ref: 1)
    ..item(57, 51, 0, at(1290), at(1450), a: 1, b: 1, c: 6, d: 6, ref: 1)
    ..item(57, 52, 0, at(900), at(1050), a: 1, b: 0, c: 5, d: 4, ref: 1);
  return t.build();
}

/// 물레 왕국(두 단 띠 · 420 ~ 1400)과 그 왼쪽의 외톨 왕국(한 단 · 100 ~ 400): 단 0 — 가 420 ~ 800 · 무령 800 ~ 1300 · 태후(섭정) 900 ~ 1100,
/// 단 1 — 나(주장) 420 ~ 700 · 단공(주장) 1000 ~ 1200. 조각: 가 · 나는 420 ~ 700이 겹침, 무령 · 단공은 1000 ~ 1200이 겹침(섭정은 셋째로 세지 않음).
Uint8List wardTile() => (TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(2, 0, at(100), at(400), '외톨 왕국', look: leaderLook, color: 0xc8b193)
      ..band(1, 0, at(420), at(1400), '물레 왕국', look: leaderLook, sub: twoLanes)
      ..cell(20, 0, at(100), at(400), '외톨왕', style: st(0))
      ..cell(10, 0, at(420), at(800), '가왕', style: st(0))
      ..cell(11, 0, at(800), at(1300), '무령왕', style: st(1, join: true))
      ..cell(12, 0, at(900), at(1100), '태후', style: st(2))
      ..cell(14, 0, at(420), at(700), '나왕', lane: 1, style: st(4))
      ..cell(13, 0, at(1000), at(1200), '단공', lane: 1, style: st(3))
      ..item(57, 50, 0, at(1000), at(1200), a: 1, b: 1, c: 4, d: 6, ref: 1)
      ..item(57, 51, 0, at(900), at(1100), a: 1, b: 0, c: 3, d: 4, ref: 1)
      ..item(57, 52, 0, at(420), at(700), a: 1, b: 1, c: 5, d: 6, ref: 1))
    .build();

/// 여울 공국(한 단 띠 · 한 단 줄 · 100 ~ 1500): 첫공 100 ~ 400 · 둘째공(명목) 400 ~ 850 · 태비 아란(섭정) 500 ~ 700 · 셋째공(주장) 870 ~ 1300 ·
/// 넷째공(명목 + 옛 명목 지도자 29비트) 1300 ~ 1500. 둘째공과 셋째공 사이(850 ~ 870)는 빈 자리 — 건너뛴 순번(2)이 섭정 칸이라 메우지 않는다.
/// [legits]가 거짓이면 구역 57 없이(같은 칸 · 같은 비트).
Uint8List oneLaneTile({bool legits = true}) {
  final t = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, at(100), at(1500), '여울 공국', look: leaderLook)
    ..cell(10, 0, at(100), at(400), '첫공', style: st(0))
    ..cell(11, 0, at(400), at(850), '둘째공', style: st(1, join: true))
    ..cell(12, 0, at(500), at(700), '태비 아란', style: st(2))
    ..cell(13, 0, at(870), at(1300), '셋째공', style: st(3, join: true))
    ..cell(14, 0, at(1300), at(1500), '넷째공', style: st(4, join: true) | CellStyle.nominalLeader);
  if (legits) {
    t
      ..item(57, 50, 0, at(400), at(850), a: 1, c: 2, d: 5, ref: 1)
      ..item(57, 51, 0, at(500), at(700), a: 1, c: 3, d: 4, ref: 1)
      ..item(57, 52, 0, at(870), at(1300), a: 1, c: 4, d: 6, ref: 1)
      ..item(57, 53, 0, at(1300), at(1500), a: 1, c: 5, d: 5, ref: 1);
  }
  return t.build();
}

/// 칸 그림 갈래의 시험은 칸 층 가로선의 꼴 [rows] off(구분선 갈래 전 그림 — 맞닿음 · 가로선 없음)로 본다: 이 파일의 픽셀 기대(먹 25 · 칸 금 범위)는
/// 칸 그림 갈래가 적은 그대로이고, 꼴 off는 구분선 갈래 전 그림과 같아야 하므로 그대로 맞아야 한다. 꼴 a · b · c(기본 b)는 끝의 무리
/// '구분선 갈래와 합침'이 본다(4단계 마지막 합치기 — 감독 결정 2026-10-25 맞닿음).
(TimelineScene, TimelinePainter) make({bool legit = true, int lanes = 2, Uint8List? data, FloorRule rows = FloorRule.off}) {
  PaintPick.legit = legit;
  PaintPick.rows = rows;
  final layout = layoutOf(lanes: lanes);
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..setContentHeight(layout.totalHeight + 200);
  controller.showRange(0, at(1920 - SceneView.gutter));
  final tile = data ?? legitTile();
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

/// 그 픽셀의 0xRRGGBB.
int rgbAt(Uint8List px, num x, num y) {
  final i = (y.floor() * 1920 + x.floor()) * 4;
  return px[i] << 16 | px[i + 1] << 8 | px[i + 2];
}

/// [rgb] 위에 먹을 [a]만큼 얹은 색.
int inked(int rgb, double a) {
  int ch(int s) => (((rgb >> s) & 0xff) * (1 - a)).round() << s;
  return ch(16) | ch(8) | ch(0);
}

/// 두 색이 채널마다 ±2 안에서 같은가.
bool near(int a, int b) => [16, 8, 0].every((s) => (((a >> s) & 0xff) - ((b >> s) & 0xff)).abs() <= 2);

/// 기록 '종류:줄:단 l,t,w,h'(0.1px 단위).
class Noted {
  Noted(String text)
    : lane = int.parse(text.split(' ')[0].split(':')[2]),
      kind = int.parse(text.split(' ')[0].split(':')[0]),
      l = int.parse(text.split(' ')[1].split(',')[0]) / 10,
      t = int.parse(text.split(' ')[1].split(',')[1]) / 10,
      w = int.parse(text.split(' ')[1].split(',')[2]) / 10,
      h = int.parse(text.split(' ')[1].split(',')[3]) / 10;
  final int kind, lane;
  final double l, t, w, h;
  double get r => l + w;
}

List<Noted> cellsOf(TimelinePainter painter) => [for (final v in painter.debugSink.notes['칸'] ?? const <Object>[]) Noted('$v')];

/// 화면 x(그림 영역 [px] — 배치 px).
double xAt(TimelineScene scene, double px) => scene.controller.view.xOf(at(px));

/// 줄 0 지도자 층의 윗변(화면 y — 하연 왕국은 지도자만 · 줄의 첫 층이라 맞붙이기가 없음).
double baseOf(TimelineScene scene) {
  final layout = scene.layout, geo = layout.geo(0);
  return scene.controller.view.yOf(layout.rowTop(0) + geo.leaderTop);
}

/// 섭정 밑줄의 먹(종이 위 고른 회색 60).
const regentInk = 0x666666;

/// 주장 빗금(5px 칸의 1px 화소 계단 — 다듬기 판 hatch: 칸 (i, 4 − i))이 화소 [x] · [y]에 서는가. 무늬는 분 0이 선 열 · 지도자 층 윗선([phaseY])에 붙는다.
bool stairAt(TimelineScene scene, int x, int y, double phaseY) {
  final phaseX = LegitLook.phaseX(scene.controller.view.xOf(0));
  return ((x - phaseX) % 5 + (y - phaseY) % 5).round() == 4;
}

/// [x0] ~ [x1) × [y0] ~ [y1)의 화소가 빗금 자리에서는 [tint] 위 먹 25, 그 밖은 [tint] 그대로인가 — 다른 화소가 있으면 그 자리를 적는다.
void expectHatch(TimelineScene scene, Uint8List px, num x0, num x1, num y0, num y1, int tint, double phaseY, String why) {
  final ink = inked(tint, .25);
  var stairs = 0;
  for (int y = y0.floor(); y < y1; y++) {
    for (int x = x0.floor(); x < x1; x++) {
      final want = stairAt(scene, x, y, phaseY), got = rgbAt(px, x, y);
      if (want) stairs++;
      expect(want ? near(got, ink) : got == tint, isTrue, reason: '$why — ($x, $y) ${got.toRadixString(16)} 빗금=$want');
    }
  }
  expect(stairs, greaterThan(0), reason: '$why — 빗금 화소가 하나도 없다');
}

void main() {
  tearDown(PaintPick.reset);

  test('혼자인 조각은 층 전체(27) · 겹친 조각만 제 단(13) — 칸 기록 · 누름 자리가 조각마다 제 자리', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final geo = scene.layout.geo(0), base = baseOf(scene);
    expect(geo.leaderLanes, 2);
    final cells = cellsOf(painter).where((n) => n.kind == 1).toList();
    // (그림 영역 시작 px, 단(기록의 단 — 칸의 단), 위, 높이)
    Noted at0(double px, int lane) => cells.firstWhere((n) => n.lane == lane && (n.l - xAt(scene, px)).abs() < 1.5, orElse: () => fail('조각 $px · 단 $lane 없음'));
    void slot(double px, int lane, double top, double h, String what) {
      final n = at0(px, lane);
      expect(n.t, closeTo(top, .05), reason: '$what 위');
      expect(n.h, closeTo(h, .05), reason: '$what 높이');
    }

    slot(100, 0, base + 1, 27, '서하(혼자 — 층 전체)');
    slot(400, 0, base + 1, 27, '온결 400 ~ 550(혼자)');
    slot(550, 0, base + 1, 13, '온결 550 ~ 700(다빈과 겹침 — 단 0)');
    slot(550, 1, base + 15, 13, '다빈 550 ~ 700(겹침 — 단 1)');
    slot(700, 1, base + 1, 27, '다빈 700 ~ 900(혼자 — 층 전체)');
    slot(900, 0, base + 1, 27, '무령 900 ~ 1290');
    slot(1290, 0, base + 1, 13, '무령 1290 ~ 1300(단공과 겹침)');
    slot(1290, 1, base + 15, 13, '단공 1290 ~ 1300');
    slot(1300, 1, base + 1, 27, '단공 1300 ~ 1450(혼자)');
    slot(1460, 0, base + 1, 27, '하늘');
    // 섭정 칸은 조각을 끊지 않는다 — 무령의 900 ~ 1290이 한 조각이고, 섭정 칸은 칸으로 그리지 않는다(걸음 3 — 피후견 칸의 밑줄).
    expect(cells.where((n) => n.lane == 0 && (n.l - xAt(scene, 1050)).abs() < 1.5), isEmpty, reason: '1050에서 끊긴 조각 없음');
    expect(cells.where((n) => n.lane == 0 && (n.l - xAt(scene, 900)).abs() < 1.5 && n.h > 26).length, 1, reason: '무령만 — 섭정 칸은 칸이 아니다');
    // 한 단 띠(외톨 왕국)는 지금 길 — 지도자 층 윗변 + 1부터 13.
    slot(1520, 0, base + 1, 13, '외톨(한 단 띠)');
    // 누름 자리: 조각마다 제 자리.
    final hit = painter.strips.hitStrips;
    expect(hit(xAt(scene, 475), base + 22)!.ref, 'leader:1', reason: '온결 혼자 조각의 아랫 단 자리');
    expect(hit(xAt(scene, 625), base + 5)!.ref, 'leader:1', reason: '겹친 조각 단 0 = 온결');
    expect(hit(xAt(scene, 625), base + 22)!.ref, 'leader:2', reason: '겹친 조각 단 1 = 다빈');
    expect(hit(xAt(scene, 800), base + 5)!.ref, 'leader:2', reason: '다빈 혼자 조각의 윗 단 자리');
    expect(hit(xAt(scene, 1600), base + 22)?.kind, isNot(1), reason: '한 단 띠의 칸 밑(14 밑)은 지도자 칸이 아니다');
  });

  test('단 사이 금 — 겹친 조각에만 · 먹 25 · 양 끝 세로 금 화소까지', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final base = baseOf(scene), y = base + 14;
    final tint = rgbAt(px, xAt(scene, 150), base + 20);
    expect(rgbAt(px, xAt(scene, 450), base + 20), tint, reason: '칸 바탕은 몸통 칠 그대로(지도자 칸은 칠 없음)');
    final ink = inked(tint, .25);
    for (final x in const <double>[560, 600, 690]) {
      expect(near(rgbAt(px, xAt(scene, x), y), ink), isTrue, reason: '겹친 조각 $x의 단 사이 금 ${rgbAt(px, xAt(scene, x), y).toRadixString(16)}');
    }
    for (final x in const <double>[150, 450, 800, 1200]) {
      expect(rgbAt(px, xAt(scene, x), y), tint, reason: '혼자인 조각 $x에는 단 사이 금이 없다');
    }
    final c550 = xAt(scene, 550).roundToDouble(), c700 = xAt(scene, 700).roundToDouble();
    expect(near(rgbAt(px, c550, y), ink), isTrue, reason: '왼쪽 끝 열(다빈 칸 금의 열)까지');
    expect(near(rgbAt(px, c700, y), ink), isTrue, reason: '오른쪽 끝 열(온결 칸 금의 열)까지');
    expect(rgbAt(px, c550 - 1, y), tint);
    expect(rgbAt(px, c700 + 1, y), tint);
    // 10px 겹침(1290 ~ 1300)에도 단 사이 금.
    expect(near(rgbAt(px, xAt(scene, 1295), y), ink), isTrue);
    expect(painter.debugSink.notes['단금']?.length, 2, reason: '겹친 조각 둘 — 띠 전체를 가로지르는 금은 없다');
  });

  test('칸 금 — 칸의 시작 · 끝에서 그 조각 안 제 자리에만 · 위아래 가로 금에 닿음(들임 없음) · 같은 열은 한 번', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final base = baseOf(scene);
    final tint = rgbAt(px, xAt(scene, 150), base + 20), ink = inked(tint, .25);
    bool inkAt(double col, double y) => near(rgbAt(px, col, y), ink);
    // 서하 · 온결 경계(400 — 둘 다 층 전체): 머리 색줄 아랫금(층 윗변 − 1) 바로 밑부터 층 아랫금(+ 28) 바로 위까지.
    final c400 = xAt(scene, 400).roundToDouble();
    for (double y = base; y < base + 28; y++) {
      expect(inkAt(c400, y), isTrue, reason: '400 칸 금 y + ${y - base} ${rgbAt(px, c400, y).toRadixString(16)}');
    }
    expect(rgbAt(px, c400, base - 1), rgbAt(px, xAt(scene, 150), base - 1), reason: '위 가로 금(머리 색줄 아랫금) 그대로');
    expect(rgbAt(px, c400, base + 28), rgbAt(px, xAt(scene, 150), base + 28), reason: '아래 가로 금(칸 뭉치 아랫금) 그대로');
    // 온결 끝(700 — 겹친 조각의 단 0): 단 0 자리에만(+ 0 ~ + 13) · 단 1(다빈이 이어짐 — 이음매)에는 없음.
    final c700 = xAt(scene, 700).roundToDouble();
    for (double y = base; y < base + 14; y++) {
      expect(inkAt(c700, y), isTrue, reason: '700 단 0 y + ${y - base}');
    }
    for (double y = base + 15; y < base + 28; y++) {
      expect(rgbAt(px, c700, y), tint, reason: '700 단 1은 다빈의 이음매 y + ${y - base}');
    }
    // 다빈 시작(550 — 겹친 조각의 단 1): 단 1 자리에만(+ 15 ~ + 27) · 단 0(온결이 이어짐)에는 없음.
    final c550 = xAt(scene, 550).roundToDouble();
    for (double y = base + 15; y < base + 28; y++) {
      expect(inkAt(c550, y), isTrue, reason: '550 단 1 y + ${y - base}');
    }
    for (double y = base; y < base + 14; y++) {
      expect(rgbAt(px, c550, y), tint, reason: '550 단 0은 온결의 이음매 y + ${y - base}');
    }
    // 다빈 끝 · 무령 시작(900 — 둘 다 층 전체): 한 열에 한 번(겹쳐 짙어지지 않음).
    final c900 = xAt(scene, 900).roundToDouble();
    for (final y in [base, base + 14, base + 27]) {
      expect(inkAt(c900, y), isTrue, reason: '900 y + ${y - base}');
    }
    expect(rgbAt(px, c900 - 1, base + 20), tint);
    expect(rgbAt(px, c900 + 1, base + 20), tint, reason: '이웃 열에 겹금 없음');
    // 섭정 칸 끝(1050)에는 칸 금이 없다 — 섭정은 칸이 아니다(걸음 3).
    expect(rgbAt(px, xAt(scene, 1050).roundToDouble(), base + 20), tint);
  });

  test('이름 — 칸이 시작하는 조각부터 이름과 여백이 드는 첫 조각의 제 자리 가운데 · 칸마다 한 번', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final base = baseOf(scene);
    final labels = painter.debugLabels.where((l) => l.kind == 'cell').toList();
    ({double x, double y}) of(String name) {
      final hits = labels.where((l) => l.text == name).toList();
      expect(hits.length, 1, reason: '$name은 한 번만');
      return (x: hits.single.at.dx, y: hits.single.at.dy);
    }

    final textH = 8.5 * 1.2;
    // 온결: 첫 조각(400 ~ 550 · 혼자)에 든다 — 층 전체의 세로 가운데.
    final on = of('온결왕');
    expect(on.y, closeTo(base + 1 + (27 - textH) / 2, .05));
    expect(on.x, inInclusiveRange(xAt(scene, 400), xAt(scene, 475)));
    // 다빈: 첫 조각(550 ~ 700 · 겹친 단 1 · 150px)에 든다 — 제 단의 세로 가운데.
    final da = of('다빈왕');
    expect(da.y, closeTo(base + 15 + (13 - textH) / 2, .05));
    expect(da.x, inInclusiveRange(xAt(scene, 550), xAt(scene, 625)));
    // 단공: 첫 조각(1290 ~ 1300 · 10px)에는 들지 않아 다음 조각(1300 ~ 1450 · 혼자)의 층 전체 가운데.
    final dan = of('단공');
    expect(dan.y, closeTo(base + 1 + (27 - textH) / 2, .05));
    expect(dan.x, inInclusiveRange(xAt(scene, 1300), xAt(scene, 1375)));
    // 무령: 첫 조각(900 ~ 1290)의 층 전체 가운데.
    expect(of('무령왕').y, closeTo(base + 1 + (27 - textH) / 2, .05));
    // 한 단 띠의 이름은 지금 자리(지도자 층 윗변 + 1부터 13의 가운데).
    expect(of('외톨왕').y, closeTo(base + 1 + (13 - textH) / 2, .05));
  });

  test('셋 겹친 띠(세 단) — 맞닿은 겹친 조각의 단 사이 금은 한 줄로(경계 열이 두 번 칠해져 짙어지지 않음)', () async {
    // 가 0단 100 ~ 700 · 나 1단 200 ~ 600 · 다 2단 300 ~ 500 → 겹친 조각 200 ~ 300 · 300 ~ 500 · 500 ~ 600(맞닿음).
    final t = TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(1, 0, at(100), at(800), '물레 왕국', look: leaderLook, sub: 2 << 22)
      ..cell(10, 0, at(100), at(700), '가왕', style: st(0))
      ..cell(11, 0, at(200), at(600), '나왕', lane: 1, style: st(1))
      ..cell(12, 0, at(300), at(500), '다왕', lane: 2, style: st(2))
      ..item(57, 50, 0, at(200), at(600), a: 1, b: 1, c: 2, d: 3, ref: 1)
      ..item(57, 51, 0, at(300), at(500), a: 1, b: 2, c: 3, d: 3, ref: 1);
    final (scene, painter) = make(data: t.build(), lanes: 3);
    await settle(scene, painter);
    expect(scene.layout.geo(0).leaderLanes, 3);
    final px = await pixelsOf(painter);
    final base = baseOf(scene);
    final tint = rgbAt(px, xAt(scene, 150), base + 20), ink = inked(tint, .25);
    for (final y in [base + 14, base + 28]) {
      for (final x in const <double>[250, 300, 400, 500, 550]) {
        final col = xAt(scene, x).roundToDouble();
        expect(near(rgbAt(px, col, y), ink), isTrue, reason: '$x 열 · y + ${y - base} ${rgbAt(px, col, y).toRadixString(16)}');
      }
    }
    expect(painter.debugSink.notes['단금']?.length, 2, reason: '단 사이 금 둘(1 · 2) × 이어 그은 한 줄');
    // 가: 혼자인 100 ~ 200 · 600 ~ 700은 층 전체(3 × 14 − 1).
    final cells = cellsOf(painter).where((n) => n.kind == 1 && n.lane == 0).toList();
    expect(cells.where((n) => n.h > 40).length, 2);
  });

  test('같은 줄 왼쪽의 한 단 띠 — 두 단 띠의 조각을 먼저 그려도 그 이름이 비킴에 막히지 않음 · 섭정 칸은 겹침에 들지 않음', () async {
    final (scene, painter) = make(data: wardTile());
    await settle(scene, painter);
    final base = baseOf(scene);
    final labels = painter.debugLabels.where((l) => l.kind == 'cell').toList();
    final names = {for (final l in labels) l.text};
    expect(names, containsAll(['외톨왕', '가왕', '나왕', '무령왕', '단공']));
    final ga = labels.firstWhere((l) => l.text == '가왕');
    expect(ga.at.dy, closeTo(base + 1 + (13 - 8.5 * 1.2) / 2, .05), reason: '가왕은 겹친 조각의 단 0(제 단 열쇠)');
    final cells = cellsOf(painter).where((n) => n.kind == 1).toList();
    Noted piece(double px, int lane) => cells.firstWhere((n) => n.lane == lane && (n.l - xAt(scene, px)).abs() < 1.5, orElse: () => fail('조각 $px · 단 $lane 없음'));
    expect([piece(800, 0).t, piece(800, 0).h], [base + 1, 27], reason: '무령 800 ~ 1000(혼자 — 섭정은 겹침이 아님)');
    expect([piece(1000, 0).t, piece(1000, 0).h], [base + 1, 13], reason: '무령 1000 ~ 1200(단공과 겹침)');
    expect([piece(1000, 1).t, piece(1000, 1).h], [base + 15, 13], reason: '단공 1000 ~ 1200');
    // 섭정 칸: 경계를 만들지 않고(900 · 1100에서 끊긴 무령 조각 없음) 칸으로 그리지 않는다(걸음 3 — 피후견 칸의 밑줄) — 1000 ~ 의 단 0은 무령 하나.
    expect(cells.where((n) => (n.l - xAt(scene, 900)).abs() < 1.5), isEmpty, reason: '900(섭정 시작)에 칸 · 조각 없음');
    expect(cells.where((n) => n.lane == 0 && n.h < 14 && (n.l - xAt(scene, 1000)).abs() < 1.5).length, 1, reason: '무령 1000 ~ 의 단 0만');
    expect(cells.where((n) => (n.l - xAt(scene, 1100)).abs() < 1.5), isEmpty, reason: '1100(섭정 끝)에서 끊긴 조각 없음');
    expect(names, isNot(contains('태후')), reason: '섭정 칸의 이름은 그리지 않는다');
    expect(painter.debugSink.notes['단금']?.length, 2, reason: '겹친 조각 420 ~ 700 · 1000 ~ 1200');
  });

  test('한 단 띠는 같은 줄에서도 지금 길 — 몸통은 제 단만큼(사건 칸이 14 올라감)', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final layout = scene.layout;
    expect(painter.bands.eventLiftOf(layout, 0, 2), G.floor, reason: '외톨 왕국 — 남는 단 14만큼');
    expect(painter.bands.eventLiftOf(layout, 0, 1), 0, reason: '하연 왕국 — 제 단 둘');
  });

  test('스위치 legit을 끄면 예전 픽셀 — 두 단 비트가 없는 줄과 바이트 같음 · 모든 지도자 칸이 층 윗변 + 1부터 13', () async {
    final (offScene, offPainter) = make(legit: false);
    await settle(offScene, offPainter);
    final off = await pixelsOf(offPainter);
    PaintPick.reset();
    // 견줌도 스위치 끔(걸음 3의 무늬 — 섭정 밑줄 · 주장 빗금 — 는 한 단 줄에서도 그리므로).
    final (plainScene, plainPainter) = make(lanes: 1, legit: false);
    await settle(plainScene, plainPainter);
    final plain = await pixelsOf(plainPainter);
    expect(offScene.layout.geo(0).leaderLanes, 1);
    expect(off, plain, reason: '스위치를 끈 두 단 줄 = 두 단 비트 없는 줄(조각을 그리지 않는 지금 길)');
    final base = baseOf(offScene);
    for (final n in cellsOf(offPainter).where((n) => n.kind == 1)) {
      expect([n.t, n.h], [base + 1, 13], reason: '단 ${n.lane}의 칸 ${n.l}');
    }
    expect(offPainter.debugSink.notes['단금'], isNull);
  });

  // ──────────── 걸음 3 — 칸의 정통성 무늬(lg2-ga · 구역 57) ────────────

  test('섭정(두 단 띠 · 층 전체 조각) — 칸 · 이름 · 금 없이 피후견 칸 아랫변 안쪽 2px 먹 60 · 칸 금 오른쪽 화소부터 · 누름은 섭정 칸', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final base = baseOf(scene), tint = rgbAt(px, xAt(scene, 150), base + 20);
    // 태후 서리 900 ~ 1050 — 피후견 칸 무령(900 ~ 1290 혼자 → 층 전체 27): 밑줄은 층 아랫금(+ 28) 바로 위 두 줄(+ 26 · + 27).
    final c900 = xAt(scene, 900).roundToDouble(), c1050 = xAt(scene, 1050).roundToDouble();
    for (final y in [base + 26, base + 27]) {
      for (final x in [c900 + 1, xAt(scene, 960), c1050 - 1]) {
        expect(rgbAt(px, x, y), regentInk, reason: '밑줄 ($x, y + ${y - base})');
      }
      expect(rgbAt(px, c1050, y), tint, reason: '섭정 끝 열 밖은 비었다');
    }
    expect(near(rgbAt(px, c900, base + 27), inked(tint, .25)), isTrue, reason: '칸 금(900 — 다빈 끝 · 무령 시작)은 그대로 — 밑줄은 그 오른쪽 화소부터');
    expect(rgbAt(px, xAt(scene, 960), base + 25), tint, reason: '밑줄은 두 줄뿐');
    expect(painter.debugSink.notes['섭정밑줄']?.length, 1);
    expect(painter.debugLabels.where((l) => l.text == '태후 서리'), isEmpty, reason: '섭정 칸의 이름은 그리지 않는다');
    // 누름: 밑줄 자리 둘레(밑줄 위 3px까지)는 섭정 칸, 그 위는 피후견 칸.
    final hit = painter.strips.hitStrips;
    expect([hit(xAt(scene, 960), base + 25)?.ref, hit(xAt(scene, 960), base + 25)?.name], ['leader:4', '태후 서리']);
    expect(hit(xAt(scene, 960), base + 27)?.ref, 'leader:4');
    expect(hit(xAt(scene, 960), base + 20)?.ref, 'leader:3', reason: '밑줄 위는 무령');
  });

  test('섭정(두 단 띠 · 조각을 건넘) — 조각마다 피후견 칸의 제 자리: 혼자인 조각은 층 아랫변 · 겹친 조각은 제 단(단 0) 아랫변', () async {
    final (scene, painter) = make(data: wardTile());
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final base = baseOf(scene);
    // 태후 900 ~ 1100 · 무령 800 ~ 1300(단 0) — 800 ~ 1000은 무령 혼자(층 전체 → + 26 · + 27), 1000 ~ 1200은 단공과 겹침(단 0 → + 12 · + 13).
    for (final y in [base + 26, base + 27]) {
      expect(rgbAt(px, xAt(scene, 950), y), regentInk, reason: '900 ~ 1000 층 아랫변 y + ${y - base}');
      expect(rgbAt(px, xAt(scene, 1050), y), isNot(regentInk), reason: '1000 ~ 은 층 아랫변이 아니다(단공의 단)');
    }
    for (final y in [base + 12, base + 13]) {
      expect(rgbAt(px, xAt(scene, 1050), y), regentInk, reason: '1000 ~ 1100 단 0 아랫변 y + ${y - base}');
      expect(rgbAt(px, xAt(scene, 950), y), isNot(regentInk), reason: '900 ~ 1000은 단 0 아랫변이 아니다');
    }
    final c1000 = xAt(scene, 1000).roundToDouble(), c1100 = xAt(scene, 1100).roundToDouble();
    expect(rgbAt(px, c1000 - 1, base + 27), regentInk, reason: '층 전체 몫은 단공 칸 금 앞까지');
    expect(rgbAt(px, c1000, base + 27), isNot(regentInk), reason: '단공 칸 금(+ 15 ~ + 27) 화소는 비킨다');
    expect(rgbAt(px, c1000, base + 13), regentInk, reason: '단 0 몫은 이음매 열부터(단 0에는 칸 금이 없다)');
    expect(rgbAt(px, c1100 - 1, base + 13), regentInk);
    expect(rgbAt(px, c1100, base + 13), isNot(regentInk), reason: '섭정 끝');
    expect(painter.debugSink.notes['섭정밑줄']?.length, 2, reason: '조각마다 하나');
    expect(painter.strips.hitStrips(xAt(scene, 1050), base + 11)?.ref, 'leader:2', reason: '단 0 밑줄 둘레도 섭정 칸');
  });

  test('섭정(한 단 띠) — 층 아랫변 안쪽 2px · 칸이 아니라 무리의 빈틈을 메우지 않음 · 누름은 섭정 칸', () async {
    final (scene, painter) = make(data: oneLaneTile(), lanes: 1);
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final base = baseOf(scene), tint = rgbAt(px, xAt(scene, 130), base + 7);
    expect(scene.layout.geo(0).leaderLanes, 1);
    final cells = cellsOf(painter).where((n) => n.kind == 1).toList();
    expect(cells.where((n) => (n.l - xAt(scene, 500)).abs() < 1.5), isEmpty, reason: '섭정 칸(500 ~ 700)은 칸이 아니다');
    // 둘째공(400 ~ 850)은 빈틈(850 ~ 870)을 건너 셋째공에 잇지 않는다 — 건너뛴 순번 2가 섭정 칸이라 빠진 칸이 아니다.
    final second = cells.firstWhere((n) => (n.l - xAt(scene, 400)).abs() < 1.5);
    expect(second.r, closeTo(xAt(scene, 850) - .5, .06), reason: '둘째공 끝 그대로(셋째공 시작까지 늘이지 않음)');
    // 밑줄: 층(+ 1 ~ + 14)의 아래 두 줄 + 12 · + 13 — 이름(둘째공 · 가운데 625 언저리)을 비킨 자리에서 본다.
    final c500 = xAt(scene, 500).roundToDouble(), c700 = xAt(scene, 700).roundToDouble();
    for (final y in [base + 12, base + 13]) {
      for (final x in [c500, xAt(scene, 540), xAt(scene, 690), c700 - 1]) {
        expect(rgbAt(px, x, y), regentInk, reason: '($x, y + ${y - base})');
      }
      expect(rgbAt(px, c500 - 1, y), tint);
      expect(rgbAt(px, c700, y), tint);
    }
    expect(rgbAt(px, xAt(scene, 540), base + 11), tint);
    expect(painter.debugLabels.where((l) => l.text == '태비 아란'), isEmpty);
    final hit = painter.strips.hitStrips;
    expect([hit(xAt(scene, 540), base + 12)?.ref, hit(xAt(scene, 540), base + 12)?.name], ['leader:2', '태비 아란']);
    expect(hit(xAt(scene, 540), base + 5)?.ref, 'leader:1', reason: '밑줄 위는 피후견 칸(둘째공)');
  });

  test('명목 — 이름 먹 45 · 옛 명목 지도자(29비트 · 단체 켬의 .5)와 함께면 옅은 쪽', () async {
    final (scene, painter) = make(data: oneLaneTile(), lanes: 1);
    await settle(scene, painter);
    final notes = [for (final v in painter.debugSink.notes['명목정통'] ?? const <Object>[]) '$v'];
    expect(notes, contains('0 둘째공 ${(LegitLook.nominalName & 0xffffff).toRadixString(16)}'));
    // 넷째공: 옛 명목(이름 색을 종이와 반씩)과 먹 45 가운데 밝은 쪽.
    final old = mixSrgb(over(mixSrgb(0xffa0bcc5, Look.ink, .30), Look.paper), Look.paper, .5);
    int sum(int c) => ((c >> 16) & 0xff) + ((c >> 8) & 0xff) + (c & 0xff);
    final want = sum(old) > sum(LegitLook.nominalName) ? old : LegitLook.nominalName;
    expect(notes, contains('0 넷째공 ${(want & 0xffffff).toRadixString(16).padLeft(6, '0')}'));
    expect(LegitLook.nominalName, CanvasInk.k45);
    expect(notes.where((n) => n.contains('셋째공')), isEmpty, reason: '주장 칸은 이름 그대로');
  });

  test('주장(한 단 띠) — 칸 바탕에만 1px 화소 빗금(5px 계단 · 먹 25 · 칸 금 · 층 금 비킴) · 이름 앞 4 ~ 이름 끝 + 4는 받침', () async {
    final (scene, painter) = make(data: oneLaneTile(), lanes: 1);
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final base = baseOf(scene), tint = rgbAt(px, xAt(scene, 130), base + 7);
    // 셋째공 870 ~ 1300: 이름(가운데 1085)을 비킨 900 ~ 940의 층 안 전체(+ 1 ~ + 13).
    expectHatch(scene, px, xAt(scene, 900).round(), xAt(scene, 940).round(), base + 1, base + 14, tint, base, '셋째공 바탕');
    // 층 윗금 · 아랫금 줄은 그대로(빗금은 칸 안만).
    for (final y in [base, base + 14]) {
      for (int x = xAt(scene, 900).round(); x < xAt(scene, 940).round(); x++) {
        expect(rgbAt(px, x, y), rgbAt(px, xAt(scene, 200).round(), y), reason: '($x, y + ${y - base}) 층 금 그대로');
      }
    }
    // 칸 금 화소(셋째공의 왼쪽 · 넷째공과 이은 오른쪽)는 빗금이 덮지 않는다.
    final left = (xAt(scene, 870) + .5).roundToDouble();
    for (int y = (base + 2).round(); y < base + 13; y++) {
      expect(near(rgbAt(px, left, y), inked(tint, .25)), isTrue, reason: '칸 금 y + ${y - base}');
    }
    // 이름 받침: 이름 왼쪽 − 4 ~ 오른쪽 + 4는 빗금 없음(글자 위 줄 + 1에서 봄) · 그 밖은 빗금.
    final name = painter.strips.drawnCell(1, 'leader:3')!;
    expect(name.textW, greaterThan(0));
    final gl = (name.textL - LegitLook.namePad).floor(), gr = (name.textL + name.textW + LegitLook.namePad).ceil();
    for (int x = gl; x < gr; x++) {
      expect(rgbAt(px, x, base + 1), tint, reason: '받침 ($x)');
    }
    expectHatch(scene, px, gl - 10, gl, base + 1, base + 2, tint, base, '받침 왼쪽');
    expectHatch(scene, px, gr, gr + 10, base + 1, base + 2, tint, base, '받침 오른쪽');
    expect(painter.debugSink.notes['주장칸']?.length, 1);
  });

  test('주장(두 단 띠) — 겹친 조각(제 단)은 칸 바탕 전체 · 이름은 이름이 든 조각에만 받침 · 무늬는 층 윗선에 붙어 단이 달라도 한 무늬', () async {
    final (scene, painter) = make();
    await settle(scene, painter);
    final px = await pixelsOf(painter);
    final base = baseOf(scene), tint = rgbAt(px, xAt(scene, 150), base + 20);
    // 단공(주장): 1290 ~ 1300은 무령과 겹친 단 1(+ 15 ~ + 27 · 칸 금 열 1290은 비킴) — 이름 없음 · 빗금만.
    final c1290 = xAt(scene, 1290).roundToDouble(), c1300 = xAt(scene, 1300).roundToDouble();
    expectHatch(scene, px, c1290 + 1, c1300, base + 15, base + 28, tint, base, '겹친 조각(단 1)');
    // 1300 ~ 1450은 혼자(층 전체 + 1 ~ + 27) — 이름(가운데 1375)의 받침 밖 1400 ~ 1440은 빗금.
    expectHatch(scene, px, xAt(scene, 1405).round(), xAt(scene, 1440).round(), base + 1, base + 28, tint, base, '혼자인 조각(층 전체)');
    final name = painter.strips.drawnCell(1, 'leader:5')!;
    for (int x = (name.textL - 4).floor(); x < name.textL + name.textW + 4; x++) {
      expect(rgbAt(px, x, base + 1), tint, reason: '받침 ($x)');
    }
    // 공동(다빈)은 무늬가 없다 — 700 ~ 900 혼자인 조각은 칠 그대로(이름을 비킨 자리).
    for (int x = xAt(scene, 860).round(); x < xAt(scene, 890).round(); x++) {
      expect(rgbAt(px, x, base + 3), tint, reason: '공동은 무늬 없음 ($x)');
    }
  });

  test('구역 57이 없는 타일은 이 길을 지나지 않는다 · 스위치 legit을 끄면 구역 57을 보지 않는다(섭정도 예전 꼴의 칸)', () async {
    final (plain, plainPainter) = make(data: oneLaneTile(legits: false), lanes: 1);
    await settle(plain, plainPainter);
    final none = await pixelsOf(plainPainter);
    PaintPick.reset();
    final (off, offPainter) = make(data: oneLaneTile(), lanes: 1, legit: false);
    await settle(off, offPainter);
    final offPx = await pixelsOf(offPainter);
    expect(offPx, none, reason: '스위치 끔(구역 57 있음) = 구역 57 없는 타일(스위치 켬)');
    for (final key in ['섭정밑줄', '주장칸', '명목정통']) {
      expect(plainPainter.debugSink.notes[key], isNull, reason: key);
      expect(offPainter.debugSink.notes[key], isNull, reason: key);
    }
    expect(cellsOf(offPainter).where((n) => n.kind == 1 && (n.l - xAt(off, 500)).abs() < 1.5).length, 1, reason: '끄면 섭정 칸도 칸(예전)');
  });

  // 빽빽한 칸(칸 그림 갈래 검토 고침 — 두 단 조각의 문턱): 지도자 칸이 한 칸에 6px도 못 되면 층 전체(두 단 27)를 빽빽한 칸 하나로. 칸 수는 단마다
  // (서고 미리보기 `_cells`가 단마다 `seen`) — 화면 안 그 띠의 단마다 센 수([_countLeaders])와 이 타일의 단마다 보이는 수 가운데 큰 값 · 섭정 칸은 세지 않는다.
  // 하연 왕국 100 ~ 400(칸 상자 안 폭 298 — (298 − 6) ÷ 수 < 6이면 빽빽: 49칸부터).
  group('빽빽한 칸 — 두 단 띠 조각', () {
    /// 단 0에 [lane0]칸 · 단 1에 [lane1]칸을 [from] ~ [to] px에 고르게(순번은 단 0부터 이어서). [regentAt]이 있으면 단 0의 그 자리(px)에 섭정 칸
    /// (30px · 구역 57 d = 4 — [legits]가 거짓이면 구역 없이 보통 칸).
    void cellsInto(TileBuilder t, {required int lane0, required int lane1, double from = 100, double to = 400, double? regentAt, bool legits = true, int firstId = 100}) {
      var id = firstId, seq = 0;
      final lane0Cells = <(double, double, String, bool)>[
        for (int k = 0; k < lane0; k++) (from + (to - from) * k / lane0, from + (to - from) * (k + 1) / lane0, '왕 $k', false),
        if (regentAt != null) (regentAt, regentAt + 30, '태후', true),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      for (final (a, b, name, regent) in lane0Cells) {
        t.cell(id++, 0, at(a), at(b), name, style: st(seq));
        if (regent && legits) t.item(57, 900 + seq, 0, at(a), at(b), a: 1, b: 0, c: seq + 1, d: 4, ref: 1);
        seq++;
      }
      for (int k = 0; k < lane1; k++) {
        t.cell(id++, 0, at(from + (to - from) * k / lane1), at(from + (to - from) * (k + 1) / lane1), '공동 $k', lane: 1, style: st(seq++));
      }
    }

    Uint8List denseTile({required int lane0, required int lane1, double? regentAt, bool legits = true}) {
      final t = TileBuilder(level: 9, x: 0, chunk: 0)..band(1, 0, at(100), at(400), '하연 왕국', look: leaderLook, sub: twoLanes);
      cellsInto(t, lane0: lane0, lane1: lane1, regentAt: regentAt, legits: legits);
      return t.build();
    }

    List<String> dense(TimelinePainter p) => [for (final v in p.debugSink.notes['빽빽'] ?? const <Object>[]) '$v'];

    test('단마다 센다 — 단 0 · 단 1이 30칸씩(합 60)이면 낱칸 · 단 하나가 50칸이면 층 전체(27)를 빽빽한 칸 하나', () async {
      final (scene, painter) = make(data: denseTile(lane0: 30, lane1: 30));
      await settle(scene, painter);
      expect(scene.layout.geo(0).leaderLanes, 2);
      expect(dense(painter), isEmpty, reason: '단마다 30칸 — (298 − 6) ÷ 30 ≥ 6(두 단을 합쳐 세면 60칸이라 빽빽해졌다)');
      final cells = cellsOf(painter).where((n) => n.kind == 1).toList();
      expect(cells.where((n) => n.lane == 0).length, 30);
      expect(cells.where((n) => n.lane == 1).length, 30);

      final (scene2, painter2) = make(data: denseTile(lane0: 50, lane1: 2));
      await settle(scene2, painter2);
      final base = baseOf(scene2), l = xAt(scene2, 100) + 1, r = xAt(scene2, 400) - 1;
      expect(dense(painter2), ['1:1:-1 ${(l * 10).round()},${((base + 1) * 10).round()},${((r - l) * 10).round()},270'], reason: '층 전체 · 띠 하나에 한 번');
      expect(cellsOf(painter2).where((n) => n.kind == 1), isEmpty, reason: '빽빽한 칸이면 낱칸 · 조각이 없다');
    });

    test('섭정 칸은 수에 들지 않는다 — 단 0의 48칸 + 섭정 1이면 낱칸 · 같은 칸을 구역 57 없이(보통 칸 49)면 빽빽', () async {
      final (scene, painter) = make(data: denseTile(lane0: 48, lane1: 1, regentAt: 250));
      await settle(scene, painter);
      expect(dense(painter), isEmpty, reason: '섭정은 층을 세우지 않는다 — 48칸');
      expect(painter.debugSink.notes['섭정밑줄'], isNotNull, reason: '섭정 칸이 섭정으로 읽혔다');
      final (scene2, painter2) = make(data: denseTile(lane0: 48, lane1: 1, regentAt: 250, legits: false));
      await settle(scene2, painter2);
      expect(dense(painter2).length, 1, reason: '49칸');
    });

    test('타일 둘에 걸친 띠 — 칸 수는 띠 전체(타일마다 25칸 · 띠 50칸이면 빽빽) · 빽빽한 칸은 한 번 · 칸이 한 타일에만 있어도 띠 상자 전체', () async {
      // 단계 9의 타일 하나 = 8192px — 타일 0 끝(8192)이 화면 x 840에 오게 본다. 띠 8042 ~ 8342(칸 상자 안 폭 298 — 49칸부터 빽빽).
      Future<(TimelineScene, TimelinePainter)> twoTiles({required bool split}) async {
        final t0 = TileBuilder(level: 9, x: 0, chunk: 0)..band(1, 0, at(8042), at(8192), '하연 왕국', look: leaderLook, sub: twoLanes, flags: Tile.clipRight);
        final t1 = TileBuilder(level: 9, x: 1, chunk: 0)..band(1, 0, at(0), at(150), '하연 왕국', look: leaderLook, sub: twoLanes, flags: Tile.clipLeft);
        if (split) {
          cellsInto(t0, lane0: 25, lane1: 0, from: 8042, to: 8192);
          cellsInto(t1, lane0: 25, lane1: 0, from: 0, to: 150, firstId: 200);
        } else {
          cellsInto(t1, lane0: 50, lane1: 1, from: 0, to: 150);
        }
        final tile0 = t0.build(), tile1 = t1.build();
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
          fetchTile: (level, x, chunk, packs) async =>
              level == 9 && chunk == 0 && x == 0 ? tile0 : (level == 9 && chunk == 0 && x == 1 ? tile1 : TileBuilder(level: level, x: x, chunk: chunk).build()),
        );
        addTearDown(scene.dispose);
        final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
        await settle(scene, painter);
        return (scene, painter);
      }

      for (final split in [true, false]) {
        final (scene, painter) = await twoTiles(split: split);
        expect(scene.controller.view.xOf(at(8192)), closeTo(840, 1e-6));
        final l = scene.controller.view.xOf(at(8042)) + 1, r = scene.controller.view.xOf(at(8342)) - 1;
        final notes = dense(painter);
        expect(notes.length, 1, reason: '띠 하나에 한 번(split $split)');
        expect(notes.single, startsWith('1:1:-1 ${(l * 10).round()},'), reason: '띠 상자 왼쪽부터(split $split)');
        expect(notes.single, contains(',${((r - l) * 10).round()},270'), reason: '띠 상자 전체 폭 · 층 전체(split $split)');
        expect(cellsOf(painter).where((n) => n.kind == 1), isEmpty, reason: 'split $split');
      }
    });
  });

  // ──────────── 구분선 갈래와 합침(4단계 마지막 합치기 — 감독 결정 2026-10-25 '층 사이 가로선 b' · '모든 가로세로 구분선은 맞닿게') ────────────
  // 두 단 띠의 조각 길(칸 그림 갈래)이 구분선 갈래의 셈을 따른다: 칸 금 · 단 사이 금의 먹은 한 단 띠의 칸 금과 같은 셈(꼴 b만 먹 12 — FloorRuleLook.dividerOf),
  // 칸 층 가로선은 층 전체(층 윗선 · 제 단 수 × 14) 기준으로 한 번(조각 무리마다 모아도 같은 줄은 한 선 · 단 사이 금 줄에는 없음), 칸 금은 위아래 가로 금에
  // 맞닿고(가로 금 줄은 칠하지 않음), 섭정 밑줄은 늘어난 칸 금 범위까지 비킨다. 꼴 off는 위 시험들(칸 그림 갈래 그대로 — 구분선 갈래 전 그림)과 같다.
  group('구분선 갈래와 합침 — 두 단 띠 조각(꼴 a · b · c · off)', () {
    for (final rule in FloorRule.values) {
      test('꼴 ${rule.name}: 칸 금 · 단 사이 금의 먹(b만 12) · 칸 금은 위아래 가로 금에 맞닿음 · 가로선은 층 윗선 · 아랫선의 칸 자리에만 · 섭정 밑줄은 칸 금 오른쪽부터', () async {
        final (scene, painter) = make(rows: rule);
        await settle(scene, painter);
        final px = await pixelsOf(painter);
        final base = baseOf(scene), tint = rgbAt(px, xAt(scene, 150), base + 20);
        final ink = inked(tint, rule == FloorRule.b ? CanvasInk.a12 : CanvasInk.a25);
        // 칸 금(서하 · 온결 경계 400 — 둘 다 층 전체): 층 윗변(머리 색줄 아랫금 바로 밑)부터 층 아랫금 바로 위까지 틈 없이 · 가로 금 줄은 칸 금이 덧칠하지 않음.
        final c400 = xAt(scene, 400).roundToDouble();
        for (double y = base; y < base + 28; y++) {
          expect(near(rgbAt(px, c400, y), ink), isTrue, reason: '400 칸 금 y + ${y - base} ${rgbAt(px, c400, y).toRadixString(16)}');
        }
        // 가로 금 줄(위 — 머리 색줄 아랫금 · 아래 — 칸 뭉치 아랫금)은 칸 금이 덧칠하지 않는다(먹 한 번): 그 열의 화소가 같은 줄 이웃 열(±3 — 꼴 c 점선의
        // 한 주기)의 빛깔 가운데 하나.
        for (final y in [base - 1, base + 28]) {
          final seen = {for (final d in const [-3, -2, -1, 1, 2, 3]) rgbAt(px, c400 + d, y)};
          expect(seen, contains(rgbAt(px, c400, y)), reason: '가로 금 줄 y ${y - base}의 칸 금 열 ${rgbAt(px, c400, y).toRadixString(16)} — 이웃 ${seen.map((v) => v.toRadixString(16))}');
        }
        // 겹친 조각의 칸 금(온결 끝 700 — 단 0): 단 사이 금 줄(+ 14) 바로 위까지 · 단 사이 금(550 ~ 700)은 칸 금과 같은 먹.
        final c700 = xAt(scene, 700).roundToDouble();
        for (double y = base; y < base + 14; y++) {
          expect(near(rgbAt(px, c700, y), ink), isTrue, reason: '700 단 0 y + ${y - base}');
        }
        for (final x in const <double>[560, 600, 690]) {
          expect(near(rgbAt(px, xAt(scene, x), base + 14), ink), isTrue, reason: '단 사이 금 $x ${rgbAt(px, xAt(scene, x), base + 14).toRadixString(16)}');
        }
        expect(painter.debugSink.notes['단금']?.length, 2, reason: '겹친 조각 둘');
        // 칸 층 가로선(기록 '층선' — 띠 · y×10 · x0×10,x1×10 · 밝기×1000).
        final rules = [for (final n in painter.debugSink.notes['층선'] ?? const <Object>[]) '$n'.split(' ')];
        if (rule == FloorRule.off) {
          expect(rules, isEmpty, reason: '꼴 off는 가로선이 없다');
        } else {
          final mine = [for (final r in rules) if (r[0] == '1') (y: int.parse(r[1]) / 10, x0: int.parse(r[2].split(',')[0]) / 10, x1: int.parse(r[2].split(',')[1]) / 10)];
          expect({for (final r in mine) r.y}, {(base - 1).floorToDouble(), (base + 28).floorToDouble()},
              reason: '하연 왕국의 가로선은 층 윗선(첫 층 — 머리 색줄 아랫금 줄) · 층 아랫선뿐 — 단 사이 금 줄(+ 14)에는 없다');
          bool covered(double y, double px0) => mine.any((r) => r.y == y.floorToDouble() && r.x0 <= xAt(scene, px0) && r.x1 > xAt(scene, px0));
          for (final y in [base - 1, base + 28]) {
            for (final x in const <double>[150, 450, 600, 800, 1000, 1295, 1400, 1480]) {
              expect(covered(y, x), isTrue, reason: '칸 자리 $x · y ${y - base}의 가로선');
            }
            expect(covered(y, 1455), isFalse, reason: '칸이 없는 자리(단공 끝 1450 ~ 하늘 시작 1460)에는 긋지 않는다');
            expect(mine.where((r) => r.y == y.floorToDouble()).length, lessThanOrEqualTo(3), reason: '같은 줄은 합쳐 한 선(조각 무리마다 나뉘지 않음)');
          }
        }
        // 섭정 밑줄(태후 서리 900 ~ 1050 — 피후견 무령의 층 전체 조각): 칸 금(900)은 그대로 · 밑줄은 그 오른쪽 화소부터(늘어난 칸 금 범위도 비킴).
        final c900 = xAt(scene, 900).roundToDouble();
        expect(near(rgbAt(px, c900, base + 27), ink), isTrue, reason: '칸 금 900 · y + 27');
        expect(rgbAt(px, c900 + 1, base + 27), regentInk, reason: '밑줄은 칸 금 오른쪽 화소부터');
      });
    }

    test('한 단 띠(여울 공국 — 주장 빗금 · 섭정 밑줄): 꼴 b면 칸 금이 먹 12로 위아래 가로 금에 맞닿고 빗금 · 밑줄은 늘어난 칸 금 범위를 비킨다', () async {
      final (scene, painter) = make(data: oneLaneTile(), lanes: 1, rows: FloorRule.b);
      await settle(scene, painter);
      final px = await pixelsOf(painter);
      final base = baseOf(scene), tint = rgbAt(px, xAt(scene, 130), base + 7), ink = inked(tint, CanvasInk.a12);
      // 칸 금의 열(한 단 띠는 칸 상자 끝의 반올림 열 — 이은 쪽은 앞 칸의 r − 1)을 경계 둘레 ±2에서 찾는다(층 가운데 줄에서 먹 12인 열).
      double colNear(double at0) {
        final c = xAt(scene, at0).roundToDouble();
        for (final d in const [0, -1, 1, -2, 2]) {
          if (near(rgbAt(px, c + d, base + 7), ink)) return c + d;
        }
        return fail('$at0 둘레에 칸 금 없음');
      }

      // 첫공 · 둘째공(400) · 둘째공 끝(850) · 셋째공 시작(870 — 주장 빗금 칸) · 셋째공 · 넷째공(1300): 층 윗변(머리 색줄 아랫금 바로 밑)부터 층 아랫금
      // 바로 위까지(+ 0 ~ + 13) 먹 12 하나 — 빗금 · 섭정 밑줄이 칸 금 열에 얹히지 않고(먹 한 번), 가로 금 줄(+ 14)은 칸 금이 덧칠하지 않는다.
      for (final at0 in const <double>[400, 850, 870, 1300]) {
        final col = colNear(at0);
        for (double y = base; y < base + 14; y++) {
          expect(near(rgbAt(px, col, y), ink), isTrue, reason: '$at0 칸 금(열 $col) y + ${y - base} ${rgbAt(px, col, y).toRadixString(16)}');
        }
      }
      expect(painter.debugSink.notes['주장칸']?.length, 1, reason: '주장 칸 빗금');
      expect(painter.debugSink.notes['섭정밑줄']?.length, 1, reason: '섭정 밑줄');
    });
  });
}

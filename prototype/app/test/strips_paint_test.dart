import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show BandLook, TagLook;
import 'package:archive_prototype/scene/paint/strips.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 띠 안의 단(칸)을 놓는 순수한 셈을 잰다: 단의 세로 자리 · 띠 안쪽 4px에 가두기 · 0.5px 틈과 이음 ·
// 예속 칸의 거꾸로 된 단 번호 · 이름이 들어갈 때만 · 모으는 도형의 수.
// 그림으로의 대조는 test/render_scene_test.dart(장면을 그림으로 떠서 지금 연표의 기준 그림과 나란히).

/// 단계 9에서 통 하나가 32px일 때의 1분 폭. 자리는 모두 '그림 영역 왼쪽에서 몇 px'로 적고 분으로 바꾼다.
final ppm = 32 / bucketMinutes(9);
double at(double px) => px / ppm;

/// 3판의 줄 하나(계약 3절의 값을 그대로 쌓게 kind 이하를 함께 준다).
Map<String, dynamic> row(int id, {int phase = 0, int rank = 0, double dep = 0, int organ = 1}) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': 4, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': phase, 'rank': rank, 'cats': <int>[],
  'fig': 0, 'dep': dep, 'zones': 0, 'hem': 0,
};

SceneLayout layout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xa0bcc5,
      'dynasty': 1, 'leader': 1, 'cabinet': 1, 'organ': 1, 'rail_levels': 2,
      'rows': [row(0, phase: 2, rank: 1, dep: 25), row(1)],
    },
  ],
});

/// style에 함께 실리는 값(계약 6-2): 비트 14 번갈아 짙기 · 15~26 순번 + 1.
int st(int style, {bool alt = false, int seq = -1}) => style | (alt ? 1 << 14 : 0) | ((seq < 0 ? 0 : seq + 1) << 15);

/// 한 타일에 띠 하나와 그 안의 여러 단.
Uint8List cells() {
  final t = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, at(100), at(1600), '첫불 성채국', color: 0xa0bcc5)
    // 왕조: 잇지 않는다(지금 연표는 왕조 칸에 layoutStrip을 쓰지 않는다) — 늘 0.5px씩 틈
    ..cell(1, 0, at(150), at(600), '유리항 깊은 왕조', kind: 0, style: st(0, seq: 0), color: 0xa0bcc5)
    ..cell(2, 0, at(600), at(1000), '은결 왕가', kind: 0, style: st(0, seq: 1), color: 0xc8b193)
    // 지도자: 둘째 · 셋째가 앞 칸과 같은 무리(style 4) — 틈 없이 하나의 긴 둥근 칸. 번갈아 짙기는 원래 목록의 홀수 번째
    ..cell(10, 0, at(150), at(400), '은결 나나나', kind: 1, style: st(0, seq: 0))
    ..cell(11, 0, at(400), at(700), '둘째 지도자', kind: 1, style: st(4, alt: true, seq: 1))
    ..cell(12, 0, at(700), at(1000), '셋째 지도자', kind: 1, style: st(4, seq: 2))
    // 시기: 체계 두 개(단 0 · 1). 이름은 "체계\t시기" 꼴 + style 32
    ..cell(20, 0, at(150), at(800), '장부 학파\t복구기', kind: 4, lane: 0, style: st(32, seq: 0))
    ..cell(21, 0, at(800), at(1400), '장부 학파\t안정기', kind: 4, lane: 0, style: st(32 | 4, seq: 1))
    ..cell(22, 0, at(150), at(1400), '물길 학파\t한 시기', kind: 4, lane: 1, style: st(32, seq: 2))
    // 지위: 서열 3(style에 (3+1) << 8)
    ..cell(30, 0, at(150), at(1400), '문지기', kind: 5, style: st(4 << 8, seq: 0))
    // 예속 안 칸: 단 0이 띠 아랫변에 가장 가깝다
    ..cell(40, 0, at(200), at(1200), '검은 인장 정부', kind: 7, lane: 0, style: st(1 << 11, seq: 0), color: 0xb1a0c9)
    ..cell(41, 0, at(200), at(1200), '흰 모래 연맹', kind: 7, lane: 1, style: st(2 << 11, seq: 1), color: 0xc9b1a0)
    // 구역 40 — 지도자 단의 모호한 구간(추정). 구역 41 — 둘째 지도자 칸의 이설 경계. 구역 43 — 왕조 칸이 가리키는 항목
    ..item(40, 1, 0, at(250), at(350), a: 1, b: 0, c: 0, d: 0, ref: 1)
    ..item(41, 2, 0, at(550), at(700), a: 1, b: 0, c: 0, d: 2, ref: 1)
    ..item(43, 3, 0, at(150), at(600), a: 0, b: 0, c: 1, ref: 1, name: '유리항 깊은 왕조', text2: 'moon/d-0')
    // 구역 42 — 둘째 · 셋째 지도자 칸이 같은 가문(가문 줄은 이어 붙은 두 칸에 한 가닥). 첫째 칸은 가문이 없다
    ..item(42, 4, 0, at(400), at(700), a: 1, b: 0, c: 2, ref: 1, name: '푸른달 가문', color: houseColor, text2: 'h-moon-1')
    ..item(42, 5, 0, at(700), at(1000), a: 1, b: 0, c: 3, ref: 1, name: '푸른달 가문', color: houseColor, text2: 'h-moon-1')
    // 구역 46 — 첫째 지도자 칸의 다른 표기(묘호 · 시호 · 이름 · 대수 3)
    ..item(46, 6, 0, at(150), at(400), a: 1, b: 0, c: 1, d: 4, ref: 1, name: '고요묘', text2: '맑은시호\t나나나');
  return t.build();
}

/// 견본 가문의 색(구역 42의 color — 0xRRGGBB).
const houseColor = 0x8b6f47;

/// 지금 연표의 해 좌표(정수 N = N년 1월 1일 · 기원전 1년 = −1 · 0은 빈 자리) → 1970년 기준 분(test/render_scene_test.dart와 같은 투영).
double minuteOfYear(double y) {
  final year = y.floor();
  final a = DateTime.utc(year < 0 ? year + 1 : year), b = DateTime.utc(year == -1 ? 1 : (year < 0 ? year + 2 : year + 1));
  return (a.millisecondsSinceEpoch + (b.millisecondsSinceEpoch - a.millisecondsSinceEpoch) * (y - year)) / 60000;
}

(TimelineScene, TimelinePainter) make({Uint8List? data, double Function()? clock, SceneLayout? shape}) {
  final controller = TimelineController()
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..setContentHeight(600);
  controller.showRange(0, at(1920 - SceneView.gutter));
  final tile = data ?? cells();
  final scene = TimelineScene(
    controller: controller,
    layout: shape ?? layout(),
    clock: clock,
    fetchTile: (level, x, chunk, packs) async =>
        level == 9 && x == 0 && chunk == 0 ? tile : (TileBuilder(level: level, x: x, chunk: chunk)).build(),
  );
  return (scene, painterOf(scene));
}

/// 이 파일의 검사는 **이름이 다 준비된 장면 하나**를 그려 놓고 잰다 — 그래서 글줄 준비의 예산을 풀어 둔 그리개를 쓴다(support/scene_text.dart).
/// 이 견본은 새 글줄이 64개라 예산(장면마다 40개 · 실제 시간 6ms) 그대로는 한 장면에 다 실리지 않고, 어느 이름까지 실리는지가
/// 그 순간 기기가 얼마나 바쁜지에 달렸다(다섯째 글줄인 '은결 나나나'도 앞의 글줄에서 6ms를 넘기면 빠졌다).
TimelinePainter painterOf(TimelineScene scene) => TimelinePainter(scene, text: unbudgetedText())..debug = true;

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
  // 이름이 덜 실린 장면을 재지 않게 못 박아 둔다 — 예산을 그대로 둔 그리개로 이 견본을 그리면 첫 장면이 늘 여기서 걸린다.
  expect(painter.text.starved, isFalse, reason: '글줄 준비가 모자란 장면이다 — 이름이 덜 실린 채 재게 된다([painterOf]로 지을 것)');
}

/// 장면을 그림으로 떠서 RGBA 바이트(1920×1080)를 돌려준다. 글줄 준비가 모자란 장면(starved)은 다 찰 때까지 다시 그린다.
Future<Uint8List> pixelsOf(TimelinePainter painter) async {
  ui.Picture? picture;
  for (int i = 0; i < 50; i++) {
    picture?.dispose();
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    picture = recorder.endRecording();
    if (!painter.text.starved) break;
  }
  final image = await picture!.toImage(1920, 1080);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// 그 픽셀(x · y는 배치 px — 배율 1)의 0xRRGGBBAA.
int pixelAt(Uint8List px, double x, double y) {
  final i = (y.floor() * 1920 + x.floor()) * 4;
  return px[i] << 24 | px[i + 1] << 16 | px[i + 2] << 8 | px[i + 3];
}

/// 0xAARRGGBB(불투명) → 그림이 돌려주는 0xRRGGBBAA.
int rgbaOf(int argb) => ((argb & 0x00ffffff) << 8 | 0xff) & 0xffffffff;

/// [after]가 [before] 위에 [rgb]를 [alpha]만큼 얹은 색인가(sRGB 섞기 · 채널마다 ±2).
void expectBlend(int after, int before, int rgb, double alpha, {String? reason}) {
  for (final shift in const [24, 16, 8]) {
    final b = (before >> shift) & 0xff, c = (rgb >> (shift - 8)) & 0xff, a = (after >> shift) & 0xff;
    expect(a, closeTo(b + (c - b) * alpha, 2), reason: '${reason ?? ''} 채널 ${shift ~/ 8}: ${before.toRadixString(16)} → ${after.toRadixString(16)}');
  }
}

/// 띠 0 안에서 [xs]의 어느 자리에도 칸이 없는 높이(칸 기록으로 고른다) — 조명 칠만 보이는 자리.
double freeY(TimelinePainter painter, List<double> xs) {
  final v = painter.scene.controller.view, layout = painter.scene.layout, geo = layout.geo(0);
  final top = v.yOf(layout.rowTop(0) + geo.bandTop);
  final cellsAt = notedCells(painter);
  for (double y = top + 3; y < top + geo.bandHeight - 3; y += 1) {
    final hit = cellsAt.any((n) => xs.any((x) => x >= n.l - 1 && x <= n.r + 1) && y >= n.t - 1 && y <= n.t + n.h + 1);
    if (!hit) return y + .5;
  }
  fail('칸이 없는 높이를 찾지 못했다');
}

Future<void> loadAll(TimelineScene scene) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
  }
}

/// 검사용 기록 '종류:줄:단 l,t,w,h'(0.1px 단위)를 풀어 본다.
class Noted {
  Noted(String text)
    : kind = int.parse(text.split(' ')[0].split(':')[0]),
      row = int.parse(text.split(' ')[0].split(':')[1]),
      lane = int.parse(text.split(' ')[0].split(':')[2]),
      l = int.parse(text.split(' ')[1].split(',')[0]) / 10,
      t = int.parse(text.split(' ')[1].split(',')[1]) / 10,
      w = int.parse(text.split(' ')[1].split(',')[2]) / 10,
      h = int.parse(text.split(' ')[1].split(',')[3]) / 10;
  final int kind, row, lane;
  final double l, t, w, h;
  double get r => l + w;
}

List<Noted> notedCells(TimelinePainter painter) =>
    [for (final v in painter.debugSink.notes['칸'] ?? const <Object>[]) Noted(v as String)];

List<String> noted(TimelinePainter painter, String kind) =>
    [for (final v in painter.debugSink.notes[kind] ?? const <Object>[]) '$v'];

/// 장면을 한 번 그리고 기록을 얻는다. 밝기는 장면의 [em.Emphasis]에 걸어 준다(그리는 쪽이 장면마다 층에 물려준다).
/// [flowMs]를 주면 밝기를 흐르게 두고 그만큼만 흘린 도중의 장면을 그린다(기간 조명의 진행 — 명세 06의 3-3).
/// [showAlt] · [showHouses] · [leaderLabel] · [leaderOrdinal]은 필터 시트의 표시 값이다(앱 틀이 `SceneMarks`에 적고 층이 장면마다 읽는다).
Future<TimelinePainter> drawn({
  em.Look? look,
  int density = 0,
  String? hot,
  double? flowMs,
  bool showAlt = true,
  bool showHouses = false,
  String leaderLabel = 'auto',
  bool leaderOrdinal = false,
  Set<String>? hotTwins,
}) async {
  final (scene, painter) = make();
  final flowing = flowMs != null;
  scene.controller.reduceMotion = !flowing; // 흐르는 도중의 값이 아니라 끝 값으로 재게(조명의 진행을 볼 때만 흐르게 둔다)
  if (density != 0) {
    scene.layout.setConditions(scene.layout.conditions.copyWith(density: density));
    scene.controller.setContentHeight(scene.layout.totalHeight);
  }
  painter.strips.hotCell = hot;
  // 표시 값은 앱 틀이 `SceneMarks`에 적고 층이 장면마다 읽는다 — 검사도 같은 길로 넣는다.
  SceneMarks.of(scene)
    ..showAlt = showAlt
    ..showHouses = showHouses
    ..leaderLabel = leaderLabel
    ..leaderOrdinal = leaderOrdinal
    ..hotTwins = hotTwins
    ..version += 1;
  await loadAll(scene);
  if (look != null) {
    final e = em.Emphasis.of(scene)..reduceMotion = !flowing;
    e.set(look);
    // 시계는 한 번에 50ms까지만 받는다(장면 하나가 아주 길어도 밝기가 건너뛰지 않게) — 나누어 흘린다.
    for (var left = flowMs ?? 0; left > 0;) {
      final step = left > 50 ? 50.0 : left;
      e.tick(step);
      left -= step;
    }
  }
  scene.prepare();
  // 좌표 비교는 글줄 준비가 끝난 장면으로 한다. 프레임 예산은 PC 부하에 따라 첫 그림에서 끝나지 않을 수 있다.
  for (int i = 0; i < 50; i++) {
    paint(painter);
    if (!painter.text.starved) break;
  }
  expect(painter.text.starved, isFalse, reason: '비교할 글줄은 50장면 안에 모두 준비되어야 한다');
  return painter;
}

void main() {
  test('단의 세로 자리는 줄 배치 그대로 — 이름 색줄 아래 몸통의 칸 층에 왕조 · 시기 · 지위 · 지도자 · 내각 차례로', () async {
    final (scene, painter) = make();
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    final geo = scene.layout.geo(0);
    final bandTop = scene.controller.view.yOf(scene.layout.rowTop(0) + geo.bandTop);
    final byKind = <int, Noted>{for (final n in notedCells(painter).reversed) if (n.lane == 0) n.kind: n};
    // 두 장 꼬리표(리메이크 2부 · 감독 결정 '두 장 ㄴ'): 이름 색줄 14 아래 몸통에서 칸 층이 14씩 맞붙는다(`G.floor` — 예전 16).
    // 왕조 14 → 시기 2 × 14 → 지위 14 → 지도자 14 → 내각 … → 그 밑에 흰 사건 칸(글줄 하나 18).
    // 칸은 층마다의 윗선(1px — 첫 층은 색줄 아랫변의 테 · 그 아래는 층 사이 금) 아래에 든다: 칸 위 = 층 위 + 1 · 높이 = 14 − 1 = 13(paint/strips.dart).
    const floor0 = G.head; // 14
    expect(geo.bodyTop - geo.bandTop, G.head, reason: '몸통 윗변 = 색줄 아랫변');
    expect(byKind[0]!.t - bandTop, 14 + 1, reason: '왕조 층은 띠 윗변에서 14px(몸통 윗변) — 칸은 그 윗선 아래');
    expect(byKind[0]!.h, G.dynasty - 1);
    expect(byKind[4]!.t - bandTop, floor0 + G.dynasty + 1, reason: '시기 층 0');
    expect(byKind[4]!.h, G.phase - 1);
    expect(byKind[5]!.t - bandTop, floor0 + G.dynasty + 2 * (G.phase + G.phaseGap) + 1, reason: '지위 층은 시기 두 층 아래');
    expect(byKind[1]!.t - bandTop, floor0 + G.dynasty + 2 * (G.phase + G.phaseGap) + G.rank + G.rankGap + 1, reason: '지도자 층');
    expect(byKind[1]!.t - bandTop, 14 + 14 + 28 + 14 + 1);
    expect(byKind[1]!.h, G.leader - 1);
    expect(byKind[1]!.h, 13);
    expect(geo.cabinetTop - geo.bandTop, 14 + 14 + 28 + 14 + 14, reason: '내각 층은 지도자 층 바로 밑(이 타일에는 내각 칸이 없다 — 자리만)');
    // 시기 층 1은 층 0보다 14 아래(층 사이 틈 없음)
    final phases = notedCells(painter).where((n) => n.kind == 4).toList();
    final lane1 = phases.firstWhere((n) => n.lane == 1), lane0 = phases.firstWhere((n) => n.lane == 0);
    expect(lane1.t - lane0.t, G.phase + G.phaseGap);
    expect(lane1.t - lane0.t, 14);
  });

  // 두 장 꼬리표(리메이크 2부 · 계약 3절 머리 상자): 줄 값(`fig_wide` 비트 19)이 실린 줄에서는 띠마다 **제 칸 층만** 몸통 윗변부터 맞붙인다
  // (`TagLook.compactOf` — 띠 look 비트 21~29). 줄의 칸 뭉치는 그 줄의 띠들이 나눠 쓰므로, 왕조 층이 없는 띠의 지도자 칸은 왕조 층만큼 올라간다.
  test('두 장 꼬리표: 띠마다 제 칸 층만 몸통 윗변부터 맞붙인다 — 왕조 층이 없는 띠의 지도자 칸은 몸통 첫 층에', () async {
    final shape = SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
      'tracks': [
        {
          'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'color': 0xa0bcc5, 'rail_levels': 2,
          // 비트 3~5 = 막대 단 수 + 1 · 16 왕조 · 17 지도자 · 19 줄 값으로 칸 층을 둠
          'rows': [{...row(0), 'fig_wide': (1 << 3) | (1 << 16) | (1 << 17) | (1 << 19)}],
        },
      ],
    });
    // 띠 look: 비트 20 = 칸이 있다 · 21 + 0 = 왕조 층 · 21 + 5 = 지도자 층.
    const leaderOnly = 1 << 20 | 1 << (21 + 5), both = 1 << 20 | 1 << 21 | 1 << (21 + 5);
    final data = (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, at(100), at(700), '첫불 성채국', look: leaderOnly)
          ..band(2, 0, at(800), at(1500), '은결 왕국', look: both)
          ..cell(10, 0, at(150), at(600), '첫불 임금', kind: 1, style: st(0, seq: 0))
          ..cell(20, 0, at(850), at(1400), '은결 왕조', kind: 0, style: st(0, seq: 0))
          ..cell(21, 0, at(850), at(1400), '은결 임금', kind: 1, style: st(0, seq: 1)))
        .build();
    final (scene, painter) = make(data: data, shape: shape);
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    final geo = scene.layout.geo(0);
    expect(scene.layout.spec(0)!.cellRows, isTrue);
    expect([geo.dynastyTop - geo.bandTop, geo.leaderTop - geo.bandTop], [G.head, G.head + G.floor], reason: '줄의 칸 뭉치: 왕조 → 지도자');
    final bandTop = scene.controller.view.yOf(scene.layout.rowTop(0) + geo.bandTop);
    final v = scene.controller.view;
    final cellsNow = notedCells(painter);
    Noted cellAt(int kind, double px) => cellsNow.firstWhere((n) => n.kind == kind && n.l <= v.xOf(at(px)) && n.r >= v.xOf(at(px)));
    expect(cellAt(1, 300).t - bandTop, G.head + 1, reason: '왕조 층이 없는 띠: 지도자 칸이 몸통 첫 층(남의 왕조 층 14만큼 올라감)');
    expect(cellAt(0, 1000).t - bandTop, G.head + 1, reason: '왕조 층을 가진 띠: 왕조 칸이 첫 층');
    expect(cellAt(1, 1000).t - bandTop, G.head + G.floor + 1, reason: '그 띠의 지도자 칸은 줄의 자리 그대로');
    expect(TagLook.compactOf(geo, leaderOnly, geo.leaderTop), geo.dynastyTop);
    expect(TagLook.compactOf(geo, both, geo.leaderTop), geo.leaderTop);
  });

  test('칸은 띠 안쪽 4px에 갇히고, 잇지 않는 쪽만 0.5px 틈이 벌어진다', () async {
    final (scene, painter) = make();
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    final v = scene.controller.view;
    final band = painter.debugBands.single;
    final dyn = notedCells(painter).where((n) => n.kind == 0).toList()..sort((a, b) => a.l.compareTo(b.l));
    expect(dyn.length, 2);
    expect(dyn[0].l, closeTo(v.xOf(at(150)) + 0.5, .01), reason: '왕조 칸은 잇지 않으므로 늘 0.5px 틈');
    expect(dyn[0].r, closeTo(v.xOf(at(600)) - 0.5, .01));
    expect(dyn[1].l, closeTo(v.xOf(at(600)) + 0.5, .01));
    expect(dyn[0].r < dyn[1].l, isTrue, reason: '왕조가 바뀌면 틈이 벌어진다');
    // 칸은 띠 안쪽(테두리 1 + 여백 3)에 갇힌다
    for (final n in notedCells(painter)) {
      expect(n.l, greaterThanOrEqualTo(band.rect.left + 4 - .01));
      expect(n.r, lessThanOrEqualTo(band.rect.right - 4 + .01));
    }
  });

  test('같은 무리의 이어지는 칸은 틈 없이 하나의 긴 둥근 칸이 된다', () async {
    final (scene, painter) = make();
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    final v = scene.controller.view;
    final leaders = notedCells(painter).where((n) => n.kind == 1).toList()..sort((a, b) => a.l.compareTo(b.l));
    expect(leaders.length, 3);
    expect(leaders[0].l, closeTo(v.xOf(at(150)) + 0.5, .01), reason: '무리의 바깥 끝은 0.5px 틈');
    expect(leaders[0].r, closeTo(v.xOf(at(400)), .01), reason: '이어지는 쪽은 틈이 없다');
    expect(leaders[1].l, closeTo(leaders[0].r, .01));
    expect(leaders[2].r, closeTo(v.xOf(at(1000)) - 0.5, .01));
  });

  test('예속 안 칸은 0번 단이 띠 아랫변에 가장 가깝다', () async {
    final (scene, painter) = make();
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    final deps = notedCells(painter).where((n) => n.kind == 7).toList();
    expect(deps.length, 2);
    final lane0 = deps.firstWhere((n) => n.lane == 0), lane1 = deps.firstWhere((n) => n.lane == 1);
    expect(lane0.t - lane1.t, G.depPitch, reason: '한 단 14(칸 층 — 틈 없음), 번호가 클수록 위');
    expect(lane0.t - lane1.t, 14);
    expect(lane0.h, G.dep - 1, reason: '칸은 층의 윗선(1px) 아래 13');
  });

  test('이름은 들어갈 때만 · 가운데 맞춤 · 체계 이름표는 그 체계에 하나', () async {
    final (scene, painter) = make();
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    final names = painter.debugLabels.where((l) => l.kind == 'cell').toList();
    expect(names.map((l) => l.text), contains('은결 나나나'));
    // 지도자 칸의 이름은 그 칸의 가운데
    final leaders = notedCells(painter).where((n) => n.kind == 1).toList()..sort((a, b) => a.l.compareTo(b.l));
    final first = names.firstWhere((l) => l.text == '은결 나나나');
    expect(first.at.dx, greaterThan(leaders[0].l), reason: '왼쪽 맞춤이 아니라 가운데');
    expect((first.at.dx + (first.at.dx - leaders[0].l)) < leaders[0].r, isTrue);
    // 체계 이름표: 체계마다(= 단마다) 하나씩만
    final tags = painter.debugLabels.where((l) => l.kind == 'sch').toList();
    expect(tags.length, 2, reason: '체계 둘 · 체계마다 첫 칸에만');
    expect(tags.map((l) => l.text).toSet(), {'장부 학파', '물길 학파'});
    // 시기 칸의 이름에는 체계 이름이 붙지 않는다(탭 문자 앞말은 딱지로 떨어져 나간다)
    for (final l in names) {
      expect(l.text.contains('\t'), isFalse);
    }
  });

  test('칸이 많아도 도형은 묶음으로 모으고 칸마다 세어 둔다', () async {
    final (scene, painter) = make();
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    // 그린 칸의 수 = 기록의 수 = stats.shapes의 몫. 그리기 호출은 층의 묶음(네모 · 무늬 · 조각 · 글자)뿐이다.
    expect(notedCells(painter).length, 11);
    expect(scene.stats.shapes, greaterThanOrEqualTo(11));
  });

  test('같은 장면을 두 번 그려도 똑같다 — 타일에 보관한 셈과 다시 쓰는 상자가 묵지 않는다', () async {
    // 층은 타일마다 한 번 셈한 것(무리의 경계 · 이름의 폭 · 칸 참조)을 보관하고 자리 상자 · 밝기를 다시 쓴다.
    // 보관이 묵거나 다시 쓰는 상자가 덜 비워지면 둘째 장면부터 그림이 달라진다.
    final (scene, painter) = make();
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    final first = [for (final k in const ['칸', '칸이음', '칸밝기', '무늬', '유령선']) ...noted(painter, k)];
    final firstNames = [for (final l in painter.debugLabels.where((l) => l.kind == 'cell' || l.kind == 'sch')) '${l.kind} ${l.text} ${l.at} ${l.alpha}'];
    paint(painter);
    final second = [for (final k in const ['칸', '칸이음', '칸밝기', '무늬', '유령선']) ...noted(painter, k)];
    final secondNames = [for (final l in painter.debugLabels.where((l) => l.kind == 'cell' || l.kind == 'sch')) '${l.kind} ${l.text} ${l.at} ${l.alpha}'];
    expect(first, isNotEmpty);
    expect(second, first);
    expect(secondNames, firstNames);
    // 맞히기의 자리 기록도 장면마다 다시 쓰이므로 쌓이지 않는다.
    final dyn = notedCells(painter).where((n) => n.kind == 0).toList()..sort((a, b) => a.l.compareTo(b.l));
    expect(painter.strips.hitStrips(dyn[0].l + 2, dyn[0].t + 2)!.ref, 'dynasty:0');
  });

  test('style 비트를 계약 6-2대로 읽는다', () {
    expect(CellStyle.rankOf(4 << 8), 3);
    expect(CellStyle.rankOf(0), -1);
    expect(CellStyle.depLookOf(1 << 11), 0);
    expect(CellStyle.depLookOf(3 << 11), 2);
    expect(CellStyle.depLookOf(0), -1);
    expect(CellKind.dep, 7);
  });

  test('style의 번갈아 짙기(비트 14)와 순번(15~26)을 계약 6-2대로 읽는다', () {
    expect(CellStyle.altOf(st(4, alt: true, seq: 7)), isTrue);
    expect(CellStyle.altOf(st(4, seq: 7)), isFalse);
    expect(CellStyle.seqOf(st(0, seq: 0)), 0);
    expect(CellStyle.seqOf(st(0, seq: 4093)), 4093);
    expect(CellStyle.seqOf(st(0)), -1, reason: '싣지 않았으면 −1');
    expect(CellStyle.seqOf(0xfff << 15), -1, reason: '넘치면 −1');
    // 순번 · 번갈아 짙기를 얹어도 아래 비트의 뜻은 그대로다(타일의 정렬 열쇠 lane은 건드리지 않는다).
    expect(CellStyle.rankOf(st(4 << 8, seq: 3)), 3);
    expect(CellStyle.depLookOf(st(2 << 11, alt: true, seq: 9)), 1);
  });

  test('누른 자리에서 칸을 찾아 칸 참조와 가리키는 항목을 돌려준다', () async {
    final painter = await drawn();
    final leaders = notedCells(painter).where((n) => n.kind == 1).toList()..sort((a, b) => a.l.compareTo(b.l));
    final hit = painter.strips.hitStrips(leaders[1].l + 2, leaders[1].t + 2);
    expect(hit, isNotNull);
    expect(hit!.ref, 'leader:1', reason: '칸 참조는 항목 기록의 차례(x_cellBounds의 열쇠)');
    expect(hit.kind, CellKind.leader);
    expect(hit.band, 1);
    expect(hit.key, '1|leader:1');
    // 왕조 칸은 구역 43이 가리키는 항목의 uid를 함께 돌려준다.
    final dyn = notedCells(painter).where((n) => n.kind == 0).toList()..sort((a, b) => a.l.compareTo(b.l));
    final onDyn = painter.strips.hitStrips(dyn[0].l + 2, dyn[0].t + 2);
    expect(onDyn!.ref, 'dynasty:0');
    expect(onDyn.uid, 'moon/d-0');
    // 칸이 없는 자리
    expect(painter.strips.hitStrips(5, 5), isNull);
    // 시기 · 지위 · 예속 안 칸도 제 참조를 돌려준다.
    final rank = notedCells(painter).firstWhere((n) => n.kind == 5);
    expect(painter.strips.hitStrips(rank.l + 2, rank.t + 2)!.ref, 'rank:0');
    final dep = notedCells(painter).firstWhere((n) => n.kind == 7 && n.lane == 1);
    expect(painter.strips.hitStrips(dep.l + 3, dep.t + 2)!.ref, 'dep:1');
  });

  // 고른 것이 있으면 칸은 **띠의 흐림에 제 몫을 더 곱한다**: `.tl-cell`은 .45(C:370) · 왕조 칸(`.tl-dyn`)은 .5(C:969).
  // 고른 띠 안의 칸도 흐려진다 — 그래서 고른 나라의 띠가 칸에 묻히지 않고 도드라진다(감독이 짚은 것).
  test('고른 것이 있으면 칸은 띠의 흐림에 제 몫(.45 · 왕조 .5 · 기관 .5 · 품은 칸 1)을 더 곱한다', () async {
    // 단마다의 몫 — 지도자 · 내각 · 시기 · 지위는 `.tl-cell`(.45) · 왕조는 `.tl-dyn`(.5) ·
    // 기관은 줄 직속인 `.tl-org`(띠의 흐림을 받지 않는 .5) · 품은 칸은 `.tl-dep`(제 규칙이 없어 띠 그대로).
    Map<int, Set<int>> byKind(TimelinePainter p) {
      final out = <int, Set<int>>{};
      for (final v in noted(p, '칸밝기')) {
        final head = v.split(' ');
        (out[int.parse(head[0].split(':')[0])] ??= {}).addAll(head[1].split(',').map(int.parse));
      }
      return out;
    }

    // 다른 띠를 고름 → 이 띠는 .58
    final away = byKind(await drawn(look: const em.Look(band: 99, row: 5)));
    expect(away[0], {290}, reason: '왕조 칸 — .58 × .5');
    final cellKinds = [for (final kind in const [1, 2, 4, 5]) if (away[kind] != null) kind];
    expect(cellKinds, isNotEmpty);
    for (final kind in cellKinds) {
      expect(away[kind], {261}, reason: '.tl-cell(단 $kind) — .58 × .45');
    }
    if (away[3] != null) expect(away[3], {500}, reason: '기관 칸은 줄 직속이라 띠의 .58을 받지 않는다 — .5');
    expect(away[7], {580}, reason: '품은 칸은 띠의 흐림 그대로');

    // 이 띠 자신을 고름 → 띠는 1이지만 칸은 그대로 제 몫만큼 흐려진다(감독이 짚은 것).
    final mine = byKind(await drawn(look: const em.Look(band: 1)));
    expect(mine[0], {500});
    for (final kind in cellKinds) {
      expect(mine[kind], {450}, reason: '고른 띠 안의 칸(단 $kind)도 .45로 흐려진다');
    }
    expect(mine[7], {1000}, reason: '품은 칸만 1로 남는다');

    // 아무것도 고르지 않으면 모두 1이다(회귀).
    final plain = byKind(await drawn());
    for (final entry in plain.entries) {
      expect(entry.value, {1000}, reason: '고른 것이 없으면 흐리지 않는다(단 ${entry.key})');
    }
  });

  test('같은 사람의 칸(건의 8의 6-나): 짝 칸에 먹 1.5px 테 — 고른 동안에도 칸의 .45 흐림에서 빠지고, 올린 칸의 짝도 같은 테', () async {
    // 다른 띠(99)의 칸을 골랐고 그 사람이 이 띠의 첫 지도자이기도 하다.
    final painter = await drawn(look: const em.Look(band: 99, row: 5, cell: 'leader:3', twins: {'99|leader:3', '1|leader:0'}));
    final twin = noted(painter, '같은사람');
    expect(twin, isNotEmpty);
    expect(twin, everyElement(startsWith('1|leader:0 ')));
    final lit = noted(painter, '칸밝기');
    expect(lit.where((v) => v.startsWith('1:0:0 ') && v.endsWith(' 580,580')), isNotEmpty, reason: '짝 칸은 띠의 .58 그대로(.45를 곱하지 않는다)');
    expect(lit.where((v) => v.startsWith('1:0:0 ') && v.endsWith(' 261,261')), isNotEmpty, reason: '나머지 지도자 칸은 .58 × .45');

    final hover = await drawn(hotTwins: const {'1|leader:1', '99|leader:0'});
    expect(noted(hover, '같은사람'), everyElement(startsWith('1|leader:1 ')));
    expect(noted(hover, '같은사람'), isNotEmpty);
    expect(noted(await drawn(), '같은사람'), isEmpty, reason: '짝이 없으면 테가 없다');
  });

  test('기간 조명: 구간 안의 칸은 .55 · 밖은 .45 · 누른 칸은 짙게', () async {
    final painter = await drawn(look: em.Look(band: 1, cell: 'leader:0', lit: true, spots: [em.Spot(1, at(150), at(400), cell: 'leader:0')]));
    final names = {for (final l in painter.debugLabels.where((l) => l.kind == 'cell')) l.text: l.alpha};
    expect(names['은결 나나나'], closeTo(.45, .001), reason: '누른 칸(is-spot)은 조명의 .55에서 빠져 `.tl-cell`의 .45로 남는다(C:1321의 :not(.is-spot))');
    expect(names['셋째 지도자'], closeTo(.45, .001), reason: '조명 밖의 칸');
    expect(names['문지기'], closeTo(.45, .001));
    // 묶음의 색 알파에도 같은 값이 곱해진다(칸 왼쪽 끝 · 오른쪽 끝에서 잰 값).
    final lit = noted(painter, '칸밝기');
    expect(lit.any((v) => v.startsWith('1:0:0 ') && v.endsWith(' 450,450')), isTrue, reason: '누른 칸은 조명의 가름에서 빠져 .45');
    expect(lit.any((v) => v.startsWith('1:0:0 ') && v.endsWith(' 450,450')), isTrue, reason: '조명 밖의 칸은 .45');
    // 지위 칸은 조명 경계(at(400))에 걸쳐 왼쪽 .55 · 오른쪽 .45로 갈린다.
    expect(lit.any((v) => v.startsWith('5:0:0 ') && v.endsWith(' 550,450')), isTrue, reason: '조명 경계에 걸친 칸은 안팎이 갈린다');
  });

  test("조명의 칸은 '같은 시기를 타국에도'를 끈 채로도 눌린 칸이다(지금 연표의 _isSpot)", () async {
    // lit이 꺼지면 흐린 띠를 구간으로 갈라 칠하지는 않지만, 창이 가리킨 그 칸은 그대로 짙다.
    final painter = await drawn(look: em.Look(bands: const {1}, spots: [em.Spot(1, at(150), at(400), cell: 'leader:0')]));
    final lit = noted(painter, '칸밝기');
    expect(lit.any((v) => v.startsWith('1:0:0 ') && v.endsWith(' 1000,1000')), isTrue, reason: '조명의 칸은 흐려지지 않는다');
    expect(lit.any((v) => v.startsWith('5:0:0 ') && v.endsWith(' 550,550')), isTrue, reason: '강조에 든 띠의 다른 칸은 .55');
  });

  test('모호한 구간(구역 40)은 이름표를 비켜 무늬 조각으로 나뉜다', () async {
    final painter = await drawn();
    final marks = noted(painter, '무늬').where((v) => v.startsWith('1 ')).toList();
    expect(marks, isNotEmpty, reason: '지도자 단에 구역 40의 구간이 실렸다');
    // 조각의 합은 구간(100px 어치)보다 좁다 — 이름표 자리를 비켜 갈라졌기 때문.
    final widths = [for (final m in marks) double.parse(m.split(',')[1]) / 10];
    expect(widths.fold<double>(0, (a, b) => a + b), lessThan(at(350) * ppm - at(250) * ppm + 1));
  });

  test('이설의 유령 구분선(구역 41)을 칸 높이만 한 세로 점선으로 긋는다', () async {
    final painter = await drawn();
    final lines = noted(painter, '유령선');
    expect(lines.length, 1);
    expect(lines.single.startsWith('1:0:0 '), isTrue, reason: '지도자 단의 0번 단');
  });

  test('조감(밀도 2)에서는 띠 안의 단이 모두 사라진다', () async {
    final painter = await drawn(density: 2);
    expect(notedCells(painter), isEmpty);
    expect(painter.debugLabels.where((l) => l.kind == 'cell'), isEmpty);
  });

  // ──────────────── 기간 조명의 흐름(명세 06의 3-3) ────────────────

  test('조명이 켜지는 동안 구간 안의 밝기는 띠의 밝기와 조명 밝기 사이를 진행만큼 흐른다', () async {
    final spot = [em.Spot(1, at(150), at(400), cell: 'leader:0')];
    // 200ms 가운데 50ms — 구간 안은 .45와 .55 사이 어딘가, 구간 밖은 그대로 .45.
    final mid = await drawn(look: em.Look(lit: true, spots: spot), flowMs: 50);
    final rank = noted(mid, '칸밝기').firstWhere((v) => v.startsWith('5:0:0 ')).split(' ')[1].split(',').map(int.parse).toList();
    expect(rank[1], 450, reason: '조명 밖은 흐르지 않는다');
    expect(rank[0], greaterThan(450), reason: '켜지는 중이라 이미 띠보다 밝다');
    expect(rank[0], lessThan(550), reason: '아직 다 켜지지 않았다');
    // 아주 조금만 흘렀을 때가 더 어둡다(진행이 늘수록 밝아진다).
    final early = await drawn(look: em.Look(lit: true, spots: spot), flowMs: 4);
    final rankEarly = noted(early, '칸밝기').firstWhere((v) => v.startsWith('5:0:0 ')).split(' ')[1].split(',').map(int.parse).toList();
    expect(rankEarly[0], lessThan(rank[0]));
    expect(rankEarly[0], greaterThanOrEqualTo(450));
    // 다 켜지면 예전과 똑같다(.55 / .45).
    final done = await drawn(look: em.Look(lit: true, spots: spot));
    expect(noted(done, '칸밝기').any((v) => v.startsWith('5:0:0 ') && v.endsWith(' 550,450')), isTrue);
  });

  test('반쯤도 켜지지 않은 조명은 아직 눌린 칸으로 치지 않는다', () async {
    final spot = [em.Spot(1, at(150), at(400), cell: 'leader:0')];
    // 이름을 고르지 않고(조명만) 4ms — 진행이 .5를 넘지 못하므로 그 칸도 아직 흐린 쪽에 가깝다.
    final early = await drawn(look: em.Look(lit: true, spots: spot), flowMs: 4);
    final lit = noted(early, '칸밝기').firstWhere((v) => v.startsWith('1:0:0 ')).split(' ')[1].split(',').map(int.parse).toList();
    expect(lit[0], lessThan(550), reason: '눌린 칸의 짙은 모습(밝기 1)으로 건너뛰지 않는다');
    // 다 켜지면 눌린 칸이다.
    final done = await drawn(look: em.Look(lit: true, spots: spot));
    expect(noted(done, '칸밝기').any((v) => v.startsWith('1:0:0 ') && v.endsWith(' 1000,1000')), isTrue);
  });

  // ──────────────── 필터 시트의 표시 값 넷 ────────────────

  test("'이설' 체크를 끄면 유령 구분선도 이름 밑 점선도 그리지 않는다 — 모호한 칸의 무늬는 그대로", () async {
    final on = await drawn();
    final off = await drawn(showAlt: false);
    expect(noted(on, '유령선'), isNotEmpty);
    expect(noted(off, '유령선'), isEmpty);
    // 칸의 자리 · 모양은 하나도 달라지지 않는다(무늬도 그대로 — 지금 연표 altRowPlan의 zones).
    expect(noted(off, '칸'), noted(on, '칸'));
    expect(noted(off, '무늬'), noted(on, '무늬'));
  });

  test("표시 체크 '가문'을 켜면 이어 붙은 지도자 칸에 가문 줄 한 가닥이 깔린다", () async {
    final off = await drawn();
    expect(noted(off, '가문줄'), isEmpty, reason: '기본은 꺼짐');
    final painter = await drawn(showHouses: true);
    final lines = noted(painter, '가문줄');
    expect(lines.length, 1, reason: '둘째 · 셋째 지도자 칸이 같은 가문이라 한 가닥');
    final leaders = notedCells(painter).where((n) => n.kind == 1).toList()..sort((a, b) => a.l.compareTo(b.l));
    final parts = lines.single.split(' ');
    final box = parts[1].split(',').map((v) => int.parse(v) / 10).toList();
    expect(parts[0], 'h-moon-1');
    expect(box[0], closeTo(leaders[1].l + 1, .01), reason: '이어 붙은 왼쪽 끝은 1px 들임');
    expect(box[0] + box[2], closeTo(leaders[2].r - 3, .01), reason: '둥근 오른쪽 끝은 3px 들임');
    expect(box[1], closeTo(leaders[1].t + leaders[1].h - 3, .01), reason: '칸 아래 테두리 바로 안쪽');
    expect(parts[2], (mixSrgb(0xff000000 | houseColor, 0xff000000, .72) & 0xffffffff).toRadixString(16));
    // 첫째 지도자 칸은 가문이 없어 줄이 없다.
    expect(box[0], greaterThan(leaders[0].r));
  });

  test("표시 체크 '가문'을 켜면 지도자 단의 유령 구분선이 그 줄만큼 짧아진다", () async {
    double bottomOf(TimelinePainter p) =>
        double.parse(noted(p, '유령선').firstWhere((v) => v.startsWith('1:0:0 ')).split(' ')[2].split(',')[1]) / 10;
    final off = await drawn(), on = await drawn(showHouses: true);
    expect(noted(on, '유령선').length, noted(off, '유령선').length, reason: '가문 줄은 유령선의 수를 바꾸지 않는다');
    expect(bottomOf(off) - bottomOf(on), closeTo(2, .01), reason: '아래 들임이 2 → 4');
    // 지도자가 아닌 단은 그대로다.
    expect(noted(on, '유령선').where((v) => !v.startsWith('1:')), noted(off, '유령선').where((v) => !v.startsWith('1:')));
  });

  test('지도자 표기와 대수(구역 46)를 칸 이름에 옮긴다', () async {
    Set<String> namesOf(TimelinePainter p) => {for (final l in p.debugLabels.where((l) => l.kind == 'cell')) l.text};
    expect(namesOf(await drawn()), contains('은결 나나나'));
    expect(namesOf(await drawn(leaderLabel: 'temple')), contains('고요묘'));
    expect(namesOf(await drawn(leaderLabel: 'title')), contains('맑은시호'));
    expect(namesOf(await drawn(leaderLabel: 'given')), contains('나나나'));
    expect(namesOf(await drawn(leaderLabel: 'temple-title')), contains('고요묘 맑은시호'));
    expect(namesOf(await drawn(leaderLabel: 'all')), contains('고요묘 맑은시호 나나나'));
    expect(namesOf(await drawn(leaderOrdinal: true)), contains('3대 은결 나나나'));
    expect(namesOf(await drawn(leaderLabel: 'temple', leaderOrdinal: true)), contains('3대 고요묘'));
    // 구역 46이 없는 칸(둘째 · 셋째 지도자)은 기본 표기 그대로다.
    expect(namesOf(await drawn(leaderLabel: 'temple')), contains('둘째 지도자'));
    // 지도자가 아닌 단은 표기에 흔들리지 않는다.
    expect(namesOf(await drawn(leaderLabel: 'all')), contains('문지기'));
  });

  test('표기가 바뀌면 타일에 걸어 둔 글 · 폭 보관을 비운다 — 같은 층으로 이어 그려도 이름이 묵지 않는다', () async {
    final (scene, painter) = make();
    scene.controller.reduceMotion = true;
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    Set<String> names() => {for (final l in painter.debugLabels.where((l) => l.kind == 'cell')) l.text};
    expect(names(), contains('은결 나나나'));
    SceneMarks.of(scene)
      ..leaderLabel = 'temple'
      ..version += 1;
    paint(painter);
    expect(names(), contains('고요묘'));
    expect(names(), isNot(contains('은결 나나나')));
    SceneMarks.of(scene)
      ..leaderLabel = 'auto'
      ..version += 1;
    paint(painter);
    expect(names(), contains('은결 나나나'));
  });

  test('메움으로 깔린 타일에는 못 찾은 표기를 굳히지 않는다 — 구역 46이 뒤늦게 실려 와도 그 칸만 기본 이름으로 남지 않게', () async {
    // 메움(cover): 지금 단계의 타일이 아직 덜 떠서 그 자리를 윗단계 타일이 깔아 메운 장면.
    // 층은 메움 타일의 구역 46을 읽지 않지만(beginFrame의 `d.isCover`) 그리개는 메움 타일도 [paintTile]로 그린다 —
    // 그 장면에서 지은 기본 표기를 타일에 굳혀 두면, 그 타일이 제 단계의 주 타일이 되어 구역 46이 실려 와도 그 칸만 옛 이름으로 남는다.
    var nowMs = 0.0;
    final data = cells();
    // 단계 8의 타일은 띠만 담는다 — 칸은 메움으로 깔린 단계 9의 타일에서 온다(칸을 가두는 띠는 메움이 아닌 타일에서만 모은다).
    final bandOnly = (TileBuilder(level: 8, x: 0, chunk: 0)..band(1, 0, at(100), at(1600), '첫불 성채국', color: 0xa0bcc5)).build();
    final controller = TimelineController()
      ..resize(1920, 1080)
      ..setExtent(-at(100000), at(100000))
      ..setContentHeight(600);
    controller.showRange(0, at(1920 - SceneView.gutter));
    final scene = TimelineScene(
      controller: controller,
      layout: layout(),
      clock: () => nowMs, // 시계를 멈춰 두면 갓 온 타일이 떠오르는 중(alpha < 1)이라 그 밑에 메움이 깔린다
      fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0
          ? data
          : (level == 8 && x == 0 && chunk == 0 ? bandOnly : (TileBuilder(level: level, x: x, chunk: chunk)).build()),
    );
    addTearDown(scene.dispose);
    final painter = painterOf(scene);
    Set<String> names() => {for (final l in painter.debugLabels.where((l) => l.kind == 'cell')) l.text};
    double xOf(TimelinePainter p, String text) => p.debugLabels.firstWhere((l) => l.kind == 'cell' && l.text == text).at.dx;

    // (1) 기본 표기로 단계 9를 한 번 그려 타일을 받아 둔다(표기가 기본이면 구역 46은 아예 읽지 않는다).
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    expect(names(), contains('은결 나나나'));

    // (2) 4배로 당기면 단계 8 — 그 타일이 막 왔으므로 밑에 단계 9의 타일이 메움으로 깔린다. 여기서 표기를 바꾼다.
    controller.showRange(0, at((1920 - SceneView.gutter) / 4));
    await loadAll(scene);
    scene.prepare();
    expect(scene.draw.any((d) => d.isCover), isTrue, reason: '메움 타일이 깔린 장면이어야 이 검사가 뜻이 있다');
    SceneMarks.of(scene)
      ..leaderLabel = 'temple'
      ..version += 1;
    paint(painter);
    // 메움 타일만으로는 구역 46을 못 읽으므로 이 장면의 이름은 기본 표기다(여기까지는 지금도 옳다).
    expect(names(), contains('은결 나나나'));

    // (3) 다시 단계 9. 이번에는 제 타일이라 구역 46이 실려 온다 — (2)의 답이 굳어 있으면 안 된다.
    nowMs = 5000;
    controller.showRange(0, at(1920 - SceneView.gutter));
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    expect(names(), contains('고요묘'));
    expect(names(), isNot(contains('은결 나나나')));
    // 글이 달라지면 폭도 달라진다 — (2)에서 기본 표기로 재어 둔 폭이 남아 있으면 이름이 그만큼 비켜 놓인다.
    expect(xOf(painter, '고요묘'), closeTo(xOf(await drawn(leaderLabel: 'temple'), '고요묘'), .01),
        reason: '메움을 거치지 않고 곧바로 그린 장면과 같은 자리');
  });

  // ──────────────── 가문 조명 · 조명 칠 · 성씨 풍선의 자리(확정 설계 1-2 5-2 · 5-3 — D1-N3) ────────────────

  // 견본: 둘째 · 셋째 지도자 칸(at 400~1000)이 가문 'h-moon-1', 첫째 칸(150~400)은 가문 없음. 가문 기록의 x_spots를 띠 번호로 바꾼 꼴.
  final houseLook = em.Look(house: 'h-moon-1', houses: const {'h-moon-1'}, spots: [em.Spot(1, at(400), at(1000))]);

  test('가문 조명: 묶음의 칸은 진하게 · 조명된 띠의 다른 지도자 칸(가문 없음 포함)은 .55 · 왕조 · 시기 · 지위 · 예속은 그대로', () async {
    final painter = await drawn(look: houseLook);
    final alpha = {for (final l in painter.debugLabels.where((l) => l.kind == 'cell')) l.text: l.alpha};
    expect(alpha['은결 나나나'], closeTo(.55, .001), reason: '가문이 없는 지도자 칸도 다른 칸이다(웹 is-other-house)');
    expect(alpha['둘째 지도자'], 1);
    expect(alpha['셋째 지도자'], 1);
    expect(alpha['문지기'], 1, reason: '지위 칸은 흐리지 않는다');
    expect(alpha['유리항 깊은 왕조'], 1, reason: '왕조 칸은 흐리지 않는다');
    final leaders = notedCells(painter).where((n) => n.kind == 1).toList()..sort((a, b) => a.l.compareTo(b.l));
    expect(noted(painter, '칸밝기').where((v) => v.startsWith('1:0:0 ')).map((v) => v.split(' ')[1]).toList()..sort(), ['1000,1000', '1000,1000', '550,550']);
    // 묶음의 칸은 가문 강조와 같은 진한 바탕(제 색 42% + 종이) — 칸 안 왼쪽(이름이 없는 자리)의 픽셀.
    final px = await pixelsOf(painter);
    final second = leaders[1];
    expect(pixelAt(px, second.l + 8, second.t + second.h / 2), rgbaOf(mixSrgb(0xffa0bcc5, Look.paper, .42)), reason: '둘째 지도자 칸은 is-house');
  });

  test('가문 조명의 칠: 띠 색 22%를 띠 안쪽 높이로 그 구간에만 — 칸 아래 · 구간 밖은 그대로', () async {
    final painter = await drawn(look: houseLook);
    final fills = noted(painter, '조명칠');
    expect(fills.length, 1);
    final parts = fills.single.split(' ');
    expect(parts[0], '1');
    final box = parts[1].split(',').map((v) => int.parse(v) / 10).toList();
    final v = painter.scene.controller.view;
    expect(box[0], closeTo(v.xOf(at(400)), .051));
    expect(box[0] + box[2], closeTo(v.xOf(at(1000)), .051));
    expect(parts[2], (withAlpha(0xffa0bcc5, .22) & 0xffffffff).toRadixString(16));
    // 픽셀: 칸이 없는 띠 안 자리에서 구간 안은 띠 색 22%가 얹히고, 구간 밖은 하나도 다르지 않다.
    final plain = await drawn();
    final before = await pixelsOf(plain), after = await pixelsOf(painter);
    final y = freeY(plain, [v.xOf(at(900)), v.xOf(at(1100))]);
    final inside = v.xOf(at(900)), outside = v.xOf(at(1100));
    expect(pixelAt(after, outside, y), pixelAt(before, outside, y), reason: '구간 밖');
    expectBlend(pixelAt(after, inside, y), pixelAt(before, inside, y), 0xa0bcc5, .22, reason: '구간 안');
    // 칠의 두 끝에 띠 테두리 색 60%의 1px 세로선(띠 끝에 닿지 않았으므로 둘 다).
    expect(pixelAt(after, inside, y), isNot(pixelAt(after, v.xOf(at(400)), y)));
  });

  test("가문 조명을 켰다 끈 뒤의 장면은 켜기 전과 픽셀까지 같다(흐름 200 · 160ms를 다 지난 뒤)", () async {
    // 시계를 멈춰 둔다 — 타일이 떠오르는 흐름은 다 끝난 자리에서, 밝기의 흐름은 손으로 돌린다(그리개의 시계는 0만큼 흐른다).
    var nowMs = 0.0;
    final (scene, painter) = make(clock: () => nowMs);
    scene.controller.reduceMotion = false;
    await loadAll(scene);
    nowMs = 60000;
    final e = em.Emphasis.of(scene)..reduceMotion = false;
    scene.prepare();
    final before = await pixelsOf(painter);
    e.set(houseLook);
    for (int i = 0; i < 20; i++) {
      e.tick(25);
    }
    scene.prepare();
    final on = await pixelsOf(painter);
    expect(listEquals(on, before), isFalse, reason: '켜면 달라진다');
    e.set(const em.Look());
    for (int i = 0; i < 20; i++) {
      e.tick(25);
    }
    expect(e.active, isFalse);
    scene.prepare();
    final after = await pixelsOf(painter);
    expect(listEquals(after, before), isTrue, reason: '끈 뒤 = 켜기 전');
  });

  test('가문 조명의 .55는 흐른다 — 옅어짐 160ms 도중에는 1과 .55 사이', () async {
    final mid = await drawn(look: houseLook, flowMs: 60);
    final a = mid.debugLabels.firstWhere((l) => l.kind == 'cell' && l.text == '은결 나나나').alpha;
    expect(a, lessThan(1));
    expect(a, greaterThan(.55));
  });

  test('옛 꼴(house 하나 · 구간 없음)은 지금 그대로 — 칠 · .55 없이 그 가문 칸만 진하게', () async {
    final painter = await drawn(look: const em.Look(house: 'h-moon-1'));
    expect(noted(painter, '조명칠'), isEmpty);
    final alpha = {for (final l in painter.debugLabels.where((l) => l.kind == 'cell')) l.text: l.alpha};
    expect(alpha['은결 나나나'], 1);
    final px = await pixelsOf(painter);
    final leaders = notedCells(painter).where((n) => n.kind == 1).toList()..sort((a, b) => a.l.compareTo(b.l));
    expect(pixelAt(px, leaders[1].l + 8, leaders[1].t + leaders[1].h / 2), rgbaOf(mixSrgb(0xffa0bcc5, Look.paper, .42)));
  });

  test('칸 · 인물 · 왕조 조명은 칠하지 않는다(지금 그대로) — 칠은 가문 · 성씨 조명의 구간만', () async {
    final cell = await drawn(look: em.Look(cell: 'leader:0', spots: [em.Spot(1, at(150), at(400), cell: 'leader:0')]));
    expect(noted(cell, '조명칠'), isEmpty);
    final figure = await drawn(look: em.Look(lit: true, spots: [em.Spot(1, at(150), at(400))]));
    expect(noted(figure, '조명칠'), isEmpty);
  });

  test('가문 조명을 끄면 칠은 160ms에 옅어지며 남고, 그 뒤에 켠 칸 조명의 같은 구간은 칠하지 않는다', () async {
    var nowMs = 0.0;
    final (scene, painter) = make(clock: () => nowMs);
    scene.controller.reduceMotion = false;
    await loadAll(scene);
    nowMs = 60000;
    final e = em.Emphasis.of(scene);
    e.set(houseLook);
    for (int i = 0; i < 12; i++) {
      e.tick(25);
    }
    // 끄면서 칸 창으로 옮김(가문 창 → 칸 창): 옛 가문 구간은 옅어지는 동안 칠이 남는다.
    e.set(em.Look(cell: 'leader:1', spots: [em.Spot(1, at(400), at(700), cell: 'leader:1')]));
    e.tick(40);
    scene.prepare();
    paint(painter);
    final fading = noted(painter, '조명칠');
    expect(fading.length, 1);
    final alpha = int.parse(fading.single.split(' ')[2], radix: 16) >> 24;
    expect(alpha, lessThan((255 * .22).round()), reason: '옅어지는 중');
    expect(alpha, greaterThan(0));
    for (int i = 0; i < 12; i++) {
      e.tick(25);
    }
    scene.prepare();
    paint(painter);
    expect(noted(painter, '조명칠'), isEmpty, reason: '가라앉으면 칸 조명이라 칠이 없다');
  });

  test('칠 차례: 조명 칠은 띠의 추정 빗금(연대 폭) 위에 얹힌다(10절 14번 · 웹 W3와 같은 차례)', () async {
    // 연대 폭(구역 19 · 추정)이 띠 앞쪽 at 100~700을 덮고, 조명 구간 at 400~1000이 그 일부와 겹친다. 칸은 없다.
    final data = (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, at(400), at(1600), '첫불 성채국', color: 0xa0bcc5, look: BandLook.hasRange | BandLook.certEstimated << BandLook.certShift)
          ..item(19, 1, 0, at(100), at(700), ref: 1, color: 0xa0bcc5, a: 0, b: 0))
        .build();
    Future<(TimelinePainter, Uint8List)> shot(em.Look? look) async {
      final (scene, painter) = make(data: data);
      scene.controller.reduceMotion = true;
      await loadAll(scene);
      if (look != null) {
        em.Emphasis.of(scene)
          ..reduceMotion = true
          ..set(look);
      }
      scene.prepare();
      return (painter, await pixelsOf(painter));
    }

    final (plainPainter, before) = await shot(null);
    final (_, after) = await shot(em.Look(houses: const {'h-moon-1'}, spots: [em.Spot(1, at(400), at(1000))]));
    final v = plainPainter.scene.controller.view;
    final geo = plainPainter.scene.layout.geo(0);
    // 두 장 꼬리표(리메이크 2부): 띠 무늬(연대 폭 빗금)는 이름 색줄(14)에만 깔리고 몸통은 칸 뭉치 칠 · 사건 칸 종이다 — 색줄의 세로 가운데(구멍 높이)에서 잰다.
    // 머리 이름은 띠의 진짜 왼쪽 끝(연대 폭이 넓힌 at 100) + 14에 있어 아래 x 범위(at 420 ~ 680)에 들지 않는다.
    final y = v.yOf(plainPainter.scene.layout.rowTop(0) + geo.bandTop + G.head / 2);
    // 빗금의 줄과 틈(6px 주기)을 모두 지나도록 여러 픽셀 — 줄이든 틈이든 칠이 얹혔다(칠이 빗금 아래면 틈의 종이빛이 그대로 남는다).
    // 몸통의 세로 눈금 점선은 띠 위에 긋는 것이라(지금 연표와 같음) 그 몇 픽셀은 빼고 센다.
    var total = 0, blended = 0;
    final colors = <int>{};
    for (double x = v.xOf(at(420)); x < v.xOf(at(680)); x += 1) {
      total++;
      final b = pixelAt(before, x, y), a = pixelAt(after, x, y);
      var ok = true;
      for (final shift in const [24, 16, 8]) {
        final bc = (b >> shift) & 0xff, c = (0xa0bcc5 >> (shift - 8)) & 0xff, ac = (a >> shift) & 0xff;
        if ((ac - (bc + (c - bc) * .22)).abs() > 2) ok = false;
      }
      if (ok) {
        blended++;
        colors.add(b);
      }
    }
    expect(blended, greaterThan(total - 8), reason: '$blended / $total');
    expect(colors.length, greaterThanOrEqualTo(2), reason: '빗금의 줄 색과 틈 색 모두에 얹혔다: ${colors.map((c) => c.toRadixString(16))}');
  });

  test('커서가 올라간 칸의 자리 · 가문을 장면을 그린 뒤에 알린다(성씨 풍선) — 벗어나면 null', () async {
    final (scene, painter) = make();
    await loadAll(scene);
    SceneMarks.of(scene)
      ..hotCell = '1|leader:1'
      ..version += 1;
    scene.prepare();
    paint(painter);
    await pumpEventQueue();
    final hit = StripLayer.hoverOf(scene).value;
    expect(hit, isNotNull);
    expect(hit!.key, '1|leader:1');
    expect(hit.kind, 1);
    expect(hit.houseId, 'h-moon-1');
    expect(hit.houseName, '푸른달 가문');
    expect(hit.houseColor, 0xff000000 | houseColor);
    final second = (notedCells(painter).where((n) => n.kind == 1).toList()..sort((a, b) => a.l.compareTo(b.l)))[1];
    expect(hit.rect.left, closeTo(second.l, .051));
    expect(hit.rect.right, closeTo(second.r, .051));
    SceneMarks.of(scene)
      ..hotCell = null
      ..version += 1;
    paint(painter);
    await pumpEventQueue();
    expect(StripLayer.hoverOf(scene).value, isNull);
  });

  // ──────────────── 진짜 자료 처리부(DLL) + 진짜 저장소 ────────────────
  // 가문 줄은 타일의 구역 42를 읽어야 나온다 — 가짜 타일만으로는 "실제 저장소에서는 통째로 비어 있는" 것을 잡지 못한다(검증 9-2의 교훈).
  // 자리는 지금 연표를 머리 없는 브라우저로 같은 설정(밀집-세부 · 1920×1080 · '가문' 켬)으로 띄워 읽은 값이다.

  test('진짜 엔진 · 진짜 저장소: 가문 줄이 지금 연표와 같은 자리에 깔린다', () async {
    final dll = File('../engine/target/release/archive_engine.dll');
    final db = File(const String.fromEnvironment('DB', defaultValue: '../data/moonwake3h/archive.db'));
    if (!dll.existsSync() || !db.existsSync()) {
      markTestSkipped('자료 처리부 DLL 또는 저장소가 없습니다');
      return;
    }
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    addTearDown(engine.close);
    final info = await engine.start(db.absolute.path);
    final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
    final shape = SceneLayout.fromJson(Map<String, dynamic>.from((await engine.call({'op': 'layout'}))['data'] as Map));
    // 기준 그림과 같은 좌표: 1920×1080에서 맨 위 60px은 앱 틀의 자리다(그리는 쪽은 1920×1020).
    const width = 1920.0, height = 1020.0, top = 60.0;
    final controller = TimelineController()
      ..reduceMotion = true
      ..resize(width, height)
      ..setExtent(double.parse(meta['min'] as String), double.parse(meta['max'] as String))
      ..setContentHeight(shape.totalHeight);
    final scene = TimelineScene(
      controller: controller,
      layout: shape,
      fetchTile: engine.tile,
      ask: (query) async => Map<String, dynamic>.from((await engine.call(query))['data'] as Map),
    );
    addTearDown(scene.dispose);
    scene.applyLayoutToView();
    controller
      ..resize(width, height)
      ..showRange(minuteOfYear(775), minuteOfYear(940))
      ..scrollTo(0);
    SceneMarks.of(scene)
      ..showHouses = true
      ..version += 1;
    final painter = TimelinePainter(scene)..debug = true;
    // 타일이 올 때까지 그려 본다(자료 조회는 다른 작업자에서 돈다).
    for (int i = 0; i < 80; i++) {
      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const ui.Size(width, height));
      recorder.endRecording().dispose();
      if (scene.stats.tiles > 0 && scene.stats.blanks == 0 && noted(painter, '가문줄').isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      scene.tick(20);
    }
    expect(scene.stats.tiles, greaterThan(0), reason: '타일이 오지 않았다');
    final lines = noted(painter, '가문줄')
        .map((v) {
          final parts = v.split(' ');
          final box = parts[1].split(',').map((n) => int.parse(n) / 10).toList();
          return (parts[0], box[0], box[1] + top, box[2], parts.length > 3 ? parts[3] : '');
        })
        .toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    expect(lines.length, 2, reason: '밀집-세부의 첫 줄에는 가문 줄이 두 가닥이다(지금 연표와 같은 수)');
    // 지금 연표의 값: h-coast-0 [243, 589, 655.3] · h-coast-1 [905.3, 589, 1011.69] + 왼쪽 미정 꼬리 41px.
    expect(lines[0].$1, 'h-coast-0');
    expect(lines[0].$2, closeTo(243, .15));
    expect(lines[0].$3, closeTo(589, .15));
    expect(lines[0].$4, closeTo(655.3, .15));
    expect(lines[1].$1, 'h-coast-1');
    expect(lines[1].$2, closeTo(905.3, .15));
    expect(lines[1].$3, closeTo(589, .15));
    expect(lines[1].$4, closeTo(1011.69, .15));
    expect(lines[1].$5, 'fl=410', reason: '바깥 끝 칸이 미정이라 꼬리 44 − 3 = 41px에 걸쳐 옅어진다');
    // 색: 지금 연표가 셈한 값 color(srgb …)을 255로 되돌린 것 — mixSrgb(가문 색, --paper-ink, 72%).
    final tones = noted(painter, '가문줄').map((v) => int.parse(v.split(' ')[2], radix: 16)).toList()..sort();
    for (final (want, got) in [(const [128, 147, 151], tones[0]), (const [148, 129, 116], tones[1])]) {
      expect([(got >> 16) & 0xff, (got >> 8) & 0xff, got & 0xff], want);
    }
  });

  test('지도자 표기 짓기는 지금 연표의 HT.leaderLabel 그대로', () {
    final layer = StripLayer();
    expect(layer.leaderTextOf('본이름', '묘', '시', '이름', 3), '본이름');
    layer.leaderLabel = 'temple';
    expect(layer.leaderTextOf('본이름', '묘', '시', '이름', 3), '묘');
    expect(layer.leaderTextOf('본이름', '', '시', '이름', 3), '본이름', reason: '고른 표기가 비면 기본 표기로');
    layer.leaderLabel = 'temple-title';
    expect(layer.leaderTextOf('본이름', '묘', '', '이름', 3), '묘', reason: '빈 것은 빼고 잇는다');
    layer.leaderLabel = 'all';
    expect(layer.leaderTextOf('본이름', '묘', '시', '이름', -1), '묘 시 이름');
    layer.leaderOrdinal = true;
    expect(layer.leaderTextOf('본이름', '묘', '시', '이름', -1), '묘 시 이름', reason: '대수가 없는 칸에는 붙이지 않는다');
    expect(layer.leaderTextOf('본이름', '묘', '시', '이름', 12), '12대 묘 시 이름');
  });

  test('크게 확대해 시작이 화면 왼쪽 밖이고 타일에 잘린 긴 칸도 이름을 쓴다(감독 건의 2026-10-14 10번)', () async {
    // 타일의 왼쪽 끝(분 0)이 곧 화면 왼쪽 끝이다(make의 showRange(0, …)). 칸 · 띠 모두 그 앞 타일에서 시작해 왼쪽이 잘려 온다.
    final tile = (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, 0, at(1700), '긴 나라', flags: Tile.clipLeft)
          ..cell(60, 0, 0, at(1600), '긴 시기', kind: 4, lane: 0, flags: Tile.clipLeft, style: st(0, seq: 3))
          ..cell(61, 0, 0, at(1600), '긴 임금', kind: 1, flags: Tile.clipLeft, style: st(0, seq: 7)))
        .build();
    final (scene, painter) = make(data: tile);
    await loadAll(scene);
    scene.prepare();
    // 이름은 글자 폭을 잰 뒤에 쓴다 — 글줄 준비가 끝난 장면으로 본다(검사 묶음 전체를 돌리면 첫 장면에서 폭이 아직일 수 있다).
    for (int i = 0; i < 50; i++) {
      paint(painter);
      if (!painter.text.starved) break;
    }
    final names = painter.debugLabels.where((l) => l.kind == 'cell').map((l) => l.text).toList();
    expect(names, containsAll(['긴 시기', '긴 임금']), reason: '예전에는 잘린 조각이 화면 왼쪽 끝에 닿아 있어도 p.l(> c.left) 때문에 아무도 이름을 쓰지 않았다');
  });

  test('축소해 엔진이 짧은 칸을 빼고 보낸 자리는 앞뒤 칸을 잇는다 — 순번이 건너뛸 때만(감독 건의 2026-10-14 8번)', () async {
    // 지도자 셋: 순번 0 → 2(1은 엔진이 성긴 단계에서 뺌 — 4px 빈자리) 이어짐 · 순번 2 → 3은 실제로 6px 비어 있음(뺀 칸이 없음).
    final tile = (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, at(100), at(1600), '첫불 성채국')
          ..cell(10, 0, at(150), at(400), '하나', kind: 1, style: st(0, seq: 0))
          ..cell(12, 0, at(404), at(700), '셋', kind: 1, style: st(4, seq: 2))
          ..cell(13, 0, at(706), at(1000), '넷', kind: 1, style: st(4, seq: 3)))
        .build();
    final (scene, painter) = make(data: tile);
    await loadAll(scene);
    scene.prepare();
    paint(painter);
    final v = scene.controller.view;
    final leaders = notedCells(painter).where((n) => n.kind == 1).toList()..sort((a, b) => a.l.compareTo(b.l));
    expect(leaders.length, 3);
    expect(leaders[0].r, closeTo(leaders[1].l, .01), reason: '뺀 칸 자리(4px)는 앞 칸을 늘여 메우고 틈 없이 잇는다');
    expect(leaders[0].r, closeTo(v.xOf(at(404)), .01));
    expect(leaders[2].l - leaders[1].r, closeTo(v.xOf(at(706)) - v.xOf(at(700)) + 1, .01), reason: '순번이 이어지는 실제 빈자리는 그대로 두 칸(0.5px 틈씩)');
  });
}

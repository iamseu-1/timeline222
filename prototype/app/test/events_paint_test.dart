import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/color_mix.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 사건 층이 실제로 그리는 것 — 점의 모양과 색 · 이름 줄의 조각 자리 · 개수 알약 · 글줄 안내선.
// 값은 명세 docs/명세-3단계/02-사건의-표현.md와 기준 덤프(prototype/results/dom/밀집-세부.json)의 숫자다.

const band = 0xabb3c9; // 기준 덤프의 정권 색
const freeLane = 255 << 8, minutePrec = 4 << 8;
final ppm = 32 / bucketMinutes(9);
double px(double pixels) => pixels / ppm;

Map<String, dynamic> row(int id, {int lines = 2}) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': lines, 'rail_top': 108, 'organ_top': -1,
};

(TimelineScene, TimelinePainter) make(void Function(TileBuilder t) fill, {int lines = 2}) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000000000.0, 2000000000.0)
    ..setContentHeight(284);
  final origin = tileOrigin(9, 1).toDouble();
  controller.showRange(origin, origin + (1920 - SceneView.gutter) / ppm);
  final tile = TileBuilder(level: 9, x: 1, chunk: 0)..band(1, 0, 0, px(1700), '별여울국', color: band);
  fill(tile);
  final bytes = tile.build();
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 5}],
      'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0, lines: lines), row(1, lines: lines)]}],
      'epochs': [],
      'categories': [{'id': 1, 'key': 'politics', 'name': '정치', 'color': 0xd4a39b}],
    }),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 1 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
    labelCompute: (input) async => placeLabels(input),
  );
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
}

Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  int calm = 0;
  for (int i = 0; i < 80 && calm < 3; i++) {
    paint(painter);
    await pumpEventQueue();
    final out = scene.labelOutput;
    calm = out != null && out.deferred == 0 && !scene.labelWorker.busy ? calm + 1 : 0;
  }
}

void main() {
  test('점 · 알약의 색은 띠의 색에서 끌어낸다(기준 덤프의 검산과 같은 값)', () {
    // 명세 9.4: 채움 mixSrgb(정권색, 글자색, .80) · 둘레 mixSrgb(정권색, 종이, .15). 종이는 흰색 · 글자색은 검정(HistoryArchive의 토큰 · 2026-10-13)이고,
    // 아래 값들은 브라우저가 같은 식(color-mix)으로 셈한 것과 대조했다.
    expect(mixSrgb(0xffabb3c9, Look.ink, .80).toRadixString(16), 'ff898fa1'); // 브라우저의 color-mix(in srgb, #abb3c9 80%, #000)
    expect(mixSrgb(0xffabb3c9, Look.paper, .15).toRadixString(16), 'fff2f4f7'); // 브라우저의 color-mix(in srgb, #abb3c9 15%, #fff)
    // 하위 수 알약: 바탕 mixSrgb(c, 종이, .22) = #edeef3 · 글자 mixSrgb(c, 글자색, .78) = #858c9d.
    expect(mixSrgb(0xffabb3c9, Look.paper, .22).toRadixString(16), 'ffedeef3');
    expect(mixSrgb(0xffabb3c9, Look.ink, .78).toRadixString(16), 'ff858c9d');
    // 개수 알약: 바탕 mixSrgb(c, 종이, .24) = #ebedf2 · 글자 mixSrgb(c, 글자색, .42) = #484b54.
    expect(mixSrgb(0xffabb3c9, Look.paper, .24).toRadixString(16), 'ffebedf2'); // 브라우저의 color-mix(in srgb, #abb3c9 24%, #fff)
    expect(mixSrgb(0xffabb3c9, Look.ink, .42).toRadixString(16), 'ff484b54');
    // 글줄 안내선: mixOklab(정권색, 글자색, .92)의 38% = #99a0b461.
    expect(withAlpha(mixOklab(0xffabb3c9, Look.ink, .92), .38).toRadixString(16), '6199a0b4');
  });

  test('이름 줄의 조각 자리는 지금 연표의 실측과 같다', () {
    // 밀집-세부 #445(뒤집지 않음): it.x 881.5 · 점 7 · 이름 891 · 연도 1043.52(이름 폭 146.52 · 사이 6).
    final right = labelRun(x: 881.5, side: LabelSide.right, look: freeLane, nameWidth: 146.52, countWidth: 0, yearWidth: 26.59);
    expect(right.nameLeft, closeTo(891, .001));
    expect(right.yearLeft, closeTo(1043.52, .001));
    // #513(뒤집음): it.x 1074.891 · 연도 874 · 이름 906.59 · 점 1069.39.
    final flip = labelRun(x: 1074.891, side: LabelSide.left, look: freeLane, nameWidth: 156.8, countWidth: 0, yearWidth: 26.59);
    expect(flip.nameRight, closeTo(1063.391, .001));
    expect(flip.nameLeft, closeTo(906.591, .001));
    expect(flip.yearRight, closeTo(900.591, .001));
    // #397/#400(하위 수 알약): 이름 끝 1016.63 → 알약 1026.63(사이 6 + 앞 여백 4).
    final counted = labelRun(x: 923.3 - 3.5 + 5 / 2, side: LabelSide.right, look: freeLane | 1 << 19, nameWidth: 82.33, countWidth: 6.23, yearWidth: 0);
    expect(counted.countLeft - counted.nameRight, closeTo(10, .001));
    expect(counted.countRight - counted.countLeft, closeTo(6.23 + 8, .001), reason: '알약 = 글자 + 좌우 안 여백 4px');
  });

  test('점의 모양은 look이 정한다: 보통 · 빈 점 · 점선 빈 점 · 마름모 · 작은 점', () {
    // 화면의 .d 폭(명세 2.1 · 3.3) — 이름 자리 셈이 쓰는 값.
    expect(EventLook.dotWidth(freeLane), 7);
    expect(EventLook.dotWidth(freeLane | 1 << 19), 5, reason: '하위 사건');
    expect(EventLook.dotWidth(freeLane | 1 << 17), 9, reason: '공동 사건');
    expect(EventLook.dotWidth(freeLane | 1 << 22), 10, reason: '미정');
    // 좁은 띠에서 작은 점 · 숨김을 가르는 반지름(명세 4.4).
    expect(EventLook.dotRadius(freeLane, false), 6.5);
    expect(EventLook.dotRadius(freeLane, true), 4.5);
    expect(EventLook.dotRadius(freeLane | 1 << 17, false), 7.5);
    // 이름을 기울이는 것은 추정 · 전승 · 미정뿐이다.
    expect(EventLook.italic(freeLane), isFalse);
    expect(EventLook.italic(freeLane | 1 << 20), isTrue);
    expect(EventLook.italic(freeLane | 1 << 21), isTrue);
    expect(EventLook.italic(freeLane | 1 << 22), isTrue);
  });

  test('화면의 점 상자 폭과 그리는 자리는 css의 값이다(배치가 쓰는 폭과 다르다)', () {
    const treaty = freeLane | 1 << 16, shared = freeLane | 1 << 17, child = freeLane | 1 << 19, unknown = freeLane | 1 << 22;
    // 조약의 마름모는 css가 5 · 6.4 · 4px인데 `_placeRow`는 7px으로 셈한다(명세 2.1 · 8.3-6).
    expect(EventLook.dotBox(treaty), 5);
    expect(EventLook.dotBox(treaty | shared), 5, reason: '제 자리의 조약은 채운 5px 마름모로 되돌린다');
    expect(EventLook.dotBox(treaty | shared | 1 << 18), 6.4, reason: '다른 자리는 속 빈 6.4px');
    expect(EventLook.dotBox(treaty | unknown), 6.4);
    expect(EventLook.dotBox(treaty | child), 4);
    expect(EventLook.dotWidth(treaty | shared), 9, reason: '자리 셈은 조약을 따로 재지 않는다');
    // 좁은 띠 · 조감(css 1789~1795).
    expect(EventLook.dotBox(freeLane, small: true), 5);
    expect(EventLook.dotBox(child, small: true), 4);
    expect(EventLook.dotBox(shared, small: true), 7);
    expect(EventLook.dotBox(unknown, small: true), 7);
    expect(EventLook.dotBox(treaty, small: true), 4);
    // 점 가운데 = 뒤집지 않으면 it.x − 3.5 + 폭/2 · 뒤집으면 it.x + 1.5 − 폭/2 · 작은 점은 it.x − 2.5 + 폭/2(명세 9.4).
    expect(EventLook.dotDx(freeLane), 0);
    expect(EventLook.dotDx(freeLane, side: LabelSide.left), -2);
    expect(EventLook.dotDx(shared), 1);
    expect(EventLook.dotDx(shared, side: LabelSide.left), -3);
    expect(EventLook.dotDx(unknown), 1.5);
    expect(EventLook.dotDx(child), -1);
    expect(EventLook.dotDx(freeLane, small: true), 0);
    // 기준 덤프 #344/#345: 조약+공동+제자리 — 상자 [769.59, 7] → it.x 773.09 · 점 가운데 772.09.
    expect(773.09 + EventLook.dotDx(treaty | shared), closeTo(772.09, .001));
    // 그 이름은 점 상자 5px 뒤에 붙는다(it.x − 3.5 + 5 + 6).
    expect(labelRun(x: 773.09, side: LabelSide.right, look: treaty | shared, nameWidth: 50, countWidth: 0, yearWidth: 0).nameLeft, closeTo(780.59, .001));
  });

  test('고르기 · 강조의 밝기가 이름의 짙기에 곱해진다', () async {
    final (scene, painter) = make((t) => t
      ..event(11, 0, px(200), '고른 일', bits: 3 | Tile.counted, look: freeLane, rail: minutePrec, band: 1)
      ..event(12, 0, px(700), '같은 줄의 일', bits: 3 | Tile.counted, look: freeLane, rail: minutePrec, band: 1)
      ..event(13, 1, px(1100), '다른 줄의 일', bits: 3 | Tile.counted, look: freeLane, rail: minutePrec));
    await settle(scene, painter);
    double alphaOf(String name) => painter.debugLabels.firstWhere((l) => l.kind == 'event' && l.text == name).alpha;
    expect(alphaOf('고른 일'), 1);
    // 고르기(is-picked): 고른 사건 1 · 같은 줄 .7 · 나머지 .45(명세 06 3-1).
    em.Emphasis.of(scene).set(const em.Look(event: 11, row: 0));
    paint(painter);
    expect(alphaOf('고른 일'), 1);
    expect(alphaOf('같은 줄의 일'), closeTo(.7, 1e-6));
    expect(alphaOf('다른 줄의 일'), closeTo(.45, 1e-6));
    expect(em.Emphasis.of(scene).dotScale(11), 1.25, reason: '고른 사건의 점은 1.25배');
    // 강조(is-filtered): 강조 밖은 .2.
    em.Emphasis.of(scene).set(const em.Look(events: {12}));
    paint(painter);
    expect(alphaOf('같은 줄의 일'), 1);
    expect(alphaOf('고른 일'), closeTo(.2, 1e-6));
    em.Emphasis.of(scene).clear();
  });

  test('점과 이름과 개수 알약을 한 장면에 그리고, 도형은 항목마다 따로 그리지 않는다', () async {
    final (scene, painter) = make((t) {
      t
        ..event(11, 0, px(200), '별여울의 첫 기록', bits: 3 | Tile.counted, look: freeLane, rail: minutePrec, band: 1)
        ..event(12, 0, px(700), '추정 연대의 일', bits: 2 | Tile.counted, look: freeLane | 1 << 20, rail: minutePrec, band: 1)
        ..event(13, 0, px(900), '조약의 날', bits: 3 | Tile.counted, look: freeLane | 1 << 16, rail: minutePrec, band: 1)
        ..event(14, 0, px(1100), '연대 미정의 일', bits: 3 | Tile.counted, look: freeLane | 1 << 22, rail: minutePrec, band: 1)
        ..pill(0, px(1400), px(1432), 12);
    });
    await settle(scene, painter);
    expect(painter.debugDots.map((d) => d.eventId).toList()..sort(), [11, 12, 13, 14]);
    final names = painter.debugLabels.where((l) => l.kind == 'event').map((l) => l.text).toSet();
    expect(names, {'별여울의 첫 기록', '추정 연대의 일', '조약의 날', '연대 미정의 일'});
    expect(painter.debugLabels.where((l) => l.kind == 'pill').single.text, '12', reason: '대표가 없는 통은 개수 알약으로');
    // 그린 것은 모두 묶음(네모 · 조각 · 글자)에 모인다 — 항목마다 canvas를 부르지 않는다.
    expect(scene.stats.shapes, greaterThan(0));
  });

  test('글줄 안내선은 띠 안에 글줄 수 − 1개, 띠 테두리에서 14px 들여 그린다', () async {
    final (scene, painter) = make((t) => t..event(11, 0, px(200), '하나', bits: 3 | Tile.counted, look: freeLane, rail: minutePrec, band: 1), lines: 3);
    await settle(scene, painter);
    // 띠는 0 ~ 1700px(왼쪽 칸 뒤) — 안내선은 그 안쪽 15px씩 들어간다. 글줄이 셋이면 안내선은 둘.
    final geo = scene.layout.geo(0);
    expect(geo.textLines, 3);
    expect(scene.stats.shapes, greaterThan(0));
  });

  test('띠를 못 찾은 사건은 분류 색으로 떨어진다', () async {
    final (scene, painter) = make((t) => t..event(11, 1, px(200), '띠 밖의 일', bits: 3 | Tile.counted, look: freeLane, rail: minutePrec));
    await settle(scene, painter);
    final batch = scene.labelBatch!;
    final at = [for (int i = 0; i < batch.input.at.length; i++) if (batch.input.eventId[i] == 11) i].single;
    expect(batch.colorOf(at), 0xffd4a39b, reason: '둘째 줄에는 띠가 없다 — 분류 0번의 색');
    expect(batch.input.bandLo[at].isFinite, isFalse);
  });

  test('이름 옆 날짜 글은 해 눈금에서 앞의 해만 남는다', () async {
    final (scene, painter) = make((t) => t
      ..event(11, 0, px(200), '해솔의 날', bits: 3 | Tile.counted, look: freeLane, rail: minutePrec, band: 1, label: '827년 5월 12일'));
    await settle(scene, painter);
    final batch = scene.labelBatch!;
    final at = [for (int i = 0; i < batch.input.at.length; i++) if (batch.input.eventId[i] == 11) i].single;
    expect(batch.date(at), '827년');
    expect(painter.debugLabels.where((l) => l.kind == 'year').single.text, '827년');
  });

  test('글줄이 하나뿐인 줄에는 날짜 글이 붙지 않는다', () async {
    final (scene, painter) = make(
      (t) => t..event(11, 0, px(200), '해솔의 날', bits: 3 | Tile.counted, look: freeLane, rail: minutePrec, band: 1, label: '827년'),
      lines: 1,
    );
    await settle(scene, painter);
    expect(painter.debugLabels.where((l) => l.kind == 'year'), isEmpty);
  });
}

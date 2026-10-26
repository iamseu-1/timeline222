import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/rails.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

/// 구역 33~36의 `b` 5~6비트 = 중요도 · `d`의 8비트 위 = 그 줄에서 단을 고르는 차례 + 1(계약 6-7 가).
int imp(int importance) => importance << 5;
int rankOf(int rank) => (rank + 1) << 8;

// 기간 사건의 막대와 표식(구역 33~36)을 검사한다. 값의 근거는 docs/명세-3단계/03-띠에-덧붙는-것.md 1절과
// 기준 덤프(prototype/results/dom/밀집-세부.json)의 숫자다.

const m = 1000000.0;
final ppm = 32 / bucketMinutes(9); // 통 32px → 단계 9
double px(double pixels) => pixels / ppm;

/// 2판 줄 하나(굳은 자리): 글줄 둘 · 기간 막대 칸은 줄 안 108px에서 시작한다.
Map<String, dynamic> row(int id) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

/// 줄 0의 막대 칸 단 [lane]의 세로 가운데(배치 px): 날짜 칸 아래 railTop 108 + 3.5 + 단 × 7.
double railY(TimelineScene scene, int lane) {
  final v = scene.controller.view;
  return v.head - v.top + 108 + 3.5 + lane * 7;
}

/// 띠 하나(줄 0, 0 ~ [bandPx] — 기본 1700px)에 기간 막대 칸의 항목을 얹은 장면.
(TimelineScene, TimelinePainter) make(void Function(TileBuilder t) fill, {double bandPx = 1700}) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(284);
  final origin = tileOrigin(9, 1).toDouble();
  controller.showRange(origin, origin + (1920 - SceneView.gutter) / ppm);
  final tile = TileBuilder(level: 9, x: 1, chunk: 0)..band(1, 0, 0, px(bandPx), '별여울국', color: 0xabb3c9);
  fill(tile);
  final bytes = tile.build();
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 5}],
      'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1)]}],
      'epochs': [],
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
  for (int i = 0; i < 60; i++) {
    paint(painter);
    await pumpEventQueue();
  }
}

List<RailMark> marks(TimelinePainter painter, String kind) => (painter.debugSink.notes[kind] ?? const []).cast<RailMark>();

void main() {
  // 0.1.1 떼어서 살림(감독 고름 2026-10-26): 좁은 막대 구슬(결함 49)은 route에서 떼어 스위치 mend — 이 파일은 route 끔 기본 그대로 돌아 고침이 route 없이 서는지 지킨다.
  tearDown(PaintPick.reset);

  test('기간 막대는 레일의 제 단에 가는 선으로, 양 끝에 세로바를 둔다', () async {
    // 자료의 단은 1이지만 그 줄에 겹치는 막대가 없으므로 화면은 빈 첫 단(0)을 고른다(지금 연표의 pickLevel).
    final (scene, painter) = make((t) => t.item(RailLook.secRail, 10, 0, px(300), px(620), ref: 500, color: 0xabb3c9, name: '긴 공사', a: 1, b: imp(3), d: rankOf(0)));
    await settle(scene, painter);
    final bar = marks(painter, '막대').single;
    expect(bar.kind, '기간');
    expect(bar.eventId, 500);
    expect(bar.lane, 0);
    expect(bar.x, closeTo(SceneView.gutter + 300, .01));
    expect(bar.width, closeTo(320, .01));
    expect(bar.y, closeTo(railY(scene, 0), .01), reason: 'railTop + 3.5 + 단 × 7');
    expect(bar.height, 2, reason: '가는 선은 높이 2px');
    // 선택 판정 · 그림 대조가 읽는 기록에도 같은 자리가 남는다.
    final drawn = painter.debugBars.single;
    expect(drawn.eventId, 500);
    expect(drawn.rect.top, closeTo(railY(scene, 0) - 1, .01));
  });

  test('막대의 문턱은 화면 2px이다 — 그보다 좁으면 막대가 아니라 점이고, 최소 폭은 3px이다(스위치 mend를 끈 예전 그림)', () async {
    PaintPick.mend = false;
    final (wide, widePainter) = make((t) => t.item(RailLook.secRail, 10, 0, px(300), px(302.5), ref: 500, color: 0xabb3c9, a: 0));
    await settle(wide, widePainter);
    expect(marks(widePainter, '막대').single.width, closeTo(3, .01), reason: '2.5px 기간도 막대는 3px');

    final (narrow, narrowPainter) = make((t) => t.item(RailLook.secRail, 10, 0, px(300), px(302), ref: 500, color: 0xabb3c9, a: 0));
    await settle(narrow, narrowPainter);
    expect(marks(narrowPainter, '막대'), isEmpty, reason: '2px 이하는 막대가 아니다');
    expect(marks(narrowPainter, '구슬'), isEmpty, reason: '실의 길이가 3px 미만이면 구슬도 그리지 않는다');
  });

  // 0.1.1 조사 결함 49(스위치 route): 아주 짧은 사건이 3px 막대 + 6px 세로바의 'H' 꼴이었고, 단이 모자라면 이웃 막대가 같은 단에 세로바 3px 사이로 붙었다.
  test('6px보다 좁은 막대는 막대 + 세로바(H 꼴) 대신 시작 자리의 구슬 하나 — 2px 이하는 예전처럼 점 사건 · 6px 넘으면 막대', () async {
    final (short, shortPainter) = make((t) => t.item(RailLook.secRail, 10, 0, px(300), px(305), ref: 500, color: 0xabb3c9, a: 0));
    await settle(short, shortPainter);
    expect(marks(shortPainter, '막대'), isEmpty, reason: '5px — H 꼴 대신');
    final bead = marks(shortPainter, '구슬').single;
    expect((bead.kind, bead.eventId, bead.x, bead.lane), ('통설구슬', 500, SceneView.gutter + 300, 0));
    expect(marks(shortPainter, '실'), isEmpty, reason: '이설이 없으니 실 없이 구슬만');

    final (long, longPainter) = make((t) => t.item(RailLook.secRail, 10, 0, px(300), px(306.5), ref: 500, color: 0xabb3c9, a: 0));
    await settle(long, longPainter);
    expect(marks(longPainter, '막대').single.width, closeTo(6.5, .01), reason: '6px 넘으면 막대');

    final (tiny, tinyPainter) = make((t) => t.item(RailLook.secRail, 10, 0, px(300), px(302), ref: 500, color: 0xabb3c9, a: 0));
    await settle(tiny, tinyPainter);
    expect(marks(tinyPainter, '막대'), isEmpty);
    expect(marks(tinyPainter, '구슬'), isEmpty, reason: '2px 이하는 그대로 점 사건');

    // 단이 둘인 줄에 겹치는 막대 셋: 셋째는 빈 단이 없어 가장 덜 겹치는 단에 — 긴 막대는 그대로 막대(구슬로 줄이면 기간이 사라진다 · 감독 확인 몫).
    final (full, fullPainter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(600), ref: 500, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(0));
      t.item(RailLook.secRail, 11, 0, px(400), px(700), ref: 501, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(1));
      t.item(RailLook.secRail, 12, 0, px(604), px(680), ref: 502, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(2));
    });
    await settle(full, fullPainter);
    expect({for (final b in marks(fullPainter, '막대')) b.eventId}, {500, 501, 502});
    expect(marks(fullPainter, '구슬'), isEmpty);

    // 타일 경계에서 잘린 긴 막대의 2 ~ 6px 끝 조각은 막대 그대로 — 조각의 폭은 막대의 폭이 아니다(구슬이 타일 경계에 홀로 서면 안 된다).
    for (final (from, to, cut) in [(300.0, 304.0, Tile.clipLeft), (1000.0, 1004.0, Tile.clipRight)]) {
      final (piece, piecePainter) = make((t) => t.item(RailLook.secRail, 10, 0, px(from), px(to), flags: cut, ref: 500, color: 0xabb3c9, a: 0));
      await settle(piece, piecePainter);
      expect(marks(piecePainter, '막대').single.width, closeTo(4, .01), reason: '잘린 4px 조각($cut)은 막대');
      expect(marks(piecePainter, '구슬'), isEmpty, reason: '잘린 조각($cut)에 구슬이 서지 않는다');
    }

    // 스위치를 끄면 예전처럼 막대(H 꼴).
    PaintPick.mend = false;
    final (oldShort, oldPainter) = make((t) => t.item(RailLook.secRail, 10, 0, px(300), px(305), ref: 500, color: 0xabb3c9, a: 0));
    await settle(oldShort, oldPainter);
    expect(marks(oldPainter, '막대').single.width, closeTo(5, .01));
    expect(marks(oldPainter, '구슬'), isEmpty);
  });

  test('막대와 표식은 제 정권 띠 안쪽 5px에 갇힌다', () async {
    // 왼쪽 칸이 240(리메이크 2부)이라 띠가 화면 안에서 끝나게 1600px로 줄인다.
    final (scene, painter) = make((t) => t.item(RailLook.secRail, 10, 0, -px(200), px(1900), ref: 500, color: 0xabb3c9, a: 0), bandPx: 1600);
    await settle(scene, painter);
    final bar = marks(painter, '막대').single;
    // 띠는 0 ~ 1600px(화면 240 ~ 1840)이므로 245 ~ 1835에 갇힌다.
    expect(bar.x, closeTo(SceneView.gutter + 5, .01));
    expect(bar.x + bar.width, closeTo(SceneView.gutter + 1595, .01));
  });

  test('조약은 겹줄이고, 발효 눈금은 막대의 양 끝에서 3px보다 안쪽일 때만 마름모로 찍는다', () async {
    final (scene, painter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(620), ref: 500, color: 0xabb3c9, name: '흰계단 휴전', a: 2, b: imp(3) | 2, d: rankOf(0));
      t.item(RailLook.secEffect, 11, 0, px(400), px(620), ref: 500, color: 0xabb3c9, a: 2, b: imp(3), d: rankOf(0));
      // 막대의 끝에서 2px 안쪽 — 그리지 않는다.
      t.item(RailLook.secEffect, 12, 0, px(618), px(620), ref: 501, color: 0xabb3c9, a: 2, b: imp(3), d: rankOf(1));
    });
    await settle(scene, painter);
    final bar = marks(painter, '막대').single;
    expect(bar.kind, '조약');
    expect(bar.height, 4, reason: '겹줄은 높이 4px(위아래 1px 두 줄)');
    final effect = marks(painter, '발효').single;
    expect(effect.x, closeTo(SceneView.gutter + 400, .01));
    // 자료의 단은 2지만 그 줄에 겹치는 막대가 없어 화면은 빈 첫 단(0)을 고른다. 발효 눈금도 같은 단에 붙는다.
    expect(bar.lane, 0);
    expect(effect.y, closeTo(railY(scene, 0), .01));
    expect(effect.width, closeTo(5.657, .01), reason: '4px 네모를 45° 돌린 외접 네모');
  });

  test('이설의 점선 세로바는 통설과 4px 안이면 4px 바깥으로 비킨다', () async {
    final (scene, painter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(620), ref: 500, color: 0xabb3c9, a: 0);
      t.item(RailLook.secAlt, 11, 0, px(260), px(260), ref: 500, color: 0xabb3c9, name: '이른 시작설', a: 0, b: 8);
      t.item(RailLook.secAlt, 12, 0, px(302), px(302), ref: 500, color: 0xabb3c9, name: '거의 같은 설', a: 0, b: 8);
    });
    await settle(scene, painter);
    final alts = marks(painter, '이설').map((a) => a.x).toList()..sort();
    expect(alts.length, 2);
    expect(alts[0], closeTo(SceneView.gutter + 260, .01));
    expect(alts[1], closeTo(SceneView.gutter + 304, .01), reason: '통설(300)과 2px 차이라 4px 바깥으로');
    expect(marks(painter, '이설').first.height, 9);
  });

  test('점 사건의 이설은 점선 실에 꿴 구슬이 된다 — 연대 폭은 그리지 않는다(2026-10-13 "한 점으로만")', () async {
    final (scene, painter) = make((t) {
      t.event(700, 0, px(500), '연대 다툼', bits: 2);
      t.item(RailLook.secAlt, 11, 0, px(460), px(460), ref: 700, color: 0xabb3c9, name: '광부 구술설', a: 0);
      t.item(RailLook.secAlt, 12, 0, px(497), px(497), ref: 700, color: 0xabb3c9, name: '거의 같은 설', a: 0);
      t.item(RailLook.secFuzz, 13, 0, px(690), px(710), ref: 700, color: 0xabb3c9, a: 0);
    });
    await settle(scene, painter);
    final beads = marks(painter, '구슬');
    expect(beads.map((b) => b.kind).toList(), ['통설구슬', '이설구슬'], reason: '통설과 3px 차이인 이설 구슬은 합쳐진다');
    expect(beads[0].x, closeTo(SceneView.gutter + 500, .01));
    expect(beads[1].x, closeTo(SceneView.gutter + 460, .01));
    expect(beads[0].y, closeTo(railY(scene, 0), .01));
    expect(marks(painter, '눈금'), isEmpty, reason: '날짜를 정확히 모르는 점 사건은 범위(연대 폭의 눈금)를 그리지 않는다');
    final thread = marks(painter, '실').single;
    expect(thread.x + thread.width, closeTo(SceneView.gutter + 500, .01), reason: '실은 구슬 사이만 — 연대 폭(690~710)까지 늘지 않는다');
  });

  test('연대 폭만 적은 점 사건은 막대 칸에 아무것도 없다 — 점 하나로만', () async {
    final (scene, painter) = make((t) {
      t.event(700, 0, px(500), '연대 다툼', bits: 2);
      t.item(RailLook.secFuzz, 13, 0, px(460), px(560), ref: 700, color: 0xabb3c9, a: 0);
    });
    await settle(scene, painter);
    expect(marks(painter, '눈금'), isEmpty);
    expect(marks(painter, '실'), isEmpty);
    expect(marks(painter, '구슬'), isEmpty);
  });

  // '이설' 표시 체크(SceneMarks.showAlt)를 끄면 지금 연표는 `const alts = this.showAlt && !it.sec ? HT.datedAlts(e) : []`
  // (js/timeline.js 7063)로 이설을 통째로 버린다 — 세로바 · 연결선 · 이설 구슬이 없어지고, 단을 고를 때 재는
  // 자리(xs)에도 들지 않으며, 이설뿐이던 사건은 막대 칸에 아무것도 그리지 않는다(7065의 `ranged || fuzzy || alts.length`).
  test('이설 표시를 끄면 세로바가 사라진다 — 막대는 그대로', () async {
    final (scene, painter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(620), ref: 500, color: 0xabb3c9, a: 0);
      t.item(RailLook.secAlt, 11, 0, px(260), px(260), ref: 500, color: 0xabb3c9, name: '이른 시작설', a: 0, b: 8);
    });
    SceneMarks.of(scene).showAlt = false;
    await settle(scene, painter);
    expect(marks(painter, '이설'), isEmpty);
    expect(marks(painter, '막대').length, 1);
  });

  test('이설 표시를 끄면 이설뿐인 점 사건은 실도 구슬도 없다', () async {
    final (scene, painter) = make((t) {
      t.event(700, 0, px(500), '연대 다툼', bits: 2);
      t.item(RailLook.secAlt, 11, 0, px(460), px(460), ref: 700, color: 0xabb3c9, name: '광부 구술설', a: 0);
    });
    SceneMarks.of(scene).showAlt = false;
    await settle(scene, painter);
    expect(marks(painter, '구슬'), isEmpty);
    expect(marks(painter, '실'), isEmpty);
  });

  test('이설 표시를 끄면 단 고르기의 자리에서도 이설이 빠진다', () async {
    // 500의 이설(150px)이 501의 막대(100~250)와 겹쳐, 이설을 켜면 둘이 같은 단에 설 수 없다.
    void fill(TileBuilder t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(620), ref: 500, color: 0xabb3c9, a: 0, b: imp(2), d: rankOf(0));
      t.item(RailLook.secAlt, 11, 0, px(150), px(150), ref: 500, color: 0xabb3c9, name: '이른 시작설', a: 0, b: imp(2) | 8, d: rankOf(0));
      t.item(RailLook.secRail, 12, 0, px(100), px(250), ref: 501, color: 0xabb3c9, a: 0, b: imp(2), d: rankOf(1));
    }

    final (on, onPainter) = make(fill);
    await settle(on, onPainter);
    final lit = {for (final b in marks(onPainter, '막대')) b.eventId: b.lane};
    expect(lit[500], 0);
    expect(lit[501], 1, reason: '이설(150px)이 500의 자리를 왼쪽으로 넓혀 501이 다음 단으로 밀린다');

    final (off, offPainter) = make(fill);
    SceneMarks.of(off).showAlt = false;
    await settle(off, offPainter);
    final dark = {for (final b in marks(offPainter, '막대')) b.eventId: b.lane};
    expect(dark[500], 0);
    expect(dark[501], 0, reason: '이설을 끄면 겹치지 않으므로 둘 다 첫 단');
  });

  test('타일 경계에서 잘린 막대는 정수 px에서 만나 하나로 이어진다', () async {
    final (scene, painter) = make((t) => t.item(RailLook.secRail, 10, 0, px(300.4), px(620.7), ref: 500, color: 0xabb3c9, a: 0, flags: Tile.clipLeft | Tile.clipRight));
    await settle(scene, painter);
    final bar = marks(painter, '막대').single;
    expect(bar.x, closeTo(SceneView.gutter + 300, .01), reason: '잘린 쪽은 정수 px으로 — 이웃 타일의 조각과 어긋나지 않게');
    expect(bar.x + bar.width, closeTo(SceneView.gutter + 621, .01));
  });

  test('접힌 하위 사건의 막대는 그리지 않는다 — 부모 기간이 90px보다 좁으면 접힌다', () async {
    final (open, openPainter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(420), ref: 500, color: 0xabb3c9, a: 0);
      t.item(RailLook.secChild, 11, 0, px(200), px(500), ref: 500, color: 0xabb3c9, name: '부모', b: 90, c: 80);
    });
    await settle(open, openPainter);
    expect(marks(openPainter, '막대').length, 1, reason: '부모가 300px이라 펼쳐져 있다');

    final (shut, shutPainter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(340), ref: 500, color: 0xabb3c9, a: 0);
      t.item(RailLook.secChild, 11, 0, px(290), px(350), ref: 500, color: 0xabb3c9, name: '부모', b: 90, c: 80);
    });
    await settle(shut, shutPainter);
    expect(marks(shutPainter, '막대'), isEmpty, reason: '부모가 60px이라 접혀 있다');
  });

  test('색은 지금 연표의 css 식 그대로다 — 기준 덤프의 값과 같다', () {
    // 기간 막대: 몸통 edge-soft · 양 끝 세로바 edge. 띠 색 0xabb3c9에 ink(#000)를 섞은 값 — 브라우저의 color-mix(in oklab, #abb3c9 92% · 84%, #000)와 같다.
    expect(RailLook.edgeSoft(0xabb3c9), 0xff99a0b4);
    expect(RailLook.edge(0xabb3c9), 0xff878d9f);
  });

  test('단은 배율마다 다시 고른다 — 자료의 단이 같아도 화면에서 겹치면 다음 단으로', () async {
    // 둘 다 자료의 단은 0이지만 화면에서 겹친다(300~600 · 400~700). 지금 연표의 pickLevel과 같은 차례(차례 0 → 1).
    final (scene, painter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(600), ref: 500, color: 0xabb3c9, name: '앞선 싸움', a: 0, b: imp(3), d: rankOf(0));
      t.item(RailLook.secRail, 11, 0, px(400), px(700), ref: 501, color: 0xabb3c9, name: '뒤따른 싸움', a: 0, b: imp(3), d: rankOf(1));
    });
    await settle(scene, painter);
    final bars = {for (final b in marks(painter, '막대')) b.eventId: b.lane};
    expect(bars[500], 0);
    expect(bars[501], 1, reason: '자료는 둘 다 단 0이지만 화면에서 겹쳐 비어 있는 단으로 옮긴다');

    // 떨어뜨려 놓으면 둘 다 단 0이다.
    final (apart, apartPainter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(400), ref: 500, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(0));
      t.item(RailLook.secRail, 11, 0, px(600), px(700), ref: 501, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(1));
    });
    await settle(apart, apartPainter);
    expect(marks(apartPainter, '막대').every((b) => b.lane == 0), isTrue);
  });

  test('단 고르기의 차례는 고른 것 · 강조 · 중요도 · 자료의 차례 순이다', () async {
    void fill(TileBuilder t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(600), ref: 500, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(0));
      t.item(RailLook.secRail, 11, 0, px(400), px(700), ref: 501, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(1));
    }

    // 뒤 사건을 고르면 그것이 먼저 자리를 잡아 단 0을 가져간다(js/timeline.js _placeRow의 prio).
    final (scene, painter) = make(fill);
    em.Emphasis.of(scene)
      ..reduceMotion = true
      ..set(const em.Look(event: 501));
    await settle(scene, painter);
    final bars = {for (final b in marks(painter, '막대')) b.eventId: b.lane};
    expect(bars[501], 0);
    expect(bars[500], 1);
  });

  test('다른 것을 고른 동안 막대 칸은 .45로 흐려지고 고른 사건만 1이다', () async {
    final (scene, painter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(600), ref: 500, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(0));
      t.item(RailLook.secRail, 11, 0, px(800), px(1000), ref: 501, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(1));
      t.item(RailLook.secEffect, 12, 0, px(850), px(1000), ref: 501, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(1));
    });
    em.Emphasis.of(scene)
      ..reduceMotion = true
      ..set(const em.Look(event: 500));
    await settle(scene, painter);
    final bars = {for (final b in marks(painter, '막대')) b.eventId: b.alpha};
    expect(bars[500], 1, reason: '고른 사건은 밝다');
    expect(bars[501], closeTo(.45, .001), reason: 'css:369의 .tl.is-picked .tl-rail');
    expect(marks(painter, '발효').single.alpha, closeTo(.45, .001), reason: 'css:1491의 .tl.is-picked .tl-eff');
  });

  test('조감에는 기간 막대 칸이 아예 없다', () async {
    final (scene, painter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(600), ref: 500, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(0));
      t.event(700, 0, px(500), '연대 다툼', bits: 2);
      t.item(RailLook.secAlt, 11, 0, px(460), px(460), ref: 700, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(1));
    });
    scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
    await settle(scene, painter);
    expect(marks(painter, '막대'), isEmpty);
    expect(marks(painter, '구슬'), isEmpty);
  });

  test('연대 폭의 빗금 위에 막대를 다시 그린다 — 지금 연표는 막대(z 2)가 위다', () async {
    final (scene, painter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(620), ref: 500, color: 0xabb3c9, a: 0, b: imp(3) | 4, d: rankOf(0));
      t.item(RailLook.secFuzz, 11, 0, px(280), px(360), ref: 500, color: 0xabb3c9, a: 0, b: imp(3), c: 1, d: rankOf(0));
    });
    await settle(scene, painter);
    final over = marks(painter, '덧그림').single;
    // 빗금은 280~360이지만 막대는 300에서 시작하므로 겹치는 토막은 300~360이다.
    expect(over.x, closeTo(SceneView.gutter + 300, .01));
    expect(over.x + over.width, closeTo(SceneView.gutter + 360, .01));
  });

  test('점선 실은 구슬의 양 끝을 잇고, 고르면 구슬 위에 연도가 뜬다', () async {
    final (scene, painter) = make((t) {
      t.event(700, 0, px(500), '연대 다툼', bits: 2);
      t.item(RailLook.secAlt, 11, 0, px(440), px(440), ref: 700, color: 0xabb3c9, name: '광부 구술설', a: 0, b: imp(3), d: rankOf(0));
    });
    scene.selectedEventId = 700;
    await settle(scene, painter);
    final thread = marks(painter, '실').single;
    expect(thread.x, closeTo(SceneView.gutter + 440, .01));
    expect(thread.width, closeTo(60, .01));
    // 구슬 위 연도(css:854): 9px · 구슬 둘 → 글자 둘.
    final years = painter.debugLabels.where((l) => l.kind == 'bead').toList();
    expect(years.length, 2);
  });

  test('맞히기는 막대 · 구슬 · 이설 · 발효를 집는다', () async {
    final (scene, painter) = make((t) {
      t.item(RailLook.secRail, 10, 0, px(300), px(620), ref: 500, color: 0xabb3c9, name: '흰계단 휴전', a: 0, b: imp(3) | 2, d: rankOf(0));
      t.item(RailLook.secEffect, 11, 0, px(400), px(620), ref: 500, color: 0xabb3c9, a: 0, b: imp(3), d: rankOf(0));
    });
    await settle(scene, painter);
    final bar = painter.rails.hitRails(SceneView.gutter + 500, railY(scene, 0));
    expect(bar?.part, RailPart.bar);
    expect(bar?.eventId, 500);
    expect(bar?.band, 1, reason: '그 사건이 든 띠의 번호');
    expect(bar?.row, 0);
    final effect = painter.rails.hitRails(SceneView.gutter + 400, railY(scene, 0));
    expect(effect?.part, RailPart.effect, reason: '발효 마름모는 막대보다 위다');
    expect(painter.rails.hitRails(SceneView.gutter + 100, railY(scene, 0)), isNull);
  });
}

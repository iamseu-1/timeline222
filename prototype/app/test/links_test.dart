import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/paint/links.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/scopes.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/reserved.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 관계선 층(lib/scene/paint/links.dart)의 검사. 값의 뜻은 docs/계약-아카이브-3단계.md 6-10절, 자리는 docs/명세-3단계/04-관계선.md.
// 그림의 숫자는 기준 덤프(results/dom/전체.json · results/dom-r4/승계-800-1150.json)에서 옮겼다.

const m = 1000000.0; // 백만 분

/// 구역 20(네모)의 a 비트.
const sqUnkS = 1, sqUnkE = 2, sqOngoing = 4, sqSeamL = 8, sqSeamR = 16, sqRangeS = 32, sqRangeE = 64;

/// 구역 21(승계선)의 a 비트.
const lkDown = 1 << 4, lkQFirst = 1 << 5, lkSeam = 1 << 6;

Map<String, dynamic> row(int id, {int lines = 2}) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': lines, 'rail_top': 108, 'organ_top': -1,
};

SceneLayout layout({int lines = 2}) => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0, lines: lines), row(1, lines: lines)]}],
});

/// 같은 줄에서 t에 맞닿는 두 띠와 그 승계 한 건. [kind]는 0 직접 · 3 부분.
Uint8List seamTile({required double t, int kind = 0, int degree = 0}) {
  final b = TileBuilder(level: 9, x: 0, chunk: 0)
    ..band(1, 0, t - 20 * m, t, '앞 나라')
    ..band(2, 0, t, t + 20 * m, '뒤 나라')
    ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9, a: sqSeamR)
    ..item(LinkLayer.secSquare, 102, 0, t, t + 20 * m, ref: 2, name: '뒤 나라', color: 0xa295aa, a: sqSeamL)
    ..item(LinkLayer.secLink, 201, 0, t, t, ref: 1, b: 2, color: 0xabb3c9, a: kind | (degree << 2) | lkQFirst | lkSeam);
  return b.build();
}

(TimelineScene, TimelinePainter) make(Uint8List bytes, {int lines = 2}) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(284);
  final scene = TimelineScene(
    controller: controller,
    layout: layout(lines: lines),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  controller.showRange(10 * m, 20 * m);
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

Future<List<String>> notesOf(TimelineScene scene, TimelinePainter painter, String kind) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }
  return [for (final v in painter.debugSink.notes[kind] ?? const <Object>[]) '$v'];
}

/// '1052.3,636.0,5.0,0.0' 같은 기록을 숫자로.
List<double> nums(String text) => [for (final s in text.split(RegExp('[ ,]'))) double.tryParse(s) ?? double.nan].where((v) => !v.isNaN).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('점선 박자(beatRuns)', () {
    test('박자가 없으면 한 획이다', () {
      expect(LinkLayer.beatRuns(10, 20, null), [(10.0, 20.0)]);
      expect(LinkLayer.beatRuns(10, 10.2, null), isEmpty); // 0.5px보다 짧으면 없음
    });

    test('칠을 늘여 양 끝이 늘 칠로 끝난다 — 기준 덤프의 다리 칠 3px', () {
      // 명세 9-3: beatRuns(mid-2, xa, [5,4]) — len 3 · n = round(7/9) = 1 · d = 3 → 한 획 3px
      final runs = LinkLayer.beatRuns(0, -3, const [5.0, 4.0]);
      expect(runs.length, 1);
      expect(runs.first.$2 - runs.first.$1, closeTo(3, 1e-9));
    });

    test('긴 구간은 칠과 빔이 번갈아 나오고 끝이 칠이다', () {
      final runs = LinkLayer.beatRuns(0, 50, const [5.0, 4.0]);
      expect(runs.length, 6); // round((50+4)/9) = 6
      expect(runs.first.$1, closeTo(0, 1e-9));
      expect(runs.last.$2, closeTo(50, 1e-9));
      for (final r in runs) {
        expect(r.$2 - r.$1, closeTo((50 - 4 * 5) / 6, 1e-9));
      }
    });
  });

  group('제 그림판의 조각', () {
    test('굽이 조각은 낱장 안에 있고 사분면마다 자리가 다르다', () {
      for (int i = 0; i < LinkSprites.radii.length; i++) {
        final seen = <Rect>{};
        for (int q = 0; q < 4; q++) {
          final r = LinkSprites.arc(i, q);
          expect(r.right, lessThanOrEqualTo(8 * 24.0));
          expect(r.bottom, lessThanOrEqualTo(4 * 24.0));
          expect(r.width, closeTo(LinkSprites.radii[i] + LinkSprites.stroke / 2, 1e-9));
          expect(seen.add(r), isTrue);
        }
      }
      // 네모 · 고리 조각도 낱장 안에.
      for (final r in [LinkSprites.squareFill, LinkSprites.squareEdge1, LinkSprites.squareEdge16, LinkSprites.dashRing, LinkSprites.ring275, LinkSprites.ringFill]) {
        expect(r.right, lessThanOrEqualTo(8 * 24.0));
        expect(r.bottom, lessThanOrEqualTo(4 * 24.0));
      }
      // 꼬리표 갈래 E의 구멍(칠 · 테)과 꼬리 마름모: 7×7 상자 셋이 맨 아랫줄(여덟째 줄 — 가는 굽이 줄 아래)에 서로 겹치지 않게.
      final holes = [LinkSprites.holeFill, LinkSprites.holeRing, LinkSprites.diamond];
      for (final r in holes) {
        expect(r.width, LinkSprites.holeBox);
        expect(r.height, LinkSprites.holeBox);
        expect(r.top, greaterThanOrEqualTo(7 * 24.0));
        expect(r.bottom, lessThanOrEqualTo(8 * 24.0));
        expect(r.right, lessThanOrEqualTo(8 * 24.0));
      }
      expect(holes.toSet().length, 3);
      expect(holes[0].overlaps(holes[1]) || holes[1].overlaps(holes[2]) || holes[0].overlaps(holes[2]), isFalse);
    });

    // 1.6짜리 굽이를 1px 선에 쓰면 굽이만 굵어 보인다 — 가는 선은 굵기 1의 조각을 따로 쓴다.
    test('가는 선(부분 승계)의 굽이 조각은 굵은 것 아래 제 자리에 있다', () {
      for (int i = 0; i < LinkSprites.radii.length; i++) {
        for (int q = 0; q < 4; q++) {
          final thin = LinkSprites.arc(i, q, true), wide = LinkSprites.arc(i, q);
          expect(thin.width, closeTo(LinkSprites.radii[i] + LinkSprites.thinStroke / 2, 1e-9));
          expect(thin.left, wide.left);
          expect(thin.top, greaterThanOrEqualTo(4 * 24.0), reason: '네모 · 고리 줄(넷째 줄) 아래');
          expect(thin.bottom, lessThanOrEqualTo(7 * 24.0));
        }
      }
    });
  });

  // 꼬리표 갈래 E(설계 4-1 '구멍과 꼬리 마름모'): 건국 네모 → 띠 왼쪽 위의 **구멍**, 멸망 네모 → 승계선이 떠나는 띠 오른쪽 위의 **꼬리 마름모**.
  // 검사 기록의 이름은 예전 그대로 '네모'(건국 = 구멍 · 멸망 = 마름모)다.
  group('같은 줄에서 곧바로 이음 — 구멍 · 마름모 · 문 · 다리', () {
    test('구멍은 띠 시작에서 7 · 꼬리 마름모는 띠 끝에서 7 — 이음매에서도 비켜 앉지 않고, 높이는 띠 윗변 + 7(이름 색줄의 가운데)', () async {
      const t = 15 * m;
      final (scene, painter) = make(seamTile(t: t));
      addTearDown(scene.dispose);
      final squares = await notesOf(scene, painter, '네모');
      final x = scene.controller.view.xOf(t);
      // 화면에 온전히 드는 것만: 앞 나라의 마름모 · 뒤 나라의 구멍(두 띠의 바깥 끝은 화면 밖이라 반쯤 잘린 것은 그리지 않는다)
      expect(squares.length, 2);
      final fall1 = squares.firstWhere((s) => s.startsWith('멸망 1'));
      final found2 = squares.firstWhere((s) => s.startsWith('건국 2'));
      // 예전 네모의 이음매 비키기(3 · 직접이 아닌 승계 6)는 없다 — 구멍과 마름모는 꼴이 달라 맞닿아도 헷갈리지 않는다.
      expect(nums(fall1)[1], closeTo(x - TagLook.diamondX, .05));
      expect(nums(fall1)[1], closeTo(x - 7, .05));
      // 두 장 꼬리표(리메이크 2부 · 감독 결정 '두 장 ㄴ'): 구멍은 띠 전체의 키가 아니라 **이름 색줄**(G.head 14)의 귀에 맞춘다 —
      // 키 14의 모따기는 5(최소)라 구멍은 귀 + 2 = 7(paint/bands.dart TagLook.cornerOf · holeAt). 예전(한 장 꼬리표)에는 띠 키 123으로 셈해 14였다.
      expect(TagLook.holeAt(TagEnd.cham, G.head), 7);
      expect(nums(found2)[1], closeTo(x + TagLook.holeAt(TagEnd.cham, G.head), .05), reason: '다스림의 꼬리표(모따기)는 구멍이 시작에서 이름 색줄의 귀 + 2');
      // 둘의 가운데 높이 = 구멍 높이(띠 윗변 19 + 이름 색줄 14의 가운데 7 — TagLook.holeY) — 글줄 수 · 띠 키와 상관없다.
      expect(TagLook.holeY, G.head / 2);
      expect(nums(fall1)[2], closeTo(scene.controller.view.yOf(19 + TagLook.holeY), .05));
      expect(nums(found2)[2], closeTo(scene.controller.view.yOf(19 + TagLook.holeY), .05));
    });

    test('영토 밖(부흥 · 저항)의 꼬리표는 둥근 끝이라 구멍이 시작에서 9', () async {
      const t = 15 * m;
      final bytes = (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, t - 20 * m, t, '앞 나라')
            ..band(2, 0, t, t + 20 * m, '되찾는 깃발', look: BandKind.movement)
            ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9, a: sqSeamR)
            ..item(LinkLayer.secSquare, 102, 0, t, t + 20 * m, ref: 2, name: '되찾는 깃발', color: 0xa295aa, a: sqSeamL)
            ..item(LinkLayer.secLink, 201, 0, t, t, ref: 1, b: 2, color: 0xabb3c9, a: lkQFirst | lkSeam))
          .build();
      final (scene, painter) = make(bytes);
      addTearDown(scene.dispose);
      final squares = await notesOf(scene, painter, '네모');
      final x = scene.controller.view.xOf(t);
      // 구멍은 이름 색줄(G.head 14)의 둥근 끝에 맞춘다 — 반지름은 키의 절반(7)에서 멈추고 구멍은 반지름 × 0.6이 최소 9보다 작아 9
      // (예전 한 장 꼬리표는 띠 키 123으로 셈해 반지름 24 · 구멍 14였다).
      expect(TagLook.holeAt(TagEnd.key, G.head), 9);
      expect(nums(squares.firstWhere((s) => s.startsWith('건국 2')))[1], closeTo(x + TagLook.holeAt(TagEnd.key, G.head), .05));
    });

    test('맞닿은 이음매의 문은 폭 3 · 높이 4.4이고 다리는 마름모 가운데(끝 − 7)에서 구멍의 왼쪽(시작 + 7 − 2.5)까지', () async {
      const t = 15 * m;
      final (scene, painter) = make(seamTile(t: t));
      addTearDown(scene.dispose);
      final doors = await notesOf(scene, painter, '문');
      final segs = await notesOf(scene, painter, '조각');
      final x = scene.controller.view.xOf(t);
      expect(doors.length, 1, reason: '맞닿으면 두 테두리를 한 문으로');
      expect(nums(doors.first)[2], closeTo(3, .05));
      expect(nums(doors.first)[3], closeTo(4.4, .05));
      // 다리는 이음매 한가운데에서 반반: 선대 쪽은 마름모 가운데(마름모가 위에 덮여 흰 틈이 없다)에서 7px,
      // 후대 쪽은 구멍의 왼쪽 테(구멍 가운데 − 반지름 2.5)까지 4.5px.
      expect(segs.length, 2);
      expect(nums(segs.first)[0], closeTo(x - 7, .05));
      expect(nums(segs.first)[2], closeTo(x, .05));
      expect(nums(segs.last)[0], closeTo(x, .05));
      // 구멍은 이름 색줄의 귀에 맞춰 시작 + 7(두 장 꼬리표) — 다리는 구멍 왼쪽 테까지 4.5.
      final hole = TagLook.holeAt(TagEnd.cham, G.head);
      expect(hole, 7);
      expect(nums(segs.last)[2], closeTo(x + hole - TagLook.holeR, .05));
      expect(nums(segs.last)[2] - nums(segs.last)[0], closeTo(hole - TagLook.holeR, .05));
    });

    // 2026-10-13 감독 "부분승계를 좀 단순하게 · 선이 3개니까 너무 난잡해진다" → 가는 한 줄 · 짙기 80%(예전에는 늘 세 가닥 · 문 높이 8).
    test('부분 승계는 가는 한 줄이다 — 문은 다른 승계와 같은 4.4 · 조각은 반반 둘 · 1px을 픽셀 칸 가운데에', () async {
      const t = 15 * m;
      final (scene, painter) = make(seamTile(t: t, kind: 3, degree: 1));
      addTearDown(scene.dispose);
      final doors = await notesOf(scene, painter, '문');
      final segs = await notesOf(scene, painter, '조각');
      expect(nums(doors.first)[3], closeTo(4.4, .05));
      expect(segs.length, 2); // 한 줄 × 반반(선대 쪽 · 후대 쪽)
      expect(segs, everyElement(contains('가는1.0')));
      // 1px 선은 픽셀 칸 가운데(.5)에 — 두 칸에 번지지 않게. 높이는 구멍 · 마름모의 가운데(띠 윗변 19 + 7 — 이름 색줄의 가운데).
      final y = scene.controller.view.yOf(19 + TagLook.holeY);
      final ys = segs.map((s) => nums(s)[1]).toSet().toList();
      expect(ys.length, 1);
      expect(ys.single - ys.single.floorToDouble(), closeTo(.5, .01));
      expect((ys.single - y).abs(), lessThanOrEqualTo(.5));
    });

    test('부분 승계의 정도(약 · 중 · 강)는 그림을 바꾸지 않는다 — 글로만 보인다', () async {
      const t = 15 * m;
      final shots = <List<String>>[];
      for (final degree in [1, 2, 3]) {
        final (scene, painter) = make(seamTile(t: t, kind: 3, degree: degree));
        shots.add([...await notesOf(scene, painter, '문'), ...await notesOf(scene, painter, '조각')]);
        scene.dispose();
      }
      expect(shots[1], shots[0]);
      expect(shots[2], shots[0]);
    });

    test('고르기: 고른 띠에 닿는 선만 1 · 나머지 선과 문은 .14 · 네모는 그 띠의 밝기', () async {
      const t = 15 * m;
      // 세 줄 · 두 승계: 1 → 2(같은 줄의 이음매)와 1 → 3(아래 줄로). 고른 띠는 3번.
      final bytes = (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, t - 20 * m, t, '앞 나라')
            ..band(2, 0, t, t + 20 * m, '뒤 나라')
            ..band(3, 1, t + 4 * m, t + 20 * m, '아랫 나라')
            ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9, a: sqSeamR)
            ..item(LinkLayer.secSquare, 102, 0, t, t + 20 * m, ref: 2, name: '뒤 나라', color: 0xa295aa, a: sqSeamL)
            ..item(LinkLayer.secSquare, 103, 1, t + 4 * m, t + 20 * m, ref: 3, name: '아랫 나라', color: 0x9ab5a0)
            ..item(LinkLayer.secLink, 201, 0, t, t, row2: 0, ref: 1, b: 2, color: 0xabb3c9, a: lkQFirst | lkSeam)
            ..item(LinkLayer.secLink, 202, 0, t, t + 4 * m, row2: 1, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown))
          .build();
      final (scene, painter) = make(bytes);
      addTearDown(scene.dispose);
      // 밝기 상태는 그리개가 장면마다 층에 걸어 준다(`Emphasis.of(scene)`) — 검사도 같은 자리에 넣는다.
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(const em.Look(band: 3, row: 1));
      final lines = await notesOf(scene, painter, '선');
      final doors = await notesOf(scene, painter, '문');
      final squares = await notesOf(scene, painter, '네모');
      // 고른 띠(3)에 닿는 선은 색만 짙게 1(css `.tl.is-picked .tl-link.is-selected { opacity: 1 }` — 평소 .5에서), 나머지는 .5 × .14.
      expect(lines.length, 1, reason: '같은 줄의 이음매는 띠 뒤 선이 없다');
      expect(nums(lines.first).last, closeTo(1, .01));
      // 이음매의 문(폭 3 — 맞닿은 두 테두리를 한 문으로)은 고른 띠에 닿지 않으므로 .14, 고른 띠로 가는 선의 관문(폭 2)은 1.
      final seamDoor = doors.firstWhere((d) => nums(d)[2] == 3, orElse: () => '');
      expect(seamDoor, isNotEmpty, reason: '이음매의 문: $doors');
      expect(nums(seamDoor).last, closeTo(.14, .01));
      expect(doors.where((d) => nums(d).last > .9).length, greaterThan(0), reason: '고른 띠에 닿는 선의 관문: $doors');
      // 네모: 고른 띠와 같은 줄은 1, 다른 줄은 .58.
      double alphaOf(String prefix) => nums(squares.firstWhere((s) => s.startsWith(prefix))).last;
      expect(alphaOf('건국 3'), closeTo(1, .01));
      expect(alphaOf('멸망 1'), closeTo(.58, .01));
    });

    test('조감(밀도 2)에는 네모가 없고 선이 띠 끝 안쪽 3px에 닿는다', () async {
      const t = 15 * m;
      final (scene, painter) = make(seamTile(t: t));
      addTearDown(scene.dispose);
      scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
      final squares = await notesOf(scene, painter, '네모');
      final segs = await notesOf(scene, painter, '조각');
      expect(squares, isEmpty, reason: '조감에는 건국 · 멸망 네모가 없다(명세 04의 7-2)');
      // 맞닿은 이음매의 다리는 띠 끝 안쪽 STUB(3px)에서 이음매 한가운데까지 양쪽 3px.
      expect(segs.length, 2);
      for (final s in segs) {
        final v = nums(s);
        expect((v[2] - v[0]).abs(), closeTo(BirdLook.stub, .05));
      }
    });

    // 머리 이름의 구간(띠 층 · 출처 'names')은 bands_paint_test가 본다 — 여기서는 관계선 층이 적은 것만.
    test('두 장 꼬리표: 구멍 · 마름모는 이름 색줄이라 사건이 비켜 갈 구간을 적지 않는다(글줄 수와 상관없이)', () async {
      // 구멍 · 마름모는 이름 색줄(띠 윗변 + 7)에, 사건은 몸통의 흰 사건 칸에 있어 서로 다른 줄이다(감독 결정 '두 장 ㄴ') —
      // 예전 갈래 E(첫 글줄 · 세기 1 · 점도 비킴)의 구간은 없다(머리 이름의 구간을 없앤 것과 같은 까닭 — links.dart _plan · bands.dart _placeHead).
      const t = 15 * m;
      final one = make(seamTile(t: t), lines: 1), two = make(seamTile(t: t));
      addTearDown(one.$1.dispose);
      addTearDown(two.$1.dispose);
      final squares = await notesOf(two.$1, two.$2, '네모');
      await notesOf(one.$1, one.$2, '네모');
      expect(squares, isNotEmpty, reason: '구멍 · 마름모는 그대로 선다');
      expect(ReservedZones.of(two.$1).at(0, except: 'names'), isEmpty);
      expect(ReservedZones.of(one.$1).at(0, except: 'names'), isEmpty);
    });

    test('줄의 구간 지문은 세기 0만 센다 — 가장자리를 넘나드는 네모에 이름 이력이 버려지지 않게', () async {
      // 건국 · 멸망 네모는 화면 가장자리를 넘나들 때마다 생겼다 사라진다(`showF`/`showE`가 `c.left` · `c.w`로 자른다).
      // 그것까지 지문에 들면 옆으로 끌 때마다 그 줄의 이름 이력이 통째로 버려져 이름이 깜박인다.
      const t = 15 * m;
      final (scene, painter) = make(seamTile(t: t));
      addTearDown(scene.dispose);
      await notesOf(scene, painter, '네모');
      final v = scene.controller.view;
      Int32List sigOf() => LabelBatch.collect(scene, v, 0, 1, 1).input.zoneSig!;
      // 두 장 꼬리표에서는 관계선 층이 세기 1 구간을 적지 않는다 — 가장자리를 넘나드는 세기 1 구간을 검사가 직접 둔다(예전 네모 자리).
      ReservedZones.of(scene).put('네모', {
        0: [ReservedZone(t - 1 * m, t + 1 * m, line: 0, noDot: true, strength: 1)],
      });
      final base = sigOf();
      expect(ReservedZones.of(scene).at(0).any((z) => z.strength == 1), isTrue, reason: '세기 1 구간이 있는 줄이어야 한다');
      // 세기 1 · 2를 더해도 지문은 그대로다.
      ReservedZones.of(scene).put('검사', {
        0: [const ReservedZone(100 * m, 101 * m, line: 0, strength: 1), const ReservedZone(102 * m, 103 * m, line: 0, noDot: true, strength: 2)],
      });
      expect(sigOf(), base, reason: '네모(세기 1 · 2)는 지문에 들지 않는다');
      // 세기 0(소속 · 대범위 단추 · 내림줄)이 새로 생기면 지문이 달라진다.
      ReservedZones.of(scene).put('검사', {
        0: [const ReservedZone(100 * m, 101 * m, line: 0, strength: 0)],
      });
      expect(sigOf()[0], isNot(base[0]), reason: '세기 0이 새로 생긴 줄은 지문이 달라져 이름 이력을 한 번 버린다');
      expect(sigOf()[1], base[1], reason: '건드리지 않은 줄의 지문은 그대로');
    });

    test('맞히기: 마름모 · 구멍을 누르면 그 띠 · 선을 누르면 두 띠', () async {
      const t = 15 * m;
      final (scene, painter) = make(seamTile(t: t));
      addTearDown(scene.dispose);
      await notesOf(scene, painter, '네모');
      final v = scene.controller.view, y = v.yOf(19 + TagLook.holeY);
      final hit = painter.links.hitLinks(v.xOf(t) - 7, y);
      expect(hit?.kind, LinkHitKind.square);
      expect(hit?.band, 1);
      final found = painter.links.hitLinks(v.xOf(t) + TagLook.holeAt(TagEnd.cham, G.head), y);
      expect((found?.kind, found?.band), (LinkHitKind.square, 2));
      expect(painter.links.hitLinks(v.xOf(t) - 7, y + 60), isNull);
    });

    test('승계선 끄기(필터의 세 값): 구멍은 남고 선 · 문 · 꼬리 마름모가 사라진다', () async {
      const t = 15 * m;
      final (scene, painter) = make(seamTile(t: t));
      addTearDown(scene.dispose);
      painter.links.successionMode = 2;
      final squares = await notesOf(scene, painter, '네모');
      final doors = await notesOf(scene, painter, '문');
      expect(squares.where((s) => s.startsWith('건국 2')), isNotEmpty);
      expect(doors, isEmpty);
      // 마름모는 승계선이 떠나는 띠에만 — 선을 숨긴 보기에는 떠나는 띠가 없어 마름모도 없다. 사건이 비켜 갈 구간은 두 장 꼬리표에서 늘 없다.
      expect(ReservedZones.of(scene).at(0, except: 'names'), isEmpty);
      expect(squares.where((s) => s.startsWith('멸망')), isEmpty, reason: '떠나는 띠가 없어 꼬리 마름모가 없다');
    });

    test('네모 · 문 · 다리만 있는 장면을 그림으로 떠 둔다(눈으로 대조할 때)', () async {
      const t = 15 * m;
      final (scene, painter) = make(seamTile(t: t));
      addTearDown(scene.dispose);
      await notesOf(scene, painter, '네모');
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 1920, 1080), Paint()..color = const Color(0xfffbf7ef));
      painter.paint(canvas, const Size(1920, 1080));
      final picture = recorder.endRecording();
      final image = await picture.toImage(1920, 1080);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      image.dispose();
      final folder = Directory('../results/render-links2')..createSync(recursive: true);
      File('${folder.path}/검사-이음매.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });

  group('올리기 · 고르기 — 닿는 승계선만 색을 짙게(굵기는 그대로)', () {
    // 지금 연표: 띠에 올리면(`_hover` → 그 uid에 닿는 `.tl-link`에 is-hot) · 띠를 고르면(is-selected) · 선 위에 올리면(:hover)
    // 그 선의 짙기가 1이 된다(css `.tl-link.is-hot, .tl-link.is-selected, .tl-link:hover { opacity: 1 }`).
    // 띠 위 조각도 같다. 2026-10-16(관계선 색 '가')부터 짙기는 늘 1이고, 짙게는 색이 띠 테 빛깔 → 꼬리 마름모 빛깔로 바뀌는 것이다.

    /// 두 줄: 0번 줄 '앞 나라'(1)에서 1번 줄 '아랫 나라'(3)로 내려가는 승계 한 건. [a]는 구역 21의 a 비트(종류 · 정도 · 부정됨).
    Uint8List downTile({int a = 3 | (2 << 2)}) {
      const t = 15 * m;
      return (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, t - 20 * m, t, '앞 나라')
            ..band(3, 1, t + 4 * m, t + 20 * m, '아랫 나라')
            ..band(4, 1, t - 20 * m, t + 2 * m, '옆 나라')
            ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9)
            ..item(LinkLayer.secSquare, 103, 1, t + 4 * m, t + 20 * m, ref: 3, name: '아랫 나라', color: 0x9ab5a0)
            ..item(LinkLayer.secSquare, 104, 1, t - 20 * m, t + 2 * m, ref: 4, name: '옆 나라', color: 0xa295aa)
            ..item(LinkLayer.secLink, 202, 0, t, t + 4 * m, row2: 1, ref: 1, b: 3, color: 0xabb3c9, a: a | lkQFirst | lkDown))
          .build();
    }

    double lineAlpha(List<String> lines) => nums(lines.single).last;

    // 관계선 색 '가'(감독 2026-10-16): 짙기는 늘 1이고 '짙게'는 색이 바뀐다 — 띠 테 빛깔(LinkLook.inkOf) → 꼬리 마름모 빛깔(LinkLook.hotInkOf).
    String hex(int argb) => (argb & 0xffffff).toRadixString(16).padLeft(6, '0');
    final base = hex(LinkLook.inkOf(0xabb3c9)), hot = hex(LinkLook.hotInkOf(0xabb3c9));

    test('부분 승계: 평소 띠 테 빛깔 — 선에 닿는 띠에 올리면 꼬리 마름모 빛깔, 닿지 않는 띠에 올리면 그대로(짙기는 늘 1)', () async {
      final (scene, painter) = make(downTile());
      addTearDown(scene.dispose);
      expect(lineAlpha(await notesOf(scene, painter, '선')), closeTo(1, .001));
      expect(await notesOf(scene, painter, '선색'), [base]);
      scene.hover(3);
      expect(await notesOf(scene, painter, '선색'), [hot], reason: '후대 띠에 올림');
      scene.hover(1);
      expect(await notesOf(scene, painter, '선색'), [hot], reason: '선대 띠에 올림');
      scene.hover(4);
      expect(await notesOf(scene, painter, '선색'), [base], reason: '닿지 않는 띠');
      scene.hover(0);
      expect(await notesOf(scene, painter, '선색'), [base], reason: '띠 밖으로 나감');
      expect(lineAlpha(await notesOf(scene, painter, '선')), closeTo(1, .001));
    });

    test('부분 승계의 띠 뒤 선은 가는 한 줄(1px)이고 세로 통로는 직접 승계와 같은 자리다', () async {
      final (partial, pp) = make(downTile());
      final (direct, dp) = make(downTile(a: 0));
      addTearDown(partial.dispose);
      addTearDown(direct.dispose);
      final thin = (await notesOf(partial, pp, '선')).single, wide = (await notesOf(direct, dp, '선')).single;
      expect(thin, contains('가는1.0'));
      expect(wide, isNot(contains('가는')));
      // 지나는 길이 직접 승계와 같다 — 예전의 세 가닥처럼 통로를 1.5px 더 비키지 않는다(가는 선은 그릴 때만 픽셀 칸 가운데로).
      expect(nums(thin.split(' 짙기').first), nums(wide.split(' 짙기').first));
    });

    test('직접 승계는 짙기 1에 올리면 색이 짙어지고, 부정된 나라에 닿는 선의 옅음 .2는 올리면 1', () async {
      for (final (a, alpha) in [(0, 1.0), (3 | (2 << 2) | (1 << 13), .2), (1 << 13, .2)]) {
        final (scene, painter) = make(downTile(a: a));
        expect(lineAlpha(await notesOf(scene, painter, '선')), closeTo(alpha, .01), reason: 'a=$a 평소');
        expect(await notesOf(scene, painter, '선색'), [base], reason: 'a=$a 평소 색');
        scene.hover(3);
        expect(lineAlpha(await notesOf(scene, painter, '선')), closeTo(1, .01), reason: 'a=$a 올림');
        expect(await notesOf(scene, painter, '선색'), [hot], reason: 'a=$a 올림 색');
        scene.dispose();
      }
    });

    test('띠 층과 같은 올림 값(SceneMarks.hotBand — 칸 위에 올린 것)도 선을 짙게 한다', () async {
      final (scene, painter) = make(downTile());
      addTearDown(scene.dispose);
      SceneMarks.of(scene)
        ..hotBand = 3
        ..version += 1;
      expect(await notesOf(scene, painter, '선색'), [hot]);
    });

    test('선 위에 올리면 그 선만 짙게(`.tl-link:hover`)', () async {
      final (scene, painter) = make(downTile());
      addTearDown(scene.dispose);
      SceneMarks.of(scene)
        ..hotLink = (1, 3)
        ..version += 1;
      expect(await notesOf(scene, painter, '선색'), [hot]);
      SceneMarks.of(scene)
        ..hotLink = (1, 4)
        ..version += 1;
      expect(await notesOf(scene, painter, '선색'), [base], reason: '다른 선');
    });

    test('같은 줄 이음매의 띠 위 조각(부분 승계): 짙기 1 · 제 나라의 띠 테 빛깔 — 올리면 꼬리 마름모 빛깔', () async {
      const t = 15 * m;
      final (scene, painter) = make(seamTile(t: t, kind: 3, degree: 2));
      addTearDown(scene.dispose);
      List<double> alphas(List<String> segs) => [for (final s in segs) nums(s).last];
      final before = await notesOf(scene, painter, '조각');
      expect(before.length, 2);
      expect(alphas(before), everyElement(closeTo(1, .001)));
      expect((await notesOf(scene, painter, '조각색')).toSet(), {base, hex(LinkLook.inkOf(0xa295aa))}, reason: '왼쪽은 선대 · 오른쪽은 후대의 테 빛깔');
      scene.hover(2);
      expect((await notesOf(scene, painter, '조각색')).toSet(), {hot, hex(LinkLook.hotInkOf(0xa295aa))});
    });

    test('직접 승계의 띠 위 가닥: 짙기 1 — 올리면 색이 짙어진다', () async {
      const t = 15 * m;
      final (scene, painter) = make(seamTile(t: t));
      addTearDown(scene.dispose);
      expect([for (final s in await notesOf(scene, painter, '조각')) nums(s).last], everyElement(closeTo(1, .01)));
      expect(await notesOf(scene, painter, '조각색'), contains(base));
      scene.hover(1);
      expect(await notesOf(scene, painter, '조각색'), contains(hot));
      expect(await notesOf(scene, painter, '조각색'), isNot(contains(base)));
    });

    test('고른 것이 있으면 올림은 선을 짙게 하지 않는다(`.tl.is-picked .tl-link:not(.is-selected)`가 이긴다)', () async {
      final (scene, painter) = make(downTile());
      addTearDown(scene.dispose);
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(const em.Look(band: 4, row: 1));
      scene.hover(3);
      expect(lineAlpha(await notesOf(scene, painter, '선')), closeTo(.14, .01), reason: '고른 것 밖은 .14(흐림은 투명도 그대로)');
      expect(await notesOf(scene, painter, '선색'), [base]);
    });

    test('고른 띠에 닿는 부분 승계도 짙게', () async {
      final (scene, painter) = make(downTile());
      addTearDown(scene.dispose);
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(const em.Look(band: 3, row: 1));
      expect(lineAlpha(await notesOf(scene, painter, '선')), closeTo(1, .01));
      expect(await notesOf(scene, painter, '선색'), [hot]);
    });
  });

  group('합류(흡수) — 이미 있던 나라로 곧게 내려가 테두리에 닿는다', () {
    // 두 줄: 0번 줄 '앞 나라'(t − 20 ~ t)가 끝나며 1번 줄에 이미 있던 '뒤 나라'(t − 10 ~ t + 20)로 부분 승계.
    // 0번 줄에는 기관 칸 단이 있고(organ_top), 그 칸은 [organTo]까지만 있다.
    Uint8List absorbTile({required double t, required double organTo}) => (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, t - 20 * m, t, '앞 나라')
          ..band(2, 1, t - 10 * m, t + 20 * m, '뒤 나라')
          ..cell(301, 0, t - 20 * m, organTo, '기관', kind: 3)
          ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9)
          ..item(LinkLayer.secSquare, 102, 1, t - 10 * m, t + 20 * m, ref: 2, name: '뒤 나라', color: 0xa295aa)
          ..item(LinkLayer.secLink, 201, 0, t - 10 * m, t, row2: 1, ref: 1, b: 2, color: 0xabb3c9, a: 3 | (3 << 2) | lkDown | (1 << 7)))
        .build();

    (TimelineScene, TimelinePainter) makeOrgan(Uint8List bytes) {
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 1080)
        ..setExtent(-2000 * m, 2000 * m)
        ..setContentHeight(284);
      final organRow = Map<String, dynamic>.from(row(0))..['organ_top'] = 124;
      final scene = TimelineScene(
        controller: controller,
        layout: SceneLayout.fromJson({
          'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
          'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [organRow, row(1)]}],
        }),
        fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      controller.showRange(10 * m, 20 * m);
      return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
    }

    test('선대 띠의 기관 칸이 일찍 끝났으면 멸망 네모 밑에서 곧게 내려가 뒤 나라의 윗변에 합류한다', () async {
      const t = 15 * m;
      final (scene, painter) = makeOrgan(absorbTile(t: t, organTo: t - 12 * m));
      addTearDown(scene.dispose);
      final joins = await notesOf(scene, painter, '합류');
      final lines = await notesOf(scene, painter, '선');
      final squares = await notesOf(scene, painter, '네모');
      final ec = nums(squares.firstWhere((s) => s.startsWith('멸망 1')))[1];
      expect(joins.length, 1, reason: '그 줄에 기관 칸 단이 있어도 그 자리(멸망 네모 ± 10px)가 비었으면 내림줄로 합류');
      expect(nums(joins.first)[0] + nums(joins.first)[2] / 2, closeTo(ec, .05));
      // 되돌아가는 길(뒤 나라의 시작점으로)이 아니라 곧은 세로 한 획
      final pts = nums(lines.single.split(' 짙기').first);
      expect(pts.length, 4);
      expect(pts[0], closeTo(pts[2], .05));
    });

    test('기관 칸이 멸망 마름모 자리까지 있으면 예전처럼 내림줄을 긋지 않는다', () async {
      const t = 15 * m;
      final (scene, painter) = makeOrgan(absorbTile(t: t, organTo: t));
      addTearDown(scene.dispose);
      final lines = await notesOf(scene, painter, '선');
      final joins = await notesOf(scene, painter, '합류');
      final squares = await notesOf(scene, painter, '네모');
      final ec = nums(squares.firstWhere((s) => s.startsWith('멸망 1')))[1];
      final pts = nums(lines.single.split(' 짙기').first);
      // 꼬리표 갈래 E: 선은 늘 마름모 가운데에서 나온다(예전에는 네모 + 4.5) — 그래서 첫 점이 아니라 길의 꼴로 가른다.
      // 내림줄이면 마름모 밑에서 곧은 세로 한 획(두 점)이고, 아니면 마름모에서 가로로 띠 밖 세로 통로까지 나갔다가 내려간다(세 점).
      expect(pts.length, 6, reason: '가로 → 세로의 세 점: $pts');
      expect(pts[0], closeTo(ec, .05), reason: '마름모 가운데에서 나온다');
      expect(pts[1], closeTo(pts[3], .05), reason: '첫 획은 가로 — 칸을 가로지르는 내림줄은 겹침');
      expect(pts[2], greaterThan(ec + 7), reason: '세로 통로는 선대 띠의 끝 밖');
      expect(nums(joins.single)[0] + nums(joins.single)[2] / 2, closeTo(pts[2], .05), reason: '합류 조각은 세로 통로 끝에');
    });
  });

  group('이음매 눈금(명세 04 3-4 · 스위치 route) — 좁은 띠라 다리를 못 세우는 이음매에 문 하나와 띠 위 토막(조사 결함 9)', () {
    // 같은 줄에서 t에 맞닿는 폭 [w](분)의 두 띠와 그 직접 승계(이음매). 보기는 10 ~ 20백만 분이 1920px(1백만 분 = 192px).
    const t = 15 * m;
    Uint8List narrow(double w, {int kind = 0}) => (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, t - w, t, '앞 나라')
          ..band(2, 0, t, t + w, '뒤 나라')
          ..item(LinkLayer.secSquare, 101, 0, t - w, t, ref: 1, name: '앞 나라', color: 0xabb3c9, a: sqSeamR)
          ..item(LinkLayer.secSquare, 102, 0, t, t + w, ref: 2, name: '뒤 나라', color: 0xa295aa, a: sqSeamL)
          ..item(LinkLayer.secLink, 201, 0, t, t, ref: 1, b: 2, color: 0xabb3c9, a: kind | lkQFirst | lkSeam))
        .build();

    tearDown(PaintPick.reset);

    test('두 띠가 10px(구멍 · 마름모 꺼짐): 맞닿은 이음매에 폭 3 문 하나 · 띠 위 토막 끝 − 3 ~ 시작 + 3 — 가운데 왼쪽은 앞 나라, 오른쪽은 뒤 나라의 테 빛깔', () async {
      final (scene, painter) = make(narrow(.052 * m));
      addTearDown(scene.dispose);
      final tick = (await notesOf(scene, painter, '이음매눈금')).single;
      expect(tick, startsWith('1→2 '));
      final x = scene.controller.view.xOf(t);
      final n = nums(tick); // [끝 − 3, y, 시작 + 3]
      expect(n[0], closeTo(x - 3, .06));
      expect(n[2], closeTo(x + 3, .06));
      final y = n[1];
      expect(await notesOf(scene, painter, '네모'), isEmpty, reason: '10px 띠는 구멍 · 마름모가 꺼진다(16px 미만)');
      final doors = [for (final d in await notesOf(scene, painter, '문')) nums(d)];
      expect(doors.length, 1);
      expect(doors.single.take(4), [closeTo(x - 1.5, .06), closeTo(y - 2.2, .06), closeTo(3, .06), closeTo(4.4, .06)], reason: '맞닿은 두 테를 한 문으로(다리와 같은 문)');
      final segs = [for (final s in await notesOf(scene, painter, '조각')) nums(s)];
      expect(segs.length, 2);
      expect(segs[0].take(4), [closeTo(x - 3, .06), closeTo(y, .06), closeTo(x, .06), closeTo(y, .06)]);
      expect(segs[1].take(4), [closeTo(x, .06), closeTo(y, .06), closeTo(x + 3, .06), closeTo(y, .06)]);
      final colors = await notesOf(scene, painter, '조각색');
      expect(colors[0], isNot(colors[1]), reason: '앞 나라 · 뒤 나라의 테 빛깔');
      expect(await notesOf(scene, painter, '선'), isEmpty, reason: '띠 뒤 선은 두 띠 몸통에 다 가려 긋지 않는다');
      // 눈금 자리는 좁은 두 띠의 네모 맞히기 구간(가운데 ± 5) 안이라 네모(그 띠)가 먼저 잡힌다 — 맞히기 차례(단추 → 네모 → 선)는 그대로.
      expect(painter.links.hitLinks(x + 2, y)?.kind, LinkHitKind.square);
      expect(LineAudit.last!.invisible, 0, reason: '띠 위 토막이 있어 보이는 선');
    });

    test('스위치 route를 끄면 그 전 그림(두 몸통 뒤에 숨는 띠 뒤 선뿐 — 안 보이는 선) · 6px보다 좁은 띠에는 두지 않는다', () async {
      PaintPick.route = false;
      final (scene, painter) = make(narrow(.052 * m));
      addTearDown(scene.dispose);
      expect(await notesOf(scene, painter, '이음매눈금'), isEmpty);
      expect(await notesOf(scene, painter, '문'), isEmpty);
      expect((await notesOf(scene, painter, '선')).length, 1);
      expect(LineAudit.last!.invisible, 1);
      PaintPick.route = true;
      final (thin, thinPainter) = make(narrow(.02 * m)); // 약 3.8px
      addTearDown(thin.dispose);
      expect(await notesOf(thin, thinPainter, '이음매눈금'), isEmpty, reason: '토막 둘(6px)이 들 자리가 없다');
    });

    test('점선 종류(간접)도 한 획 · 부분 승계는 가는 선 굵기 그대로', () async {
      final (scene, painter) = make(narrow(.052 * m, kind: 1));
      addTearDown(scene.dispose);
      expect((await notesOf(scene, painter, '조각')).length, 2, reason: '박자로 쪼개지 않는다');
      final (partial, partialPainter) = make(narrow(.052 * m, kind: 3));
      addTearDown(partial.dispose);
      final segs = await notesOf(partial, partialPainter, '조각');
      expect(segs.length, 2);
      expect(segs.every((s) => s.contains(' 가는1.0')), isTrue, reason: '$segs');
    });
  });

  group('(가-0) 앞 나라 끝 지키기 — 승계선은 이웃 띠 밑에서 나오지 않는다(명세 04 3-6 · 스위치 route)', () {
    // 등불 왕국(0번 줄 · t에서 끝남) → 검은물 의병(1번 줄) · 남강 임시정부(2번 줄) 부흥 두 가닥. 0번 줄에서 등불 왕국 뒤에 하연 총관부가
    // [gap](px 셈은 장면에서)만큼 떨어져(0이면 맞붙어) 선다 — 지금 길의 세로 통로(끝 + 9 + k×5)가 총관부 밑이 되어 선이 총관부에서 나오는 것처럼 보였다(감독 2026-10-25).
    const t = 15 * m;
    Uint8List lanternTile({double? neighborAt}) {
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(1, 0, t - 20 * m, t, '등불 왕국')
        ..band(9, 1, t + 2 * m, t + 6 * m, '검은물 의병')
        ..band(10, 2, t + 2.5 * m, t + 6 * m, '남강 임시정부')
        ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '등불 왕국', color: 0xb8a77a)
        ..item(LinkLayer.secSquare, 109, 1, t + 2 * m, t + 6 * m, ref: 9, name: '검은물 의병', color: 0x9ab5a0)
        ..item(LinkLayer.secSquare, 110, 2, t + 2.5 * m, t + 6 * m, ref: 10, name: '남강 임시정부', color: 0xa295aa)
        ..item(LinkLayer.secLink, 201, 0, t, t + 2 * m, row2: 1, ref: 1, b: 9, color: 0xb8a77a, a: 2 | lkQFirst | lkDown)
        ..item(LinkLayer.secLink, 202, 0, t, t + 2.5 * m, row2: 2, ref: 1, b: 10, color: 0xb8a77a, a: 2 | lkQFirst | lkDown, c: 10);
      if (neighborAt != null) {
        b
          ..band(7, 0, neighborAt, t + 1 * m, '하연 총관부')
          ..item(LinkLayer.secSquare, 107, 0, neighborAt, t + 1 * m, ref: 7, name: '하연 총관부', color: 0xb59aa6);
      }
      return b.build();
    }

    (TimelineScene, TimelinePainter) make3(Uint8List bytes) {
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 1080)
        ..setExtent(-2000 * m, 2000 * m)
        ..setContentHeight(426);
      final scene = TimelineScene(
        controller: controller,
        layout: SceneLayout.fromJson({
          'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
          'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1), row(2)]}],
        }),
        fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      controller.showRange(10 * m, 20 * m);
      return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
    }

    /// 선 둘의 꺾은점([x0, y0, x1, y1, …]) · 등불 왕국의 꼬리 마름모 x(ec) · 띠 끝 x(ec + 7) · 1분(백만 분)의 px.
    Future<(List<List<double>>, double, double, double)> plan(TimelineScene scene, TimelinePainter painter) async {
      final lines = [for (final s in await notesOf(scene, painter, '선')) nums(s.split(' 짙기').first)];
      final squares = await notesOf(scene, painter, '네모');
      final ec = nums(squares.firstWhere((s) => s.startsWith('멸망 1 ')))[1];
      final f9 = nums(squares.firstWhere((s) => s.startsWith('건국 9 ')))[1], f10 = nums(squares.firstWhere((s) => s.startsWith('건국 10 ')))[1];
      return (lines, ec, ec + TagLook.diamondX, (f10 - f9) / (.5 * m));
    }

    tearDown(PaintPick.reset);

    test('맞붙은 이웃 띠(틈 0): 두 가닥이 한 줄기로 꼬리 마름모 밑에서 곧게 내려간다 — 이웃 띠 x 구간에서 나오지 않고 숨은 px 0', () async {
      final (scene, painter) = make3(lanternTile(neighborAt: t));
      addTearDown(scene.dispose);
      final (lines, ec, qe, ppm) = await plan(scene, painter);
      expect(lines.length, 2);
      for (final pts in lines) {
        // drop 꼴 [[ec, 마름모 밑], [ec, 후대 높이], [후대 구멍, 후대 높이]] — 처음 보이는 자리는 등불 왕국의 꼬리 마름모.
        expect(pts.length, 6, reason: '마름모 밑 → 후대 높이 → 구멍의 세 점: $pts');
        expect(pts[0], closeTo(ec, .05));
        expect(pts[2], closeTo(ec, .05));
        expect(pts[1], greaterThan(nums((await notesOf(scene, painter, '네모')).firstWhere((s) => s.startsWith('멸망 1 ')))[2]), reason: '마름모 밑에서');
        expect(pts[0] < qe, isTrue, reason: '총관부(${qe.toStringAsFixed(1)} ~ ${(qe + ppm * m).toStringAsFixed(1)}) 밑이 아니라 등불 왕국 안');
      }
      expect(lines[0][0], lines[1][0], reason: '같은 선대 · 같은 종류 — 한 줄기');
      // 띠 위 층의 세로 관문은 한 번만(같은 줄기의 둘째 선은 겹쳐 긋지 않는다).
      final gates = [for (final s in await notesOf(scene, painter, '조각')) nums(s)].where((g) => (g[0] - ec).abs() < .05 && (g[2] - ec).abs() < .05 && g[3] > g[1]).toList();
      expect(gates, isNotEmpty, reason: '마름모 밑 ~ 몸통 아랫변의 띠 위 획(점선이면 칠 토막 여럿)');
      expect(gates.map((g) => g[1]).toSet().length, gates.length, reason: '같은 줄기의 둘째 선은 겹쳐 긋지 않는다');
      expect(gates.map((g) => g[1]).reduce(math.min), closeTo(lines.first[1], .05), reason: '마름모 밑(선의 첫 점)에서 시작');
      expect(LineAudit.last!.hiddenPx, 0, reason: '두 끝이 아닌 띠 몸통 뒤로 숨은 px');
      // 스위치 route를 끄면 그 전 길 — 통로가 끝 + 9(총관부 밑)이고 숨은 px이 있다.
      PaintPick.route = false;
      final (offScene, offPainter) = make3(lanternTile(neighborAt: t));
      addTearDown(offScene.dispose);
      final (old, _, _, _) = await plan(offScene, offPainter);
      expect(old.first[2], closeTo(qe + 9, .05), reason: '그 전 길의 세로 통로');
      expect(LineAudit.last!.hiddenPx, greaterThan(0));
    });

    test('틈이 8px 이상이면 틈 안의 통로(끝 + 3)로 — 띠 밖 가로로 나와 이웃 띠 앞 3px 안에서 내려간다', () async {
      const gapPx = 10.0;
      final (probe, pp) = make3(lanternTile());
      final (_, _, _, ppm) = await plan(probe, pp);
      probe.dispose();
      final (scene, painter) = make3(lanternTile(neighborAt: t + gapPx / ppm));
      addTearDown(scene.dispose);
      final (lines, ec, qe, _) = await plan(scene, painter);
      expect(lines.length, 2);
      for (final pts in lines) {
        expect(pts.length, 8, reason: 'hv 꼴 네 점: $pts');
        expect(pts[0], closeTo(ec, .05), reason: '마름모 가운데에서');
        expect(pts[2], closeTo(qe + 3, .05), reason: '틈 안 — 앞 나라 끝 + 3');
        expect(pts[2], lessThanOrEqualTo(qe + gapPx - 3 + .05), reason: '이웃 띠 앞 3px 안');
      }
      expect(lines[0][2], lines[1][2], reason: '한 줄기');
      expect(LineAudit.last!.hiddenPx, 0);
    });

    test('맞붙은 이웃 띠가 없으면 길은 지금 그대로(스위치를 켜도 꺼도 같다)', () async {
      final (scene, painter) = make3(lanternTile());
      addTearDown(scene.dispose);
      final (lines, _, qe, _) = await plan(scene, painter);
      expect(lines.first[2], closeTo(qe + 9, .05), reason: '세로 통로는 끝 + 9 + k×5');
      expect(lines.last[2], closeTo(qe + 14, .05), reason: '둘째 선은 + 5');
      final on = await notesOf(scene, painter, '선');
      PaintPick.route = false;
      final (offScene, offPainter) = make3(lanternTile());
      addTearDown(offScene.dispose);
      expect(await notesOf(offScene, offPainter, '선'), on);
    });
  });

  group('걸음 6 — 같은 줄 ⊓ · 오름줄 · 꼬리 내림(명세 04 3-4 · 3-6 · 3-7 · 스위치 route · 조사 결함 2 · 3 · 10 · 12 · 44)', () {
    const t = 15 * m;
    tearDown(PaintPick.reset);

    /// 기록 '선'의 꺾은점([x0, y0, x1, y1, …]) 하나.
    Future<List<double>> line(TimelineScene scene, TimelinePainter painter) async => nums((await notesOf(scene, painter, '선')).single.split(' 짙기').first);

    /// 네모 기록에서 띠 [band]의 건국(구멍) · 멸망(마름모) x · y.
    Future<(double, double)> square(TimelineScene scene, TimelinePainter painter, String kind, int band) async {
      final n = nums((await notesOf(scene, painter, '네모')).firstWhere((s) => s.startsWith('$kind $band ')));
      return (n[1], n[2]);
    }

    /// 줄 [row]의 띠 윗변(배치 px).
    double topOf(TimelineScene scene, int row) => scene.controller.view.yOf(scene.layout.rowTop(row) + scene.layout.geo(row).bandTop);

    // 같은 줄(0): 앞 나라(1 · t에서 끝남) → 뒤 나라(2 · t + 2에서 시작) 부흥(이음매 아님). 사이에 다른 나라(5 · t + .5 ~ t + 1.5)가 끼어 있다 — 등불 왕국 → 하연 부흥국과 같은 꼴.
    Uint8List capTile() => (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, t - 20 * m, t, '앞 나라')
          ..band(5, 0, t + .5 * m, t + 1.5 * m, '사이 나라')
          ..band(2, 0, t + 2 * m, t + 20 * m, '뒤 나라')
          ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9)
          ..item(LinkLayer.secSquare, 105, 0, t + .5 * m, t + 1.5 * m, ref: 5, name: '사이 나라', color: 0xc8b193)
          ..item(LinkLayer.secSquare, 102, 0, t + 2 * m, t + 20 * m, ref: 2, name: '뒤 나라', color: 0xa295aa)
          ..item(LinkLayer.secLink, 201, 0, t, t + 2 * m, ref: 1, b: 2, color: 0xabb3c9, a: 2 | lkQFirst))
        .build();

    test('같은 줄 ⊓: 사이 띠가 있으면 꼬리 마름모 위로 나가 줄 위 틈을 건너 구멍으로 위에서 든다 — 두 끝은 세로 관문 · 부흥 고리는 위 틈 · 숨은 px 0', () async {
      final (scene, painter) = make(capTile());
      addTearDown(scene.dispose);
      final pts = await line(scene, painter);
      final (ec, y) = await square(scene, painter, '멸망', 1);
      final (fc, _) = await square(scene, painter, '건국', 2);
      final top = topOf(scene, 0);
      expect(pts.length, 8, reason: '마름모 위 → 틈 → 구멍 위 → 구멍의 네 점: $pts');
      expect(pts[0], closeTo(ec, .05));
      expect(pts[1], closeTo(y - LinkLook.tipGap, .05), reason: '마름모 위 변 밖');
      final gy = pts[3];
      expect(gy, lessThan(top - scene.layout.tabOf(0)), reason: '책갈피 탭 자리 위의 틈');
      expect([pts[2], pts[4], pts[5], pts[6], pts[7]], [closeTo(ec, .05), closeTo(fc, .05), closeTo(gy, .05), closeTo(fc, .05), closeTo(y - LinkLook.tipGap, .05)]);
      expect((await notesOf(scene, painter, '같은줄위')).single, startsWith('1→2 '));
      // 두 끝의 세로 관문: 문은 윗변 테 [top − .5, top + 1.5](폭 4.4) · 띠 위 획은 마름모 · 구멍 위 변에서 테 밖 .5까지.
      final doors = [for (final d in await notesOf(scene, painter, '문')) nums(d)];
      for (final x in [ec, fc]) {
        expect(doors.any((d) => (d[0] - (x - 2.2)).abs() < .06 && (d[1] - (top - .5)).abs() < .06 && (d[2] - 4.4).abs() < .06 && (d[3] - 2).abs() < .06), isTrue, reason: '$x의 문: $doors');
      }
      final rings = [for (final r in await notesOf(scene, painter, '고리')) nums(r)];
      expect(rings.single[1], closeTo(gy, .05), reason: '부흥 고리는 위 틈의 가로 획 위');
      expect(rings.single[0], lessThan(fc - 6) , reason: '후대 쪽 굽이 앞');
      expect(await notesOf(scene, painter, '굴문'), isEmpty);
      expect(LineAudit.last!.hiddenPx, 0);
      // 끄면 그 전 길 — 곧은 가로 한 획이 사이 나라 뒤로.
      PaintPick.route = false;
      final (off, offPainter) = make(capTile());
      addTearDown(off.dispose);
      expect((await line(off, offPainter)).length, 4);
      expect(LineAudit.last!.hiddenPx, greaterThan(0));
    });

    test('같은 줄인데 사이 띠가 없으면 곧은 선 그대로 · 위 틈이 3px 미만이어도 곧은 선(띠 뒤는 굴 문)', () async {
      final bytes = (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, t - 20 * m, t, '앞 나라')
            ..band(2, 0, t + 2 * m, t + 20 * m, '뒤 나라')
            ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9)
            ..item(LinkLayer.secSquare, 102, 0, t + 2 * m, t + 20 * m, ref: 2, name: '뒤 나라', color: 0xa295aa)
            ..item(LinkLayer.secLink, 201, 0, t, t + 2 * m, ref: 1, b: 2, color: 0xabb3c9, a: 2 | lkQFirst))
          .build();
      final (scene, painter) = make(bytes);
      addTearDown(scene.dispose);
      expect((await line(scene, painter)).length, 4);
      expect(await notesOf(scene, painter, '같은줄위'), isEmpty);
    });

    // 두 줄: 앞 나라(1 · 0번 줄 · t에서 끝남) → 뒤 나라(3 · 1번 줄 · [pStart]에서 시작) 직접 승계. 1번 줄에는 옆 나라(4 · [sideTo]까지)가 있어
    // 꼬리 마름모 밑 내림줄(② — 1번 줄의 그 자리가 막힘)을 막는다. 두 줄 다 지도자 · 내각 단이 있다(row()의 lead_top · cab_top).
    Uint8List stepTile({required double pStart, required double sideTo}) => (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, t - 20 * m, t, '앞 나라')
          ..band(4, 1, t - 20 * m, sideTo, '옆 나라')
          ..band(3, 1, pStart, t + 20 * m, '뒤 나라')
          ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9)
          ..item(LinkLayer.secSquare, 104, 1, t - 20 * m, sideTo, ref: 4, name: '옆 나라', color: 0xc8b193)
          ..item(LinkLayer.secSquare, 103, 1, pStart, t + 20 * m, ref: 3, name: '뒤 나라', color: 0xa295aa)
          ..item(LinkLayer.secLink, 201, 0, t, pStart, row2: 1, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown))
        .build();

    test('오름줄 ┐: 위로 드는 획은 이름 색줄 7px뿐 — 칸 층 · 머리 이름이 있어도 서고, S자 되돌아감이 없다(끄면 6점 S길)', () async {
      // 뒤 나라가 앞 나라 끝 + 약 9.6px에서 시작 — 띠 밖 통로(끝 + 9)로는 넉넉지 않고(x2 < xm + 6) 당김(끝 + 3.6)도 모자라며, 내림줄은 옆 나라가 막는다.
      final bytes = stepTile(pStart: t + .05 * m, sideTo: t - .02 * m);
      final (scene, painter) = make(bytes);
      addTearDown(scene.dispose);
      final pts = await line(scene, painter);
      final (fc, y2) = await square(scene, painter, '건국', 3);
      expect(pts.length, 6, reason: '마름모 → 구멍 위 → 구멍의 세 점: $pts');
      expect(pts[2], closeTo(fc, .05));
      expect(pts[4], closeTo(fc, .05));
      expect(pts[5], closeTo(y2 - LinkLook.tipGap, .05), reason: '구멍 위 변 밖에서 멎는다');
      expect(LineAudit.last!.backPaths, 0);
      // 세로 기둥 표(실 비킴이 읽는다): 구멍 x의 세로 획.
      final cols = LinkColumns.of(scene);
      expect(cols.where((k) => (k.x - fc).abs() < .06 && (k.top - pts[1]).abs() < .06 && (k.bottom - pts[5]).abs() < .06), hasLength(1), reason: '$cols');
      PaintPick.route = false;
      final (off, offPainter) = make(bytes);
      addTearDown(off.dispose);
      expect((await line(off, offPainter)).length, 12, reason: '그 전 길은 S자 되돌아감(6점)');
      expect(LineAudit.last!.backPaths, 1);
    });

    test('꼬리 내림으로: 뒤 나라가 앞 나라 끝보다 먼저 시작해 오름줄도 못 서면 마름모 밑에서 곧게 내려가 뒤 나라 줄 위 틈에서 구멍으로 위에서 든다', () async {
      // 뒤 나라가 앞 나라 끝 − 약 9.6px에서 시작(같은 해 넘김을 다른 줄로 — 조사 결함 12 · 44의 삼국 → 서진 꼴).
      final bytes = stepTile(pStart: t - .05 * m, sideTo: t - .2 * m);
      final (scene, painter) = make(bytes);
      addTearDown(scene.dispose);
      final pts = await line(scene, painter);
      final (ec, y1) = await square(scene, painter, '멸망', 1);
      final (fc, y2) = await square(scene, painter, '건국', 3);
      final top = topOf(scene, 1);
      expect(pts.length, 8, reason: '마름모 밑 → 틈 → 구멍 위 → 구멍의 네 점: $pts');
      expect([pts[0], pts[1]], [closeTo(ec, .05), closeTo(y1 + LinkLook.tipGap, .05)]);
      expect(pts[3], lessThan(top - scene.layout.tabOf(1)), reason: '뒤 나라 줄 위 틈');
      expect([pts[4], pts[6], pts[7]], [closeTo(fc, .05), closeTo(fc, .05), closeTo(y2 - LinkLook.tipGap, .05)]);
      expect(LineAudit.last!.backPaths, 0);
      // 앞 나라 꼬리 마름모 밑의 띠 위 획(꼬리 내림 관문)과 뒤 나라 윗변의 문.
      final doors = [for (final d in await notesOf(scene, painter, '문')) nums(d)];
      expect(doors.any((d) => (d[0] - (fc - 2.2)).abs() < .06 && (d[1] - (top - .5)).abs() < .06), isTrue, reason: '$doors');
      PaintPick.route = false;
      final (off, offPainter) = make(bytes);
      addTearDown(off.dispose);
      expect((await line(off, offPainter)).length, 12, reason: '그 전 길은 S자 되돌아감(6점)');
    });
  });

  group('검증 고침(2026-10-25 저녁 · 스위치 route) — 사이 줄 비킴 · 받침 카드 위 탭 · 위로 드는 획의 글줄 구간 · 꼬리 줄기 · 함께 쓰는 꼬리 관문', () {
    const t = 15 * m;
    tearDown(PaintPick.reset);

    /// 세 줄(0 · 1 · 2 — 줄 생김새는 [row]와 같다)의 장면.
    (TimelineScene, TimelinePainter) make3(Uint8List bytes) {
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 1080)
        ..setExtent(-2000 * m, 2000 * m)
        ..setContentHeight(426);
      final scene = TimelineScene(
        controller: controller,
        layout: SceneLayout.fromJson({
          'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
          'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1), row(2)]}],
        }),
        fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      controller.showRange(10 * m, 20 * m);
      return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
    }

    Future<List<double>> line(TimelineScene scene, TimelinePainter painter, [int k = 0]) async =>
        nums((await notesOf(scene, painter, '선'))[k].split(' 짙기').first);

    Future<(double, double)> square(TimelineScene scene, TimelinePainter painter, String kind, int band) async {
      final n = nums((await notesOf(scene, painter, '네모')).firstWhere((s) => s.startsWith('$kind $band ')));
      return (n[1], n[2]);
    }

    double topOf(TimelineScene scene, int row) => scene.controller.view.yOf(scene.layout.rowTop(row) + scene.layout.geo(row).bandTop);

    // 0번 줄 앞 나라(1 · t에서 끝남) → 2번 줄 뒤 나라(3 · 앞 나라 끝 − 약 9.6px에서 시작 — 꼬리 내림 꼴) 직접 승계. 1번 줄(사이 줄)에는 사이 나라(5 · [midFrom, midTo]).
    Uint8List fellTile({double? midFrom, double? midTo}) => (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, t - 20 * m, t, '앞 나라')
          ..band(3, 2, t - .05 * m, t + 20 * m, '뒤 나라')
          ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9)
          ..item(LinkLayer.secSquare, 103, 2, t - .05 * m, t + 20 * m, ref: 3, name: '뒤 나라', color: 0xa295aa)
          ..item(LinkLayer.secLink, 201, 0, t, t - .05 * m, row2: 2, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown))
        .build();
    Uint8List withMid(double from, double to) => (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, t - 20 * m, t, '앞 나라')
          ..band(5, 1, from, to, '사이 나라')
          ..band(3, 2, t - .05 * m, t + 20 * m, '뒤 나라')
          ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9)
          ..item(LinkLayer.secSquare, 105, 1, from, to, ref: 5, name: '사이 나라', color: 0xc8b193)
          ..item(LinkLayer.secSquare, 103, 2, t - .05 * m, t + 20 * m, ref: 3, name: '뒤 나라', color: 0xa295aa)
          ..item(LinkLayer.secLink, 201, 0, t, t - .05 * m, row2: 2, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown))
        .build();

    test('사이 줄 비킴: 꼬리 마름모 밑 x를 사이 줄의 띠가 막고 띠 밖 통로(끝 + 9)는 비었으면 꼬리 내림 대신 S자 — 띠 뒤로 숨지 않는다', () async {
      // 사이 나라가 앞 나라와 같은 해에 끝남: 꼬리 마름모(끝 − 7)는 덮고 띠 밖 통로(끝 + 9)는 비운다.
      final (scene, painter) = make3(withMid(t - 20 * m, t));
      addTearDown(scene.dispose);
      final pts = await line(scene, painter);
      final (ec, _) = await square(scene, painter, '멸망', 1);
      expect(pts.length, 12, reason: '되돌아가는 길 6점: $pts');
      expect(pts[2], closeTo(ec + TagLook.diamondX + 9, .05), reason: '첫 세로 획은 띠 밖 통로');
      expect(await notesOf(scene, painter, '굴문'), isEmpty);
      expect(LineAudit.last!.backPaths, 1);
      // 사이 줄이 비었으면 걸음 6 그대로 — 꼬리 내림 뒤 위에서 듦(4점).
      final (free, freePainter) = make3(fellTile());
      addTearDown(free.dispose);
      final open = await line(free, freePainter);
      expect(open.length, 8, reason: '$open');
      expect(open[0], closeTo(ec, .05));
    });

    test('사이 줄 비킴: 띠 밖 통로도 막히면 꼬리 내림 그대로(더 나빠지지 않는다 — 지나는 띠는 굴 문)', () async {
      final (scene, painter) = make3(withMid(t - 20 * m, t + 20 * m));
      addTearDown(scene.dispose);
      final pts = await line(scene, painter);
      final (ec, _) = await square(scene, painter, '멸망', 1);
      expect(pts.length, 8, reason: '$pts');
      expect(pts[0], closeTo(ec, .05));
      expect(await notesOf(scene, painter, '굴문'), isNotEmpty);
      expect(LineAudit.last!.hiddenPx, 0);
    });

    test('꼬리 줄기: 같은 앞 나라에서 꼬리 내림 둘이 종류가 다르면 3px 떨어진 두 줄기 · 관문도 하나씩(예전에는 같은 x에 포개졌다)', () async {
      // 뒤 나라 둘(3 · 1번 줄 직접, 6 · 2번 줄 부흥) 모두 앞 나라 끝 − 약 9.6px에서 시작.
      final bytes = (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, t - 20 * m, t, '앞 나라')
            ..band(3, 1, t - .05 * m, t + 20 * m, '뒤 나라')
            ..band(6, 2, t - .05 * m, t + 20 * m, '먼 뒤 나라')
            ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9)
            ..item(LinkLayer.secSquare, 103, 1, t - .05 * m, t + 20 * m, ref: 3, name: '뒤 나라', color: 0xa295aa)
            ..item(LinkLayer.secSquare, 106, 2, t - .05 * m, t + 20 * m, ref: 6, name: '먼 뒤 나라', color: 0x95aaa2)
            ..item(LinkLayer.secLink, 201, 0, t, t - .05 * m, row2: 1, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown)
            ..item(LinkLayer.secLink, 202, 0, t, t - .05 * m, row2: 2, ref: 1, b: 6, color: 0xabb3c9, a: 2 | lkQFirst | lkDown))
          .build();
      final (scene, painter) = make3(bytes);
      addTearDown(scene.dispose);
      final (ec, y1) = await square(scene, painter, '멸망', 1);
      final xs = [for (int k = 0; k < 2; k++) (await line(scene, painter, k))[0]]..sort();
      expect(xs, [closeTo(ec - 3, .05), closeTo(ec, .05)], reason: '두 줄기');
      // 꼬리 관문의 띠 위 획: 마름모 밑(y1 + 4.5)에서 시작하는 세로 조각이 두 x에 하나씩.
      final segs = [for (final s in await notesOf(scene, painter, '조각')) nums(s)];
      for (final x in xs) {
        expect(segs.where((s) => (s[0] - x).abs() < .06 && (s[1] - (y1 + LinkLook.tipGap)).abs() < .06), hasLength(1), reason: '$x의 꼬리 관문: $segs');
      }
    });

    test('함께 쓰는 꼬리 관문: 같은 줄기의 둘째 선도 그 관문 조각을 제 띠 위 조각으로 센다 — 화면 아래에서 \'안 보임\'으로 세지 않는다', () async {
      // 같은 종류(직접) 둘 — 한 줄기 · 관문 한 번. 그림을 앞 나라 몸통 아랫변까지만 그려 몸통 밑의 몫이 화면 밖이게.
      final bytes = (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, t - 20 * m, t, '앞 나라')
            ..band(3, 1, t - .05 * m, t + 20 * m, '뒤 나라')
            ..band(6, 2, t - .05 * m, t + 20 * m, '먼 뒤 나라')
            ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9)
            ..item(LinkLayer.secSquare, 103, 1, t - .05 * m, t + 20 * m, ref: 3, name: '뒤 나라', color: 0xa295aa)
            ..item(LinkLayer.secSquare, 106, 2, t - .05 * m, t + 20 * m, ref: 6, name: '먼 뒤 나라', color: 0x95aaa2)
            ..item(LinkLayer.secLink, 201, 0, t, t - .05 * m, row2: 1, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown)
            ..item(LinkLayer.secLink, 202, 0, t, t - .05 * m, row2: 2, ref: 1, b: 6, color: 0xabb3c9, a: lkQFirst | lkDown))
          .build();
      final (scene, painter) = make3(bytes);
      addTearDown(scene.dispose);
      final starts = [for (int k = 0; k < 2; k++) (await line(scene, painter, k))[0]];
      final (ec, y1) = await square(scene, painter, '멸망', 1);
      expect(starts, [closeTo(ec, .05), closeTo(ec, .05)], reason: '한 줄기');
      // 꼬리 관문의 문(몸통 아랫변 [body − 1.5, body + .5]) — 화면 아래 끝을 그 몸통 아랫변에 둔다.
      final doors = [for (final d in await notesOf(scene, painter, '문')) nums(d)];
      final gate = doors.where((d) => (d[0] - (ec - 2.2)).abs() < .06 && d[1] > y1 && (d[3] - 2).abs() < .06).toList(); // 문 높이 2 — 굴 문(3)은 빼고
      expect(gate, hasLength(1), reason: '관문은 한 번: $doors');
      final body = gate.single[1] + 1.5;
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), Size(1920, body * scene.controller.view.mag));
      recorder.endRecording().dispose();
      final a = LineAudit.last!;
      expect(a.lines, 2);
      expect(a.invisible, 0, reason: a.detail.join('\n'));
    });

    // 두 줄: 앞 나라(1 · 0번 줄) → 뒤 나라(3 · 1번 줄 · 앞 나라 끝 + 약 9.6px에서 시작) — 오름줄 ┐ 꼴(걸음 6 시험과 같은 자리). [host]면 뒤 나라에 받침 카드 · 탭(구역 47).
    Uint8List riseTile({int? hostLook}) {
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(1, 0, t - 20 * m, t, '앞 나라')
        ..band(4, 1, t - 20 * m, t - .02 * m, '옆 나라')
        ..band(3, 1, t + .05 * m, t + 20 * m, '뒤 나라')
        ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9)
        ..item(LinkLayer.secSquare, 104, 1, t - 20 * m, t - .02 * m, ref: 4, name: '옆 나라', color: 0xc8b193)
        ..item(LinkLayer.secSquare, 103, 1, t + .05 * m, t + 20 * m, ref: 3, name: '뒤 나라', color: 0xa295aa)
        ..item(LinkLayer.secLink, 201, 0, t, t + .05 * m, row2: 1, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown);
      // 뒤 나라를 감싼 받침 카드(구역 47 — 모습 1 칠한 상국 · 7 연합 겹 탭): 상국 탭은 카드 끝 쪽(화면 오른쪽 끝)이라 구멍과 멀다.
      if (hostLook != null) b.item(BandLayer.sectionHostTab, 301, 1, t + .05 * m, t + 20 * m, ref: 3, name: '큰 나라', color: 0x8899aa, a: hostLook, d: 9, text2: 'big');
      return b.build();
    }

    test('위로 드는 획은 사건 글줄 구간을 적지 않는다 — 구멍은 이름 색줄이라 사건 점 · 글자와 만나지 않는다(예전에는 글줄 하나인 띠의 점까지 밀었다)', () async {
      final (scene, painter) = make(riseTile());
      addTearDown(scene.dispose);
      expect((await line(scene, painter)).length, 6, reason: '오름줄 ┐');
      expect(ReservedZones.of(scene).at(1, except: 'names').where((z) => z.strength == 0), isEmpty);
      // 끄면 그 전 규칙(S자라 오름줄이 없다 — 꼬리 내림 관문이 아래로 지나는 몫은 그대로 적는다는 것은 아래 꼬리 내림에서).
      final (fell, fellPainter) = make3(fellTile());
      addTearDown(fell.dispose);
      await notesOf(fell, fellPainter, '선');
      expect(ReservedZones.of(fell).at(0, except: 'names').where((z) => z.strength == 0), isNotEmpty, reason: '앞 나라 몸통을 아래로 지나는 꼬리 내림은 둘째 글줄부터 비킨다');
      expect(ReservedZones.of(fell).at(2, except: 'names').where((z) => z.strength == 0), isEmpty, reason: '뒤 나라 구멍에 위에서 드는 획');
    });

    test('받침 카드 윗단(5px)을 지나는 오름줄: 관문의 띠 위 획을 카드 윗변까지 잇고 카드 윗변에도 문 — 카드는 띠 뒤 선보다 위 판', () async {
      final (scene, painter) = make(riseTile(hostLook: 1));
      addTearDown(scene.dispose);
      final pts = await line(scene, painter);
      final (fc, y2) = await square(scene, painter, '건국', 3);
      final top = topOf(scene, 1);
      expect(pts.length, 6, reason: '오름줄 ┐: $pts');
      final doors = [for (final d in await notesOf(scene, painter, '문')) nums(d)];
      bool doorAt(double y) => doors.any((d) => (d[0] - (fc - 2.2)).abs() < .06 && (d[1] - y).abs() < .06 && (d[3] - 2).abs() < .06);
      expect(doorAt(top - .5), isTrue, reason: '띠 윗변의 문: $doors');
      expect(doorAt(top - BandLayer.sheetRise - .5), isTrue, reason: '카드 윗변의 문: $doors');
      final segs = [for (final s in await notesOf(scene, painter, '조각')) nums(s)];
      expect(segs.any((s) => (s[0] - fc).abs() < .06 && (math.max(s[1], s[3]) - (y2 - LinkLook.tipGap)).abs() < .06 && (math.min(s[1], s[3]) - (top - BandLayer.sheetRise - .5)).abs() < .06), isTrue,
          reason: '구멍 위 변 → 카드 윗변 밖 .5: $segs');
      // 끄면 카드 몫 없이 예전 관문(띠 윗변까지) — 오름줄 자체가 없다(S자).
      PaintPick.route = false;
      final (off, offPainter) = make(riseTile(hostLook: 1));
      addTearDown(off.dispose);
      expect((await line(off, offPainter)).length, 12);
    });

    test('연합 겹 탭이 구멍 위에 설 수 있으면 오름줄 · 위에서 듦을 하지 않는다 — 탭 뒤로 숨지 않게', () async {
      final (scene, painter) = make(riseTile(hostLook: BandLayer.coalLook));
      addTearDown(scene.dispose);
      final pts = await line(scene, painter);
      final (fc, _) = await square(scene, painter, '건국', 3);
      final top = topOf(scene, 1);
      expect(pts.length, isNot(6), reason: '오름줄 ┐이 아니다: $pts');
      final doors = [for (final d in await notesOf(scene, painter, '문')) nums(d)];
      expect(doors.where((d) => (d[0] - (fc - 2.2)).abs() < .06 && (d[1] - (top - .5)).abs() < .06), isEmpty, reason: '구멍 위 윗변 문이 없다: $doors');
    });
  });

  group('짝 꼬리표(구역 60) — 트랙을 건너는 승계는 두 끝 띠의 작은 글로(감독 결정 (2) · 이어 주는 선 걸음 4)', () {
    // 등불 견본의 산호 해상 동맹 → 하연 연합 왕국(부분 승계 — 두 띠는 다른 트랙이다). 이 층은 트랙을 모르므로 두 끝을 0 · 1번 줄에 둔다:
    // 0번 줄의 산호 해상 동맹이 t에서 끝나고(앞 끝 `→ 하연 연합 왕국`), 1번 줄의 하연 연합 왕국이 t에서 시작한다(뒤 끝 `산호 해상 동맹 · 적석 왕국(재건) →`).
    const t = 15 * m;

    /// 구역 60의 한 끝(계약 6-10 · 내보내기 export/links.mjs와 같은 값).
    void cross(TileBuilder b, int id, int row, int band, double at, String name, int to, String uid, {required int side, int kind = 3, int color = 0xa295aa}) =>
        b.item(LinkLayer.secCross, id, row, at, at + 5 * m, ref: band, name: name, color: color, a: side, b: to, c: kind, text2: uid);

    Uint8List crossTile({int kind = 3, double frontLen = 20 * m, double? neighborAt, bool seamLink = false, bool inTrackLink = false, bool backNeighbor = false}) {
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(1, 0, t - frontLen, t, '산호 해상 동맹')
        ..item(LinkLayer.secSquare, 101, 0, t - frontLen, t, ref: 1, name: '산호 해상 동맹', color: 0x8fb3c4, a: seamLink ? sqSeamR : 0)
        ..band(11, 1, t, t + 20 * m, '하연 연합 왕국')
        ..item(LinkLayer.secSquare, 111, 1, t, t + 20 * m, ref: 11, name: '하연 연합 왕국', color: 0xa295aa);
      cross(b, 601, 0, 1, t, '하연 연합 왕국', 11, 'p-union', side: 0, kind: kind);
      cross(b, 602, 1, 11, t, '산호 해상 동맹', 1, 'p-league', side: 1, kind: kind, color: 0x8fb3c4);
      cross(b, 603, 1, 11, t, '적석 왕국(재건)', 26, 'p-jeok', side: 1, kind: kind, color: 0xb07a6a);
      if (neighborAt != null) {
        b
          ..band(7, 0, neighborAt, neighborAt + 1 * m, '하연 총관부')
          ..item(LinkLayer.secSquare, 107, 0, neighborAt, neighborAt + 1 * m, ref: 7, name: '하연 총관부', color: 0xb59aa6, a: seamLink ? sqSeamL : 0);
        // 같은 줄 이음매의 승계(같은 트랙) — 꼬리 마름모가 서고 띠 위 조각(문 · 다리)이 생긴다.
        if (seamLink) b.item(LinkLayer.secLink, 201, 0, t, t, ref: 1, b: 7, color: 0x8fb3c4, a: lkQFirst | lkSeam);
      }
      // 등불 견본처럼 하연 연합 왕국 앞에 하연 부흥국이 맞붙어(같은 줄 · 틈 0) 띠 밖 왼쪽에 자리가 없다.
      if (backNeighbor) {
        b
          ..band(10, 1, t - 20 * m, t, '하연 부흥국')
          ..item(LinkLayer.secSquare, 110, 1, t - 20 * m, t, ref: 10, name: '하연 부흥국', color: 0xd1a6b9);
      }
      // 같은 트랙의 다른 후대(1번 줄 · t + 2m 시작): 꼬리 마름모에서 띠 밖 세로 통로(끝 + 9)로 내려가는 선 — 띠 밖 꼬리표가 비켜야 한다.
      if (inTrackLink) {
        b
          ..band(12, 1, t + 2 * m, t + 6 * m, '검은물 의병')
          ..item(LinkLayer.secSquare, 112, 1, t + 2 * m, t + 6 * m, ref: 12, name: '검은물 의병', color: 0x9ab5a0)
          ..item(LinkLayer.secLink, 202, 0, t, t + 2 * m, row2: 1, ref: 1, b: 12, color: 0x8fb3c4, a: lkQFirst | lkDown);
      }
      return b.build();
    }

    /// '짝꼬리표' 기록 → (띠, 앞/뒤, 갈래, x, y, 폭, 글).
    Future<List<(int, String, int, double, double, double, String)>> tags(TimelineScene scene, TimelinePainter painter) async => [
      for (final s in await notesOf(scene, painter, '짝꼬리표'))
        () {
          final parts = s.split(' ');
          final xyw = [for (final v in parts[3].split(',')) double.parse(v)];
          return (int.parse(parts[0]), parts[1], int.parse(parts[2].substring(2)), xyw[0], xyw[1], xyw[2], parts.sublist(4).join(' '));
        }(),
    ];

    tearDown(PaintPick.reset);

    test('스위치 route를 끄면 짝 꼬리표가 없다 — 그리기 · 누름 · 풍선 글이 함께 빈다(감독 결정 "짝 꼬리표 · 스위치 route" · 걸음 91 끈 찍기)', () async {
      PaintPick.route = false;
      final (scene, painter) = make(crossTile());
      addTearDown(scene.dispose);
      expect(await tags(scene, painter), isEmpty);
      expect([for (final l in painter.debugSink.labels) if (l.kind == 'crossTag') l.text], isEmpty);
      final v = scene.controller.view;
      expect(painter.links.hitCrossTag(v.xOf(t) + CrossTagLook.outGap + 4, v.yOf(19 + TagLook.holeY)), isNull);
    });

    test('① 띠 밖 틈: 앞 끝은 띠 끝 + 4에서 `→ 뒤 나라`, 뒤 끝은 띠 시작 − 4에서 끝나는 `앞 나라 · 앞 나라 →`(여럿은 차례대로 · 로) — 높이는 구멍 · 마름모 줄', () async {
      final (scene, painter) = make(crossTile());
      addTearDown(scene.dispose);
      final list = await tags(scene, painter);
      final v = scene.controller.view, x = v.xOf(t);
      expect(list.length, 2, reason: '$list');
      final front = list.firstWhere((g) => g.$2 == '앞'), back = list.firstWhere((g) => g.$2 == '뒤');
      expect((front.$1, front.$3, front.$7), (1, 1, '→ 하연 연합 왕국'));
      expect(front.$4, closeTo(x + CrossTagLook.outGap, .05), reason: '띠 바깥 끝 + 4');
      expect(front.$5, closeTo(v.yOf(19 + TagLook.holeY), .05), reason: '이름 색줄 가운데(구멍 · 마름모 높이)');
      expect((back.$1, back.$3, back.$7), (11, 1, '산호 해상 동맹 · 적석 왕국(재건) →'));
      expect(back.$4 + back.$6, closeTo(x - CrossTagLook.outGap, .05), reason: '띠 바깥 시작 − 4에서 끝난다');
      expect(back.$5, closeTo(v.yOf(142 + 19 + TagLook.holeY), .05));
      // 꼬리표 글은 글 줄에 — 앞 끝은 화살 · 이름, 뒤 끝은 이름 둘 · 사이 점 · 화살.
      final labels = [for (final l in painter.debugSink.labels) if (l.kind == 'crossTag') l.text];
      expect(labels, containsAll(['→', '하연 연합 왕국', '산호 해상 동맹', '적석 왕국(재건)', CrossTagLook.sep]));
    });

    test('② 맞붙은 이웃 띠(틈 0) · 꼬리 마름모가 선 띠: 이름 색줄 안 마름모 앞 3에 오른쪽을 맞춘다 — 머리 이름 · 띠 위 조각과 겹치지 않는다', () async {
      final (scene, painter) = make(crossTile(neighborAt: t, seamLink: true));
      addTearDown(scene.dispose);
      final front = (await tags(scene, painter)).firstWhere((g) => g.$2 == '앞');
      final squares = await notesOf(scene, painter, '네모');
      final ec = nums(squares.firstWhere((s) => s.startsWith('멸망 1 ')))[1];
      expect(front.$3, 2, reason: '띠 밖은 총관부가 맞붙어 자리가 없다');
      expect(front.$4 + front.$6, closeTo(ec - TagLook.diamondHalf - CrossTagLook.inGap, .05), reason: '마름모 앞 3');
      for (final z in painter.bands.headNameZones[0] ?? const <(double, double)>[]) {
        expect(z.$2 <= front.$4 || z.$1 >= front.$4 + front.$6, isTrue, reason: '머리 글 구간 $z와 겹침');
      }
      for (final s in await notesOf(scene, painter, '조각')) {
        final g = nums(s);
        if ((g[1] - front.$5).abs() > 6 && (g[3] - front.$5).abs() > 6) continue;
        expect(math.max(g[0], g[2]) < front.$4 || math.min(g[0], g[2]) > front.$4 + front.$6, isTrue, reason: '띠 위 조각 $s를 덮음');
      }
    });

    test('② 뒤 끝 앞에 맞붙은 띠: 이름 색줄 안 머리 이름 뒤에 선다 — 머리 이름이 길어도(띠 밖의 밀림 한도 40은 띠 안에 걸지 않는다)', () async {
      final (scene, painter) = make(crossTile(backNeighbor: true));
      addTearDown(scene.dispose);
      final back = (await tags(scene, painter)).firstWhere((g) => g.$2 == '뒤');
      expect((back.$3, back.$7), (2, '산호 해상 동맹 · 적석 왕국(재건) →'), reason: '$back');
      final nameEnd = painter.bands.headNameEnd[11];
      expect(nameEnd, isNotNull);
      final x = scene.controller.view.xOf(t);
      expect(nameEnd! - (x + TagLook.holeX), greaterThan(CrossTagLook.drift), reason: '머리 이름이 밀림 한도보다 길다(그래도 선다)');
      expect(back.$4, greaterThanOrEqualTo(nameEnd + 4), reason: '머리 이름 뒤');
      for (final z in painter.bands.headNameZones[1] ?? const <(double, double)>[]) {
        expect(z.$2 <= back.$4 || z.$1 >= back.$4 + back.$6, isTrue, reason: '머리 글 구간 $z와 겹침');
      }
    });

    test('③ 띠 밖도 이름 색줄 안도 모자라면 `→` 한 글자 — 올리면 풍선 글로 다 보인다', () async {
      // 산호 해상 동맹을 0.2m(≈ 34px)로 줄이고, 0.15m(≈ 25px) 뒤에 이웃 띠를 둔다 — 글 전체는 어디에도 들지 않고 화살 하나는 틈에 든다.
      final (scene, painter) = make(crossTile(frontLen: .2 * m, neighborAt: t + .15 * m));
      addTearDown(scene.dispose);
      final front = (await tags(scene, painter)).firstWhere((g) => g.$2 == '앞');
      final x = scene.controller.view.xOf(t);
      expect(front.$3, 3, reason: '$front');
      expect(front.$4, closeTo(x + CrossTagLook.outGap, .05), reason: '띠 밖 틈의 처음 자리');
      expect(front.$4 + front.$6, lessThanOrEqualTo(scene.controller.view.xOf(t + .15 * m) - CrossTagLook.clear + .05), reason: '이웃 띠 3px 앞');
      final mine = [for (final l in painter.debugSink.labels) if (l.kind == 'crossTag' && (l.at.dy + CrossTagLook.size * .6 - front.$5).abs() < .05) l.text];
      expect(mine, ['→'], reason: '이름은 그리지 않는다');
      final tip = painter.links.crossTipAt(front.$4 + front.$6 / 2, front.$5);
      expect(tip, '산호 해상 동맹 → 하연 연합 왕국 · 부분 승계 · 다른 트랙 — 누르면 하연 연합 왕국 띠로');
    });

    test('맞히기: 꼬리표의 이름 · 점 · 화살을 누르면 이 끝의 띠 → 상대 띠(LinkHitKind.crossTag · scope는 앞/뒤 끝과 상대 uid)', () async {
      final (scene, painter) = make(crossTile());
      addTearDown(scene.dispose);
      final list = await tags(scene, painter);
      final front = list.firstWhere((g) => g.$2 == '앞'), back = list.firstWhere((g) => g.$2 == '뒤');
      final links = painter.links;
      final a = links.hitCrossTag(front.$4 + front.$6 - 2, front.$5);
      expect((a?.kind, a?.band, a?.to, a?.scope), (LinkHitKind.crossTag, 1, 11, '0:p-union'));
      expect(links.hitCrossTag(front.$4 + 1, front.$5)?.scope, '0:p-union', reason: '앞 끝의 화살은 첫 상대');
      // 뒤 끝: 맨 앞 점 · 첫 이름 → 첫 상대, 둘째 이름 → 둘째 상대(화살도 마지막 상대). 글의 자리는 그린 글줄의 기록에서.
      Offset labelAt(String text) => painter.debugSink.labels.firstWhere((l) => l.kind == 'crossTag' && l.text == text).at;
      final b0 = links.hitCrossTag(back.$4 + 2, back.$5);
      expect((b0?.band, b0?.to, b0?.scope), (11, 1, '1:p-league'));
      expect(links.hitCrossTag(labelAt('산호 해상 동맹').dx + 3, back.$5)?.to, 1);
      final b1 = links.hitCrossTag(labelAt('적석 왕국(재건)').dx + 3, back.$5);
      expect((b1?.to, b1?.scope), (26, '1:p-jeok'));
      expect(links.crossTipAt(labelAt('적석 왕국(재건)').dx + 3, back.$5), '적석 왕국(재건) → 하연 연합 왕국 · 부분 승계 · 다른 트랙 — 누르면 적석 왕국(재건) 띠로');
      expect(links.hitCrossTag(back.$4 + back.$6 - 1, back.$5)?.to, 26);
      // 꼬리표 밖 · 위아래로 벗어나면 없다. 선 맞히기(hitLinks)는 꼬리표를 모른다(앱 틀이 이것을 먼저 묻는다).
      expect(links.hitCrossTag(front.$4 + front.$6 + 10, front.$5), isNull);
      expect(links.hitCrossTag(front.$4 + 4, front.$5 + 12), isNull);
      expect(links.hitLinks(front.$4 + front.$6 - 2, front.$5)?.kind, isNot(LinkHitKind.crossTag));
    });

    test('거름: 메뉴 \'직접 승계만\'이면 c가 직접인 것만 · \'숨기기\'면 없다 · 옛 저장소(구역 60 없음)는 그대로', () async {
      final (partial, pp) = make(crossTile());
      addTearDown(partial.dispose);
      pp.links.successionMode = 1;
      expect(await tags(partial, pp), isEmpty, reason: '부분 승계(c 3)는 직접만 보기에서 빠진다');
      final (direct, dp) = make(crossTile(kind: 0));
      addTearDown(direct.dispose);
      dp.links.successionMode = 1;
      expect((await tags(direct, dp)).length, 2, reason: '직접 승계(c 0)는 남는다');
      final (hidden, hp) = make(crossTile(kind: 0));
      addTearDown(hidden.dispose);
      hp.links.successionMode = 2;
      expect(await tags(hidden, hp), isEmpty);
      expect(await notesOf(hidden, hp, '네모'), isNotEmpty, reason: '구멍은 그대로');
      // 구역 60이 없는 타일(옛 저장소): 꼬리표 기록도 글도 없다.
      final (old, op) = make(seamTile(t: t));
      addTearDown(old.dispose);
      expect(await tags(old, op), isEmpty);
      expect(op.debugSink.labels.where((l) => l.kind == 'crossTag'), isEmpty);
    });

    test('끊김 · 가림 0: 띠 밖 꼬리표는 같은 띠에서 나가는 선(꼬리 마름모 → 끝 + 9 통로)을 덮지 않게 비켜 서고, 사건 글줄은 막지 않는다', () async {
      final (scene, painter) = make(crossTile(inTrackLink: true));
      addTearDown(scene.dispose);
      final front = (await tags(scene, painter)).firstWhere((g) => g.$2 == '앞');
      final x = scene.controller.view.xOf(t);
      expect(front.$3, 1);
      expect(front.$4, greaterThan(x + 9), reason: '세로 통로(끝 + 9) 뒤로 비켜 섰다');
      expect(front.$4 - (x + CrossTagLook.outGap), lessThanOrEqualTo(CrossTagLook.drift), reason: '띠 끝에서 멀어지지 않는다');
      final half = CrossTagLook.size * .6;
      final lines = [for (final s in await notesOf(scene, painter, '선')) nums(s.split(' 짙기').first)];
      expect(lines, isNotEmpty);
      for (final pts in lines) {
        for (int i = 2; i < pts.length; i += 2) {
          final (ax, ay, bx, by) = (pts[i - 2], pts[i - 1], pts[i], pts[i + 1]);
          if (math.max(ay, by) < front.$5 - half || math.min(ay, by) > front.$5 + half) continue;
          expect(math.max(ax, bx) + 1 < front.$4 || math.min(ax, bx) - 1 > front.$4 + front.$6, isTrue, reason: '선 토막 ($ax,$ay)-($bx,$by)를 꼬리표가 덮음');
        }
      }
      // 보통 밀도: 꼬리표는 이름 색줄(띠 윗변 ~ + 14)이라 흰 사건 칸의 글줄과 겹치지 않는다 — 사건이 비켜 갈 구간을 적지 않는다.
      expect(ReservedZones.of(scene).at(0, except: 'names'), isEmpty);
      expect(ReservedZones.of(scene).at(1, except: 'names'), isEmpty);
    });

    test('조감(밀도 2): 띠 밖 꼬리표는 띠 가운데 높이 — 그 줄의 글줄(띠 전체)에 들어 사건 이름이 비킬 구간(세기 1)을 적는다', () async {
      final (scene, painter) = make(crossTile());
      addTearDown(scene.dispose);
      scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
      final list = await tags(scene, painter);
      expect(list, isNotEmpty);
      final front = list.firstWhere((g) => g.$2 == '앞');
      expect(front.$3, isNot(2), reason: '조감에는 이름 색줄이 없다');
      final zones = ReservedZones.of(scene).at(0, except: 'names');
      expect(zones.length, 1, reason: '$zones');
      expect((zones.single.line, zones.single.strength), (0, 1));
      final v = scene.controller.view;
      expect(v.xOf(zones.single.lo), closeTo(front.$4 - 2, .5));
      expect(v.xOf(zones.single.hi), closeTo(front.$4 + front.$6 + 2, .5));
    });
  });

  group('대범위 — 테두리(23) · 기간 칠(24) · 할거기 칠(25)', () {
    /// 두 줄에 걸친 켠 대범위 하나와, 본국 띠의 할거기 칠.
    Uint8List scopeTile({int a = 0}) {
      const t = 15 * m;
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(1, 0, t - 20 * m, t + 20 * m, '본국')
        ..item(ScopeLayer.secScope, 301, 0, t - 2 * m, t + 2 * m, row2: 1, ref: 1, name: '두 물결', color: 0xa27e76, a: a, b: 4, text2: '할거')
        ..item(ScopeLayer.secSpan, 302, 0, t - 1 * m, t + 1 * m, row2: 1, ref: 1, color: 0xa27e76)
        ..item(ScopeLayer.secHollow, 401, 0, t - 2 * m, t + 2 * m, ref: 1, name: '두 물결', color: 0xa27e76, text2: '할거');
      return b.build();
    }

    // 리메이크 2부(감독 2026-10-15 "접고 펴는 것은 플래그 하나에"): 조감이 아니면 소속 단추(예전 — 이름 줄 전체를 세기 0으로 막고
    // 분류별 글줄이 있는 줄에서는 첫 글줄의 점도 밀었다) 대신 꼬리표마다 플래그 하나를 띠 윗변 위에 얹는다. 플래그는 사건 이름 줄을 막지 않는다.
    test('소속 단추 대신 꼬리표 윗변의 플래그 하나 — 사건 이름 줄을 막지 않고, 누르면 플래그(띠 번호)', () async {
      const t = 15 * m;
      // 줄 0은 분류별 글줄(cats 둘) · 줄 1은 보통 글줄. 어느 줄이든 같은 꼴이다.
      final json = {
        'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
        'tracks': [
          {
            'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래',
            'rows': [{...row(0), 'kind': 0, 'cats': [0, 1]}, {...row(1), 'kind': 0}],
          },
        ],
      };
      final bytes = (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, t - 20 * m, t + 20 * m, '본국')
            ..band(2, 1, t - 20 * m, t + 20 * m, '이웃')
            ..item(ScopeMarks.secMemBtn, 501, 0, t - 20 * m, t + 20 * m, ref: 1, name: '', color: 0xa27e76, a: 3)
            ..item(ScopeMarks.secMemBtn, 502, 1, t - 20 * m, t + 20 * m, ref: 2, name: '', color: 0xa27e76, a: 3))
          .build();
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 1080)
        ..setExtent(-2000 * m, 2000 * m)
        ..setContentHeight(284);
      final scene = TimelineScene(
        controller: controller,
        layout: SceneLayout.fromJson(json),
        fetchTile: (level, x, chunk, packs) async =>
            level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      addTearDown(scene.dispose);
      controller.showRange(10 * m, 20 * m);
      final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
      final buttons = await notesOf(scene, painter, '단추');
      expect(buttons, isEmpty, reason: '조감이 아니면 단추를 그리지 않는다');
      final v = scene.controller.view;
      for (final (row, band) in [(0, 1), (1, 2)]) {
        // 머리 이름의 구간(띠 층 · 출처 'names')은 빼고 본다 — 그 밖에 이 줄의 이름 자리를 막는 것이 없다.
        expect(ReservedZones.of(scene).at(row, except: 'names'), isEmpty, reason: '줄 $row: 플래그는 이름 줄을 막지 않는다');
        final flag = painter.links.flagOf(band);
        expect(flag, isNotNull, reason: '줄 $row');
        // 띠 시작이 화면 왼쪽 밖이라 그림판 왼쪽 + 16 · 아랫변이 띠 윗변(14 × 7).
        final top = v.yOf(scene.layout.rowTop(row) + scene.layout.geo(row).bandTop).roundToDouble();
        expect(flag!.rect, ui.Rect.fromLTWH((v.left + FlagLook.from).roundToDouble(), top - FlagLook.h, FlagLook.w, FlagLook.h), reason: '줄 $row');
        expect([for (final e in flag.entries) (e.kind, e.label, e.count, e.on)], [(FlagKind.members, '소속', 3, false)], reason: '줄 $row: 창의 칸은 소속 하나');
        final hit = painter.links.hitLinks(flag.rect.center.dx, flag.rect.center.dy);
        expect((hit?.kind, hit?.band), (LinkHitKind.flag, band), reason: '줄 $row: 누르면 그 띠의 플래그');
      }
    });

    test('그릇 폴더(리메이크 조각 ③)는 가지의 첫 줄 위 26px(머리 21 + 줄 위 틈 5)에서 마지막 줄 아래 7px까지 — 어깨 탭 20 아래가 몸통', () async {
      final (scene, painter) = make(scopeTile());
      addTearDown(scene.dispose);
      expect(await notesOf(scene, painter, '대범위'), isEmpty, reason: '조감이 아니면 옛 둥근 테두리는 그리지 않는다');
      final boxes = await notesOf(scene, painter, '폴더');
      expect(boxes.length, 1);
      final v = nums(boxes.first);
      // top(탭 위) = rowTop(0) + bandTop(19) − 줄 위 틈 5 − 머리 21 = −7 · 아래 = 142 + 142 + 발 7 = 291 → 높이 298
      expect(v[1], closeTo(scene.controller.view.yOf(-7).roundToDouble(), .05));
      expect(v[3], closeTo(298, .05));
      // 탭의 라벨 종이: 이름 + 구성 수(항목의 b) — 몸통 윗변(탭 위 + 20) 위 2에 아랫변(높이 15).
      final tab = await notesOf(scene, painter, '폴더탭');
      expect(tab.single, startsWith('두 물결 '));
      final t = nums(tab.single);
      expect(t[1], closeTo(v[1] + 20 - 2 - 15, .05)); // 라벨의 위(기록: 탭 왼쪽~오른쪽 · 라벨 왼쪽,위,너비)
      expect(painter.debugSink.notes['폴더']!.single.toString(), contains('open'), reason: '변형이 없는 장면은 펼침으로 그린다(손잡이 없음)');
    });

    test('폴더는 본국 띠에 매달리지 않는다 — 매달림 비트가 있어도 제 어깨 탭으로 같은 자리', () async {
      final (scene, painter) = make(scopeTile(a: 1));
      addTearDown(scene.dispose);
      final boxes = await notesOf(scene, painter, '폴더');
      expect(boxes.first, isNot(contains('매달림')));
      expect(nums(boxes.first)[1], closeTo(scene.controller.view.yOf(-7).roundToDouble(), .05));
    });

    test('풀린 그릇의 열쇠표(구역 50): 구성 띠 윗변 위 2에 높이 12 · 띠 시작 + 16 + 3에서 — 켠 대범위의 것은 그리지 않는다', () async {
      const t = 15 * m;
      Uint8List keyTile() => (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, t - 20 * m, t + 20 * m, '본국')
            ..item(ScopeMarks.secKey, 601, 0, t - 20 * m, t + 20 * m, ref: 1, name: '두 물결', color: 0xa27e76, text2: 's-two'))
          .build();
      final (scene, painter) = make(keyTile());
      addTearDown(scene.dispose);
      final keys = await notesOf(scene, painter, '열쇠표');
      expect(keys.single, startsWith('두 물결 '));
      final v = nums(keys.single);
      final view = scene.controller.view;
      // 띠 시작은 화면 왼쪽 밖이라 실은 그림판 왼쪽 + 2에서, 열쇠표는 그 + 3 · 위는 띠 윗변(19) − 2 − 12.
      expect(v[1], closeTo((view.yOf(19)).roundToDouble() - 14, .05));
      expect(v[0], greaterThanOrEqualTo(scene.layout.gutterWidth));
      // 그 대범위를 켜면(펼침 · 접힘) 열쇠표가 없다 — 폴더가 이름을 보인다.
      final marks = SceneMarks.of(scene)..scopesOn = {'s-two'};
      marks.version++;
      painter.debugSink.notes.clear();
      expect(await notesOf(scene, painter, '열쇠표'), isEmpty);
    });

    // 0.1.0 1배 지적(등불 넓게 · 판 3 등불 — 갈대 공국): 4단계에 상국 탭이 생기며 같은 띠 윗변 위 틈에 앉는 열쇠표 '아홉 불씨 할거'가 탭 '아랫물국'의
    // '아'를 덮어 '…할거 랫물국'으로 읽혔다. 탭은 관계가 끝나는 해에 매여 움직이지 않고 열쇠표가 비킨다 — 탭 뒤 · 구멍만 · 닿지 않으면 그대로.
    test('풀린 그릇의 열쇠표는 같은 띠의 상국 탭을 비킨다 — 탭 뒤로 밀거나(띠 안에 들 때) 구멍만 남기고, 닿지 않으면 1px도 움직이지 않는다', () async {
      const label = '아홉 불씨 할거', host = '아랫물국';
      // 띠 1(줄 0)은 [a, b] · 그 띠의 섬김(뒤 장 · 상국 탭)은 [a, hostEnd] · 열쇠표는 띠 전체.
      Future<({List<double> key, List<double>? tab, String? moved, bool text, TimelinePainter painter})> shot(double a, double b, double? hostEnd) async {
        final t = TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, a, b, '갈대 공국')
          ..item(ScopeMarks.secKey, 601, 0, a, b, ref: 1, name: label, color: 0xa27e76, text2: 's-nine');
        if (hostEnd != null) t.item(BandLayer.sectionHostTab, 52, 0, a, hostEnd, ref: 1, name: host, color: 0x8b6f47, a: 1, d: 99, text2: 'p/lower');
        final (scene, painter) = make(t.build());
        addTearDown(scene.dispose);
        final keys = await notesOf(scene, painter, '열쇠표');
        final tabs = [for (final n in painter.debugSink.notes['상국탭'] ?? const <Object>[]) '$n'];
        final moved = [for (final n in painter.debugSink.notes['열쇠표비킴'] ?? const <Object>[]) '$n'];
        return (
          key: [for (final s in keys.single.split(' ').last.split(',')) double.parse(s)],
          tab: tabs.isEmpty ? null : [for (final s in tabs.single.split(' ').last.split(',')) double.parse(s) / 10],
          moved: moved.isEmpty ? null : moved.single,
          text: painter.debugLabels.any((l) => l.kind == 'key' && l.text == label),
          painter: painter,
        );
      }

      void apart(List<double> key, List<double> tab, String what) {
        final (kl, kr, tl, tr) = (key[0], key[0] + key[2], tab[0], tab[0] + tab[1]);
        expect(kr + FolderLook.keyGap <= tl || kl >= tr + FolderLook.keyGap, isTrue, reason: '$what: 열쇠표 $kl ~ $kr · 탭 $tl ~ $tr — 4 넘게 떨어져야 한다');
      }

      // (가) 닿지 않음: 넓은 띠의 끝에 선 탭 — 열쇠표는 탭이 없을 때와 같은 자리 · 같은 꼴.
      final bare = await shot(11 * m, 19 * m, null);
      final far = await shot(11 * m, 19 * m, 19 * m);
      expect(far.tab, isNotNull, reason: '(가) 탭이 섰다');
      expect(far.key, bare.key, reason: '(가) 탭과 닿지 않는 열쇠표는 그대로');
      expect((far.moved, far.text), (null, true));
      apart(far.key, far.tab!, '(가)');

      // (나) 탭 뒤로: 섬김이 띠 첫머리에서 일찍 끝나 탭이 열쇠표 자리에 선다 — 띠가 넉넉하면 열쇠표를 탭 뒤 4로 민다(실도 함께 — 45°).
      final early = await shot(11 * m, 19 * m, 11.6 * m);
      final tab = early.tab!;
      expect(tab[0], lessThan(bare.key[0] + bare.key[2]), reason: '(나) 비키지 않았다면 겹쳤다 — 탭 $tab · 열쇠표 ${bare.key}');
      expect(early.moved, contains('탭 뒤'));
      expect(early.key[0], (tab[0] + tab[1] + FolderLook.keyGap).roundToDouble(), reason: '(나) 탭 오른쪽 + 4');
      expect((early.key[1], early.key[2]), (bare.key[1], bare.key[2]), reason: '(나) 높이 · 폭은 그대로');
      expect(early.text, isTrue, reason: '(나) 이름도 그대로');
      apart(early.key, tab, '(나)');

      // (다) 구멍만: 좁은 띠(갈대 공국처럼) 끝의 탭 — 탭 뒤로 밀면 띠 밖으로 내미므로 제자리에 구멍만 남긴 작은 열쇠표(이름 없음 · 누르면 그대로 펼침).
      final narrow = await shot(11 * m, 11.75 * m, 11.75 * m);
      final tab2 = narrow.tab!;
      expect(narrow.moved, contains('구멍만'));
      expect(narrow.key[0], bare.key[0], reason: '(다) 제자리');
      expect(narrow.key[2], FolderLook.keyStub, reason: '(다) 구멍만 남긴 폭');
      expect(narrow.text, isFalse, reason: '(다) 이름을 적지 않는다');
      apart(narrow.key, tab2, '(다)');
      final hit = narrow.painter.links.hitLinks(narrow.key[0] + 6, narrow.key[1] + 6);
      expect((hit?.kind, hit?.scope), (LinkHitKind.scopeButton, 's-nine'), reason: '(다) 누르면 그 그릇');
    });

    test('할거기 칠은 띠 테두리 안쪽(위아래 1px씩)에 든다', () async {
      final (scene, painter) = make(scopeTile());
      addTearDown(scene.dispose);
      final hollow = await notesOf(scene, painter, '할거기');
      expect(hollow.length, 1);
      final v = nums(hollow.first);
      expect(v[2], closeTo(scene.controller.view.yOf(19) + 1, .05)); // 띠 위 자리 + 테두리 1
      expect(v[4], closeTo(123 - 2, .05)); // 띠 높이 − 테두리 둘
    });
  });

  // 같은 줄에서 띠 하나를 건너뛰는 승계선(앞 나라 → 뒷 나라 — 사이에 가운데 나라)은 띠 뒤 선이라 가운데 나라가 가린다. 그런데 고르면 가운데 나라가
  // 흐려져(.58) 뒤가 비치므로, 고른 띠에 닿아 짙어진 선이 그 이름 · 점을 줄 긋듯 가로질렀다(등불 V 조감에서 등불 왕국을 누르면 하연 총관부 위로 —
  // 2026-10-25 조감 글자 겹침 검증). 흐린 띠의 구간에서는 선을 끊는다(LinkLayer._cutBehindDim).
  group('흐린 띠 뒤로 지나는 같은 줄의 선', () {
    const t = 15 * m;
    Uint8List skipTile() => (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, t - 20 * m, t, '앞 나라')
          ..band(2, 0, t + .5 * m, t + 1.5 * m, '가운데 나라')
          ..band(3, 0, t + 2.5 * m, t + 20 * m, '뒷 나라')
          ..item(LinkLayer.secSquare, 101, 0, t - 20 * m, t, ref: 1, name: '앞 나라', color: 0xabb3c9)
          ..item(LinkLayer.secSquare, 102, 0, t + .5 * m, t + 1.5 * m, ref: 2, name: '가운데 나라', color: 0xa295aa)
          ..item(LinkLayer.secSquare, 103, 0, t + 2.5 * m, t + 20 * m, ref: 3, name: '뒷 나라', color: 0x9ab5a0)
          ..item(LinkLayer.secLink, 201, 0, t, t + 2.5 * m, row2: 0, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst))
        .build();

    for (final bird in [false, true]) {
      test('${bird ? '조감' : '보통 밀도'}: 고르기 전에는 선 하나 — 고르면 흐려진 가운데 나라의 구간을 끊고 두 끝은 그대로', () async {
        // 보통 밀도는 스위치 route(이어 주는 선 — 기본 켬)면 같은 줄 ⊓로 사이 띠 위를 건너가 띠 뒤로 지나는 곧은 선이 없다(아래 시험) —
        // 곧은 선의 끊음은 route를 끈 길에서 본다(4단계 마지막 합치기 — zoom cc34832 × line-routing). route면 흐린 띠도 불투명 종이라 끊지 않고
        // 굴 문을 둔다(검토 지적 — 아래 '조감 · route 켬' 시험).
        PaintPick.route = false;
        addTearDown(PaintPick.reset);
        final (scene, painter) = make(skipTile());
        addTearDown(scene.dispose);
        if (bird) scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
        final plain = await notesOf(scene, painter, '선');
        expect(plain.length, 1, reason: '흐린 띠가 없으면 예전 그대로 선 하나: $plain');
        em.Emphasis.of(scene)
          ..reduceMotion = true
          ..set(const em.Look(band: 1));
        painter.debugSink.notes.clear();
        final cut = await notesOf(scene, painter, '선');
        expect(cut.length, 2, reason: '가운데 나라 앞 · 뒤 두 조각: $cut');
        final view = scene.controller.view;
        final (whole, l, r) = (nums(plain.single), nums(cut[0]), nums(cut[1]));
        expect(l[0], closeTo(whole[0], .01), reason: '앞 끝은 그대로');
        expect(l[2], closeTo(view.xOf(t + .5 * m), .01), reason: '가운데 나라 앞에서 멎는다');
        expect(r[0], closeTo(view.xOf(t + 1.5 * m), .01), reason: '가운데 나라 끝에서 다시');
        expect(r[2], closeTo(whole[2], .01), reason: '뒤 끝은 그대로');
        expect((l[1], r[1], r[3]), (whole[1], whole[1], whole[1]), reason: '높이는 그대로');
        expect(l.last, closeTo(1, .01), reason: '고른 띠에 닿는 선은 짙기 1');
        expect(r.last, closeTo(1, .01));
      });
    }

    test('조감 · route 켬(기본): 흐린 띠도 불투명 종이라 끊지 않는다 — 고르기 전후 같은 한 획 · 흐린 가운데 나라의 테에 굴 문', () async {
      final (scene, painter) = make(skipTile());
      addTearDown(scene.dispose);
      expect(PaintPick.route, isTrue);
      scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
      final plain = await notesOf(scene, painter, '선');
      final plainTunnels = await notesOf(scene, painter, '굴문');
      expect(plain.length, 1, reason: '$plain');
      expect(plainTunnels.where((s) => s.startsWith('2 ')), isNotEmpty, reason: '가운데 나라 뒤로 지나는 몫에 굴 문: $plainTunnels');
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(const em.Look(band: 1));
      painter.debugSink.notes.clear();
      final picked = await notesOf(scene, painter, '선');
      expect(picked.length, 1, reason: '흐려도 끊지 않는다: $picked');
      expect(nums(picked.single).take(4), nums(plain.single).take(4), reason: '길은 그대로');
      expect(nums(picked.single).last, closeTo(1, .01), reason: '고른 띠에 닿는 선은 짙기 1');
      final tunnels = await notesOf(scene, painter, '굴문');
      expect(tunnels.where((s) => s.startsWith('2 ')), isNotEmpty, reason: '흐린 가운데 나라에도 굴 문 — 고른 선이 표시 없이 끊기지 않게: $tunnels');
    });

    test('보통 밀도 · route 켬(기본): 같은 줄 ⊓는 사이 띠 위 틈으로 건너가 흐린 띠 뒤로 지나지 않는다 — 고르기 전후 같은 한 획(끊을 몫이 없음)', () async {
      final (scene, painter) = make(skipTile());
      addTearDown(scene.dispose);
      expect(PaintPick.route, isTrue);
      final plain = await notesOf(scene, painter, '선');
      expect(plain.length, 1, reason: '$plain');
      final p = nums(plain.single);
      expect(p.length, 4 * 2 + 1, reason: '⊓ 네 점 + 짙기: ${plain.single}');
      final view = scene.controller.view;
      final gy = p[3];
      expect((p[5], gy), (gy, gy), reason: '위 틈의 가로 획');
      expect(p[0] < view.xOf(t + .5 * m) && p[4] > view.xOf(t + 1.5 * m), isTrue, reason: '가운데 나라 너머로 건너감: ${plain.single}');
      expect(gy < p[1], isTrue, reason: '줄 위로 올라감: ${plain.single}');
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(const em.Look(band: 1));
      painter.debugSink.notes.clear();
      final picked = await notesOf(scene, painter, '선');
      expect(picked.length, 1, reason: '흐린 가운데 나라 뒤로 지나지 않으니 끊지 않는다: $picked');
      expect(nums(picked.single).take(8), p.take(8), reason: '길은 그대로');
      expect(nums(picked.single).last, closeTo(1, .01), reason: '고른 띠에 닿는 선은 짙기 1');
    });

    test('가운데 나라를 고르면(흐려지지 않음) 끊지 않는다 — 선은 .14로 옅어질 뿐', () async {
      final (scene, painter) = make(skipTile());
      addTearDown(scene.dispose);
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(const em.Look(band: 2));
      final lines = await notesOf(scene, painter, '선');
      expect(lines.length, 1, reason: '$lines');
      expect(nums(lines.single).last, closeTo(.14, .01));
    });
  });
}

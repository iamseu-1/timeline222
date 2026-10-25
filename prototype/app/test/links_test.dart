import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/paint/links.dart';
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
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/paint/links.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/scopes.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 0.1.1 승계선 나머지(이어 주는 선 조사 결함 4 · 5 · 6 · 8 · 11 · 13 · 42 · 43 · 미룸 4 — 명세 04 3-6 · 7-2 · 스위치 route)의 검사.
// 장면은 1920 × 1080 · 10 ~ 20백만 분(1백만 분 = 168px) — links_test와 같은 틀이다.

const m = 1000000.0;
const t = 15 * m;

/// 구역 21(승계선)의 a 비트.
const lkDown = 1 << 4, lkQFirst = 1 << 5, lkSeam = 1 << 6;

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

(TimelineScene, TimelinePainter) make(Uint8List bytes, int rows, {bool bird = false}) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(142.0 * rows);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
      'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [for (int r = 0; r < rows; r++) row(r)]}],
    }),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  if (bird) scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
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

List<double> nums(String text) => [for (final s in text.split(RegExp('[ ,]'))) double.tryParse(s) ?? double.nan].where((v) => !v.isNaN).toList();

/// 기록 '승계길'(선대→후대 꺾은점들 [합류]) — '선대→후대' → 꺾은점([x0, y0, x1, y1, …]).
Future<Map<String, List<double>>> paths(TimelineScene scene, TimelinePainter painter) async {
  final out = <String, List<double>>{};
  for (final s in await notesOf(scene, painter, '승계길')) {
    final parts = s.split(' ');
    out[parts.first] = [for (final p in parts.skip(1)) if (p != '합류') ...p.split(',').map(double.parse)];
  }
  return out;
}

/// 띠와 그 네모(구역 20) 하나.
void sq(TileBuilder b, int id, int r, double from, double to, String name, {int color = 0xabb3c9}) => b
  ..band(id, r, from, to, name)
  ..item(LinkLayer.secSquare, 100 + id, r, from, to, ref: id, name: name, color: color);

/// 띠 [band]의 건국(구멍) · 멸망(마름모) x · y(기록 '네모').
Future<(double, double)> squareOf(TimelineScene scene, TimelinePainter painter, String kind, int band) async {
  final n = nums((await notesOf(scene, painter, '네모')).firstWhere((s) => s.startsWith('$kind $band ')));
  return (n[1], n[2]);
}

double topOf(TimelineScene scene, int r) => scene.controller.view.yOf(scene.layout.rowTop(r) + scene.layout.geo(r).bandTop);
double xOf(TimelineScene scene, double minute) => scene.controller.view.xOf(minute);

void main() {
  // 0.1.1 다-1(감독 고름 2026-10-26): 선 길 route는 기본 끔 — 이 파일은 새 길의 값을 `--paint-on=route`와 같은 뜻(route = true)으로 지킨다(끈 꼴은 제 시험이 route = false로).
  setUp(() => PaintPick.route = true);
  tearDown(PaintPick.reset);
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(PaintPick.reset);

  group('통로 번호 다시 세기(조사 결함 6 · 명세 04 8-1)', () {
    test('메뉴 \'직접 승계만\'이 간접 선을 거르면 직접 선이 그 통로를 쓴다(끝 + 9) — 끄면 구역 21의 기준값(끝 + 14)', () async {
      Uint8List tile() {
        final b = TileBuilder(level: 9, x: 0, chunk: 0);
        sq(b, 1, 0, t - 20 * m, t, '앞 나라');
        sq(b, 9, 1, t + 2 * m, t + 6 * m, '가 나라');
        sq(b, 10, 2, t + 2.5 * m, t + 6 * m, '나 나라');
        b
          ..item(LinkLayer.secLink, 201, 0, t, t + 2 * m, row2: 1, ref: 1, b: 9, color: 0xabb3c9, a: 1 | lkQFirst | lkDown)
          ..item(LinkLayer.secLink, 202, 0, t, t + 2.5 * m, row2: 2, ref: 1, b: 10, color: 0xabb3c9, a: lkQFirst | lkDown, c: 10);
        return b.build();
      }

      Future<List<double>> direct() async {
        final (scene, painter) = make(tile(), 3);
        addTearDown(scene.dispose);
        final marks = SceneMarks.of(scene)..successionMode = 1;
        marks.version++;
        final p = await paths(scene, painter);
        expect(p.keys, ['1→10'], reason: '간접 선은 걸러진다');
        return p['1→10']!;
      }

      final qe = xOf(make(tile(), 3).$1, t);
      expect((await direct())[2], closeTo(qe + 9, .05), reason: '다시 센 통로 번호 0');
      PaintPick.route = false;
      expect((await direct())[2], closeTo(qe + 14, .05), reason: '기준값(통로 번호 1)');
    });

    test('위로 가는 선과 아래로 가는 선은 따로 센다 — 둘 다 끝 + 9(예전에는 둘째가 + 14)', () async {
      // 앞 나라(1 · 1번 줄) → 위 나라(9 · 0번 줄 · 위로) · 아래 나라(10 · 2번 줄 · 아래로).
      final b = TileBuilder(level: 9, x: 0, chunk: 0);
      sq(b, 1, 1, t - 20 * m, t, '앞 나라');
      sq(b, 9, 0, t + 2 * m, t + 6 * m, '위 나라');
      sq(b, 10, 2, t + 2.5 * m, t + 6 * m, '아래 나라');
      b
        ..item(LinkLayer.secLink, 201, 0, t, t + 2 * m, row2: 1, ref: 1, b: 9, color: 0xabb3c9, a: lkQFirst)
        ..item(LinkLayer.secLink, 202, 1, t, t + 2.5 * m, row2: 2, ref: 1, b: 10, color: 0xabb3c9, a: lkQFirst | lkDown, c: 10);
      final bytes = b.build();
      final (scene, painter) = make(bytes, 3);
      addTearDown(scene.dispose);
      final p = await paths(scene, painter);
      final qe = xOf(scene, t);
      expect(p['1→9']![2], closeTo(qe + 9, .05));
      expect(p['1→10']![2], closeTo(qe + 9, .05));
      PaintPick.route = false;
      final (off, offPainter) = make(bytes, 3);
      addTearDown(off.dispose);
      expect((await paths(off, offPainter))['1→10']![2], closeTo(qe + 14, .05));
    });
  });

  group('hv 빈 기둥 · 후대 줄의 틈으로 들기(조사 결함 4 · 8 · 42)', () {
    test('사이 줄의 띠가 띠 밖 통로를 막으면 막은 띠 오른끝 + 4로 통로째 옮긴다 — 끄면 끝 + 9(사이 띠 뒤로)', () async {
      Uint8List tile() {
        final b = TileBuilder(level: 9, x: 0, chunk: 0);
        sq(b, 1, 0, t - 20 * m, t, '앞 나라');
        sq(b, 5, 1, t - 1 * m, t + .2 * m, '사이 나라');
        sq(b, 3, 2, t + 1 * m, t + 6 * m, '뒤 나라');
        b.item(LinkLayer.secLink, 201, 0, t, t + 1 * m, row2: 2, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown);
        return b.build();
      }

      final (scene, painter) = make(tile(), 3);
      addTearDown(scene.dispose);
      final pts = (await paths(scene, painter))['1→3']!;
      expect(pts.length, 8, reason: 'hv 네 점: $pts');
      expect(pts[2], closeTo(xOf(scene, t + .2 * m) + 4, .05), reason: '사이 나라 오른끝 + 4');
      expect(await notesOf(scene, painter, '굴문'), isEmpty, reason: '사이 띠 뒤로 지나지 않는다');
      PaintPick.route = false;
      final (off, offPainter) = make(tile(), 3);
      addTearDown(off.dispose);
      expect((await paths(off, offPainter))['1→3']![2], closeTo(xOf(off, t) + 9, .05));
    });

    test('아래로 가는 선: 후대 줄에서 통로와 후대 사이에 다른 띠가 있으면 후대 줄 위 틈을 따라 구멍 위까지 와서 위에서 든다 — 숨은 px 0 · 굴 문 없음', () async {
      Uint8List tile() {
        final b = TileBuilder(level: 9, x: 0, chunk: 0);
        sq(b, 1, 0, t - 20 * m, t, '앞 나라');
        sq(b, 4, 1, t + .2 * m, t + .8 * m, '앞 띠');
        sq(b, 3, 1, t + 1 * m, t + 6 * m, '뒤 나라');
        b.item(LinkLayer.secLink, 201, 0, t, t + 1 * m, row2: 1, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown);
        return b.build();
      }

      final (scene, painter) = make(tile(), 2);
      addTearDown(scene.dispose);
      final pts = (await paths(scene, painter))['1→3']!;
      final (fc, y2) = await squareOf(scene, painter, '건국', 3);
      final top = topOf(scene, 1);
      expect(pts.length, 10, reason: '마름모 → 통로 → 틈 → 구멍 위 → 구멍: $pts');
      expect(pts[2], closeTo(xOf(scene, t) + 9, .05));
      final gy = pts[5];
      expect(gy, lessThan(top - scene.layout.tabOf(1)), reason: '뒤 나라 줄 위 틈(탭 자리 위)');
      expect(gy, greaterThan(scene.controller.view.yOf(scene.layout.rowTop(1))), reason: '앞 줄 아래');
      expect([pts[6], pts[7], pts[8], pts[9]], [closeTo(fc, .05), closeTo(gy, .05), closeTo(fc, .05), closeTo(y2 - LinkLook.tipGap, .05)]);
      final doors = [for (final d in await notesOf(scene, painter, '문')) nums(d)];
      expect(doors.any((d) => (d[0] - (fc - 2.2)).abs() < .06 && (d[1] - (top - .5)).abs() < .06), isTrue, reason: '구멍 위 윗변의 문: $doors');
      expect(await notesOf(scene, painter, '굴문'), isEmpty);
      expect(LineAudit.last!.hiddenPx, 0);
      // 끄면 그 전 길 — 구멍 높이의 가로가 앞 띠 뒤로.
      PaintPick.route = false;
      final (off, offPainter) = make(tile(), 2);
      addTearDown(off.dispose);
      expect((await paths(off, offPainter))['1→3']!.length, 8);
      expect(LineAudit.last!.hiddenPx, greaterThan(0));
    });

    test('위로 가는 선: 후대 줄 아래 틈을 따라 구멍 앞 9px까지 와서 구멍 높이로 든다', () async {
      final b = TileBuilder(level: 9, x: 0, chunk: 0);
      sq(b, 1, 1, t - 20 * m, t, '앞 나라');
      sq(b, 4, 0, t + .2 * m, t + .8 * m, '앞 띠');
      sq(b, 3, 0, t + 1 * m, t + 6 * m, '뒤 나라');
      b.item(LinkLayer.secLink, 201, 0, t, t + 1 * m, row2: 1, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst);
      final (scene, painter) = make(b.build(), 2);
      addTearDown(scene.dispose);
      final pts = (await paths(scene, painter))['1→3']!;
      final (_, y2) = await squareOf(scene, painter, '건국', 3);
      final pf = xOf(scene, t + 1 * m);
      expect(pts.length, 12, reason: '통로 → 아래 틈 → 구멍 앞 9 → 구멍: $pts');
      final gy = pts[5];
      final v = scene.controller.view;
      expect(gy, greaterThan(v.yOf(scene.layout.rowTop(0) + scene.layout.geo(0).height)), reason: '뒤 나라 줄 아래');
      expect(gy, lessThan(topOf(scene, 1)), reason: '앞 나라 줄 위');
      expect([pts[6], pts[8], pts[9]], [closeTo(pf - 9, .05), closeTo(pf - 9, .05), closeTo(y2, .05)]);
      expect(await notesOf(scene, painter, '굴문'), isEmpty);
      expect(LineAudit.last!.hiddenPx, 0);
    });
  });

  group('골목 층 표 · 합류 점(조사 결함 5 · 43)', () {
    test('같은 틈에 겹치는 가로 둘은 2.5px 다른 층 — 겹치지 않는다', () async {
      // 0번 줄 앞 나라 1(t에서 끝남) → 2번 줄 먼 뒤 나라 6, 1번 줄 둘째 나라 2(t − .5에서 끝남) → 2번 줄 가까운 뒤 나라 3. 2번 줄 앞쪽에 앞 띠 4.
      final b = TileBuilder(level: 9, x: 0, chunk: 0);
      sq(b, 1, 0, t - 20 * m, t, '앞 나라');
      sq(b, 2, 1, t - 20 * m, t - .5 * m, '둘째 나라');
      sq(b, 4, 2, t + .3 * m, t + 1 * m, '앞 띠');
      sq(b, 3, 2, t + 1.1 * m, t + 1.4 * m, '가까운 뒤 나라');
      sq(b, 6, 2, t + 1.5 * m, t + 6 * m, '먼 뒤 나라');
      b
        ..item(LinkLayer.secLink, 201, 0, t, t + 1.5 * m, row2: 2, ref: 1, b: 6, color: 0xabb3c9, a: lkQFirst | lkDown)
        ..item(LinkLayer.secLink, 202, 1, t - .5 * m, t + 1.1 * m, row2: 2, ref: 2, b: 3, color: 0x95aaa2, a: lkQFirst | lkDown);
      final (scene, painter) = make(b.build(), 3);
      addTearDown(scene.dispose);
      final p = await paths(scene, painter);
      final a = p['1→6']!, c = p['2→3']!;
      expect(a.length, 10, reason: '$a');
      expect(c.length, 10, reason: '$c');
      expect((a[5] - c[5]).abs(), closeTo(2.5, .01), reason: '틈 가로의 높이: ${a[5]} · ${c[5]}');
      expect(LineAudit.last!.hiddenPx, 0);
    });

    test('같은 구멍에 옆으로 둘째로 드는 선은 첫 선의 가로에 닿는 곳에서 멎고 제 색 점(지름 3) — 관문은 하나', () async {
      // 0번 줄 뒤 나라 3 · 1번 줄 앞 나라 1(t에서 끝남) · 2번 줄 앞 나라 2(t + .2에서 끝남) — 둘 다 위로 가는 hv.
      final b = TileBuilder(level: 9, x: 0, chunk: 0);
      sq(b, 3, 0, t + 1 * m, t + 6 * m, '뒤 나라');
      sq(b, 1, 1, t - 20 * m, t, '앞 나라');
      sq(b, 2, 2, t - 20 * m, t + .2 * m, '먼 앞 나라', color: 0x95aaa2);
      b
        ..item(LinkLayer.secLink, 201, 0, t, t + 1 * m, row2: 1, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst)
        ..item(LinkLayer.secLink, 202, 0, t + .2 * m, t + 1 * m, row2: 2, ref: 2, b: 3, color: 0x95aaa2, a: lkQFirst);
      final (scene, painter) = make(b.build(), 3);
      addTearDown(scene.dispose);
      final p = await paths(scene, painter);
      final (_, y2) = await squareOf(scene, painter, '건국', 3);
      final first = p['1→3']!, second = p['2→3']!;
      expect(first.length, 8, reason: '첫 선은 hv 그대로: $first');
      expect(second.length, 6, reason: '둘째 선은 가로 없이 첫 선의 가로에서 멎는다: $second');
      final xb = xOf(scene, t + .2 * m) + 9;
      expect([second[4], second[5]], [closeTo(xb, .05), closeTo(y2, .05)]);
      final dots = [for (final d in await notesOf(scene, painter, '합류점')) nums(d)];
      expect(dots, hasLength(1));
      expect([dots.single[0], dots.single[1]], [closeTo(xb, .05), closeTo(y2, .05)]);
      final pf = xOf(scene, t + 1 * m);
      final gates = [for (final d in await notesOf(scene, painter, '문')) nums(d)].where((d) => (d[0] - (pf - .5)).abs() < .06).toList();
      expect(gates, hasLength(1), reason: '구멍 앞 관문은 한 번');
      // 끄면 둘 다 가로까지(겹침).
      PaintPick.route = false;
      final (off, offPainter) = make(b.build(), 3);
      addTearDown(off.dispose);
      expect((await paths(off, offPainter))['2→3']!.length, 8);
      expect(await notesOf(off, offPainter, '합류점'), isEmpty);
    });

    test('같은 구멍에 위에서 둘째로 드는 선은 첫 선의 세로에 닿는 곳에서 멎는다 — 구멍 위 문은 하나', () async {
      final b = TileBuilder(level: 9, x: 0, chunk: 0);
      sq(b, 1, 0, t - 20 * m, t, '앞 나라');
      sq(b, 2, 1, t - 20 * m, t - .5 * m, '둘째 나라', color: 0x95aaa2);
      sq(b, 4, 2, t + .3 * m, t + .8 * m, '앞 띠');
      sq(b, 3, 2, t + 1 * m, t + 6 * m, '뒤 나라');
      b
        ..item(LinkLayer.secLink, 201, 0, t, t + 1 * m, row2: 2, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown)
        ..item(LinkLayer.secLink, 202, 1, t - .5 * m, t + 1 * m, row2: 2, ref: 2, b: 3, color: 0x95aaa2, a: lkQFirst | lkDown);
      final (scene, painter) = make(b.build(), 3);
      addTearDown(scene.dispose);
      final p = await paths(scene, painter);
      final (fc, _) = await squareOf(scene, painter, '건국', 3);
      final first = p['1→3']!, second = p['2→3']!;
      expect(first.length, 10, reason: '$first');
      final gy = first[5];
      expect(second.length, 10, reason: '$second');
      expect(second[5], closeTo(gy - 2.5, .01), reason: '둘째 선의 틈 가로는 한 층 위');
      expect([second[8], second[9]], [closeTo(fc, .05), closeTo(gy, .05)], reason: '첫 선의 꺾는 자리에서 멎는다');
      final dots = [for (final d in await notesOf(scene, painter, '합류점')) nums(d)];
      expect(dots, hasLength(1));
      final top = topOf(scene, 2);
      final doors = [for (final d in await notesOf(scene, painter, '문')) nums(d)].where((d) => (d[0] - (fc - 2.2)).abs() < .06 && (d[1] - (top - .5)).abs() < .06);
      expect(doors, hasLength(1), reason: '구멍 위 윗변의 문은 첫 선의 것 하나');
    });

    test('이음매 눈금과 같은 구멍으로 옆에서 드는 내림줄은 한 토막을 함께 쓰지 않는다 — 나중 것이 먼저 것에 닿는 곳에서 멎고 점 하나(동아시아 남송 · 원 → 명)', () async {
      // 0번 줄: 좁은 앞 나라 1(10px — 마름모가 꺼져 이음매 눈금) → 틈 50px 뒤 나라 2. 1번 줄: 아래 나라 3이 뒤 나라 시작 8px 앞에서 끝나 꼬리 마름모에서 올라와 든다.
      // 선은 통로 번호 차례로 세운다 — [seamFirst]면 이음매(0)가 먼저, 아니면 내림줄(0)이 먼저.
      Uint8List tile({bool seam = true, bool rise = true, bool seamFirst = true}) {
        final b = TileBuilder(level: 9, x: 0, chunk: 0);
        sq(b, 1, 0, t - .06 * m, t, '앞 나라');
        sq(b, 2, 0, t + .3 * m, t + 6 * m, '뒤 나라', color: 0x95aaa2);
        sq(b, 3, 1, t - 20 * m, t + .25 * m, '아래 나라', color: 0xa295aa);
        if (seam) b.item(LinkLayer.secLink, 201, 0, t, t + .3 * m, ref: 1, b: 2, color: 0xabb3c9, a: lkQFirst | lkSeam, c: seamFirst ? 0 : 10);
        if (rise) b.item(LinkLayer.secLink, 202, 0, t + .25 * m, t + .3 * m, row2: 1, ref: 3, b: 2, color: 0xa295aa, a: lkQFirst, c: seamFirst ? 10 : 0);
        return b.build();
      }

      // 내림줄 혼자: 꼬리 마름모 → 위로 → 구멍 높이 가로 → 구멍.
      final (alone, alonePainter) = make(tile(seam: false), 2);
      addTearDown(alone.dispose);
      final solo = (await paths(alone, alonePainter))['3→2']!;
      expect(solo.length, 6, reason: '내림줄 세 점: $solo');
      final (xd, y2) = (solo[2], solo[3]);
      // 이음매 눈금 혼자: 앞 나라 끝 − 3 ~ 뒤 나라 시작 + 3.
      final (lone, lonePainter) = make(tile(rise: false), 2);
      addTearDown(lone.dispose);
      final pf = xOf(lone, t + .3 * m);
      expect(nums((await notesOf(lone, lonePainter, '이음매눈금')).single.split(' ').last), [closeTo(xOf(lone, t) - 3, .06), closeTo(y2, .06), closeTo(pf + 3, .06)]);
      // 둘 다: 한 토막([꺾는 자리, 뒤 나라 시작])을 함께 쓰지 않고 합류 점 하나 — 먼저 선 것이 구멍으로 들고 나중 것이 꺾는 자리에서 멎는다.
      for (final seamFirst in [true, false]) {
        final (scene, painter) = make(tile(seamFirst: seamFirst), 2);
        addTearDown(scene.dispose);
        final p = await paths(scene, painter);
        final tick = nums((await notesOf(scene, painter, '이음매눈금')).single.split(' ')[1]);
        final rise = p['3→2']!;
        final dots = [for (final d in await notesOf(scene, painter, '합류점')) nums(d)];
        expect(dots, hasLength(1), reason: '점 하나($seamFirst): $dots');
        expect([dots.single[0], dots.single[1]], [closeTo(xd, .05), closeTo(y2, .05)], reason: '내림줄이 꺾는 자리');
        if (seamFirst) {
          expect([rise.length, rise[2], rise[3]], [4, closeTo(xd, .05), closeTo(y2, .05)], reason: '내림줄이 이음매에 닿아 멎는다: $rise');
          expect(tick[2], closeTo(pf + 3, .06), reason: '이음매는 그대로');
        } else {
          expect(rise, solo, reason: '내림줄은 그대로');
          expect(tick[2], closeTo(xd, .06), reason: '이음매가 내림줄의 꺾는 자리에서 멎는다: $tick');
        }
        final pfDoors = [for (final d in await notesOf(scene, painter, '문')) nums(d)].where((d) => (d[0] - (pf - .5)).abs() < .06).toList();
        expect(pfDoors, hasLength(1), reason: '뒤 나라 앞 문은 먼저 든 선의 것 하나($seamFirst): $pfDoors');
      }
      // 끄면 이음매 눈금이 없어 이 장면은 그 전 그림.
      PaintPick.route = false;
      final (off, offPainter) = make(tile(), 2);
      addTearDown(off.dispose);
      await paths(off, offPainter);
      expect(await notesOf(off, offPainter, '합류점'), isEmpty);
    });
  });

  test('조감: 같은 선대의 둘째 내림줄은 3px 안쪽(조사 결함 13) — 끄면 같은 x에 포개진다', () async {
    // 앞 나라(1 · 0번 줄) → 뒤 나라 둘(1번 · 2번 줄) — 둘 다 앞 나라 끝 바로 뒤에서 시작해 내림줄(조감 · 끝 − 7)로 간다.
    Uint8List tile() {
      final b = TileBuilder(level: 9, x: 0, chunk: 0);
      sq(b, 1, 0, t - 20 * m, t, '앞 나라');
      sq(b, 3, 1, t + .02 * m, t + 6 * m, '뒤 나라');
      sq(b, 6, 2, t + .03 * m, t + 6 * m, '먼 뒤 나라');
      b
        ..item(LinkLayer.secLink, 201, 0, t, t + .02 * m, row2: 1, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown)
        ..item(LinkLayer.secLink, 202, 0, t, t + .03 * m, row2: 2, ref: 1, b: 6, color: 0xabb3c9, a: 3 | lkQFirst | lkDown, c: 10);
      return b.build();
    }

    final (scene, painter) = make(tile(), 3, bird: true);
    addTearDown(scene.dispose);
    final p = await paths(scene, painter);
    final qe = xOf(scene, t);
    expect(p['1→3']![0], closeTo(qe - BirdLook.stationX, .05), reason: '${p['1→3']}');
    expect(p['1→6']![0], closeTo(qe - BirdLook.stationX - 3, .05), reason: '${p['1→6']}');
    PaintPick.route = false;
    final (off, offPainter) = make(tile(), 3, bird: true);
    addTearDown(off.dispose);
    final o = await paths(off, offPainter);
    expect(o['1→6']![0], closeTo(qe - BirdLook.stationX, .05));
  });

  test('풀린 그릇의 열쇠표는 승계선의 세로 획을 비킨다 — 실이 닿는 곳째 획 뒤 + 4로(조사 결함 11)', () async {
    // 0번 줄 앞 나라(t에서 끝남) → 2번 줄 뒤 나라. 1번 줄 사이 나라(그릇의 구성 띠 · 화면 왼쪽 밖에서 시작)에 열쇠표 — 통로(끝 + 9)가 그 열쇠표 자리를 지난다.
    Uint8List tile() {
      final b = TileBuilder(level: 9, x: 0, chunk: 0);
      sq(b, 1, 0, t - 20 * m, t, '앞 나라');
      sq(b, 5, 1, t - .07 * m, t + 6 * m, '사이 나라');
      sq(b, 3, 2, t + 1 * m, t + 6 * m, '뒤 나라');
      b
        ..item(ScopeMarks.secKey, 601, 1, t, t + 6 * m, ref: 5, name: '원삼국 시대', color: 0xa27e76, text2: 's-three')
        ..item(LinkLayer.secLink, 201, 0, t, t + 1 * m, row2: 2, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown);
      return b.build();
    }

    final (scene, painter) = make(tile(), 3);
    addTearDown(scene.dispose);
    final xm = (await paths(scene, painter))['1→3']![2];
    final k = nums((await notesOf(scene, painter, '열쇠표')).single.split(' ').last);
    expect(k[0], greaterThan(xm + 1 + 4), reason: '열쇠표 ${k[0]} ~ ${k[0] + k[2]} · 통로 $xm');
    // 0.1.1 떼어서 살림(감독 고름 2026-10-26): route를 끈 기본(옛 길)에서도 그 길이 그은 세로 획을 비킨다 — 끄는 것은 스위치 mend.
    PaintPick.route = false;
    final (off, offPainter) = make(tile(), 3);
    addTearDown(off.dispose);
    final xo = (await paths(off, offPainter))['1→3']![2];
    final ko = nums((await notesOf(off, offPainter, '열쇠표')).single.split(' ').last);
    expect(ko[0], greaterThan(xo + 1 + 4), reason: 'route 끔(옛 길) — 열쇠표 ${ko[0]} ~ ${ko[0] + ko[2]} · 통로 $xo');
    PaintPick.mend = false;
    final (raw, rawPainter) = make(tile(), 3);
    addTearDown(raw.dispose);
    final kr = nums((await notesOf(raw, rawPainter, '열쇠표')).single.split(' ').last);
    expect(kr[0] < xo && kr[0] + kr[2] > xo, isTrue, reason: 'mend를 끄면 열쇠표가 통로를 덮는다: ${kr[0]} ~ ${kr[0] + kr[2]} · $xo');
  });

  // 0.1.1 합침 검토: 획 x가 소수이고 '획 뒤 + 4'가 반올림에서 내림으로 떨어지면 민 실이 같은 획에 다시 걸려 고리가 나아가지 못했다 — 판 3.1 동아시아에서
  // '○ 원삼국 시대' 다섯 · '○ 삼한' 둘이 사라지고 하나는 구멍만으로 섰다. 같은 띠 같은 해에 매단 둘째 열쇠표는 앞 열쇠표 뒤로 밀린 채 실만 획 앞에 걸리는데,
  // 그것을 '획 뒤 + 4 + 3'으로 되돌리면 앞 열쇠표에 포개졌다(마한 · 변한). 획 x를 1px 안에서 옮겨 가며 둘 다 이름째 획 뒤에 · 겹치지 않게 서는지 본다.
  test('획 x가 소수여도 열쇠표는 이름째 획 뒤 + 4에 선다 — 같은 획에 다시 걸리지 않고, 둘째 열쇠표는 앞 열쇠표 뒤에 그대로(포개지지 않음)', () async {
    const ppm = 168 / m;
    for (final f in const [0.0, .1, .2, .3, .4, .5, .6, .7, .8, .9]) {
      final q = t + f / ppm;
      final b = TileBuilder(level: 9, x: 0, chunk: 0);
      sq(b, 1, 0, q - 20 * m, q, '앞 나라');
      sq(b, 5, 1, q - .07 * m, q + 6 * m, '사이 나라');
      sq(b, 3, 2, q + 1 * m, q + 6 * m, '뒤 나라');
      b
        ..item(ScopeMarks.secKey, 600, 1, q, q + 6 * m, ref: 5, name: '삼한', color: 0xa27e76, text2: 's-han')
        ..item(ScopeMarks.secKey, 601, 1, q, q + 6 * m, ref: 5, name: '원삼국 시대', color: 0xa27e76, text2: 's-three')
        ..item(LinkLayer.secLink, 201, 0, q, q + 1 * m, row2: 2, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown);
      final (scene, painter) = make(b.build(), 3);
      addTearDown(scene.dispose);
      final xm = (await paths(scene, painter))['1→3']![2];
      final keys = await notesOf(scene, painter, '열쇠표');
      expect(keys, hasLength(2), reason: '획 x $xm(밀기 $f px) — 열쇠표가 빠지면 안 된다: $keys');
      final first = nums(keys.firstWhere((k) => k.startsWith('삼한 ')).split(' ').last);
      final second = nums(keys.firstWhere((k) => k.startsWith('원삼국 시대 ')).split(' ').last);
      for (final k in [first, second]) {
        expect(k[0], greaterThanOrEqualTo(xm + 1 + FolderLook.keyGap + 3), reason: '획 x $xm(밀기 $f px) · 열쇠표 ${k[0]}');
      }
      expect(second[0], greaterThanOrEqualTo(first[0] + first[2] + FolderLook.keyGap), reason: '획 x $xm(밀기 $f px) — 둘째가 첫째에 포개짐: $keys');
      for (final name in ['삼한', '원삼국 시대']) {
        expect(painter.debugLabels.any((l) => l.kind == 'key' && l.text == name), isTrue, reason: '획 x $xm(밀기 $f px) — $name 구멍만이 아니라 이름째');
      }
    }
  });

  test('꼬리 줄기를 위로 가는 선이 함께 쓰려면 그 줄기 x에서 탭 검사를 본다(이어 주는 선 미룸 4)', () async {
    // 앞 나라(1 · 1번 줄 · t에서 끝남)에 하연 총관부처럼 맞붙은 이웃 띠(7)가 있어 (가-0)이 꼬리 내림을 고른다. 아래로 가는 선(→ 3 · 2번 줄)이 줄기를 먼저 세우고,
    // 같은 종류의 위로 가는 선(→ 9 · 0번 줄)은 그 줄기 x에 연합 겹 탭이 설 수 있으면 함께 쓰지 않는다.
    final ppm = 1680 / (10 * m);
    Uint8List tile({required bool tab}) {
      final b = TileBuilder(level: 9, x: 0, chunk: 0);
      sq(b, 1, 1, t - 2 * m, t, '앞 나라');
      sq(b, 7, 1, t, t + 2 * m, '이웃 나라');
      sq(b, 3, 2, t + .5 * m, t + 6 * m, '아래 나라');
      sq(b, 9, 0, t + .6 * m, t + 6 * m, '위 나라');
      b
        ..item(LinkLayer.secLink, 202, 1, t, t + .5 * m, row2: 2, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown)
        ..item(LinkLayer.secLink, 201, 0, t, t + .6 * m, row2: 1, ref: 1, b: 9, color: 0xabb3c9, a: lkQFirst, c: 10);
      // 앞 나라 끝 쪽 꼬리 마름모 위에 설 연합 겹 탭(구역 47 모습 7 — 가담 시작 = 띠 끝 − 40px).
      if (tab) b.item(BandLayer.sectionHostTab, 301, 1, t - 40 / ppm, t, ref: 1, name: '동맹', color: 0x8899aa, a: BandLayer.coalLook, d: 9, text2: 'ally');
      return b.build();
    }

    final (scene, painter) = make(tile(tab: false), 3);
    addTearDown(scene.dispose);
    final p = await paths(scene, painter);
    final (ec, _) = await squareOf(scene, painter, '멸망', 1);
    expect(p['1→3']![0], closeTo(ec, .05), reason: '아래로 가는 선이 꼬리 줄기를 세운다: ${p['1→3']}');
    expect(p['1→9']![2], closeTo(ec, .05), reason: '탭이 없으면 위로 가는 선도 그 줄기(세로 획 x): ${p['1→9']}');
    final (tabbed, tabbedPainter) = make(tile(tab: true), 3);
    addTearDown(tabbed.dispose);
    final q = await paths(tabbed, tabbedPainter);
    expect(q['1→3']![0], closeTo(ec, .05));
    expect(q['1→9']![2], isNot(closeTo(ec, .05)), reason: '탭 밑 줄기를 함께 쓰지 않는다: ${q['1→9']}');
  });
}

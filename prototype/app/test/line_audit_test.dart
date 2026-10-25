import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/color_mix.dart' show over, withAlpha;
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/links.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 선 감사(이어 주는 선 걸음 1 — lib/scene/paint/links.dart `LinkLayer.auditLines` · `LineAudit` · 명세 04의 8-6)의 검사.
// 감사는 그림을 바꾸지 않고 센다: 두 끝 띠가 아닌 다른 띠 몸통(윗변 ~ BandLayer.bodyBottomOf) 뒤로 숨은 px · 보이는 px 0인 선 · 빠진 선 · S길.
// 스위치 route(paint_pick.dart)는 걸음 2부터 새 길을 켠다. 걸음 5부터는 굴 문(명세 04 3-9)이 다른 띠 몸통 뒤의 몫을 '표시 있음'으로 바꾼다 —
// 끄면 그 전 길 · 그 전 수(숨은 px)다.

const m = 1000000.0; // 백만 분

/// 구역 21(승계선)의 a 비트.
const lkDown = 1 << 4, lkQFirst = 1 << 5;

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

SceneLayout layout() => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
  'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0), row(1), row(2)]}],
});

/// 줄 0의 앞 나라(1 · 13에서 끝남) → 줄 2의 뒤 나라(3 · 16에서 시작) 직접 승계 하나. 사이 줄 1에 가운데 나라(2 · 12 ~ 18)가 있어
/// 앞 나라 끝 + 9의 세로 통로가 그 띠 몸통 뒤로 지난다(조사 결함 7 '사이 줄의 띠 뒤로 지나는 다른 줄 선'과 같은 꼴).
Uint8List crossTile() => (TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(1, 0, -7 * m, 13 * m, '앞 나라')
      ..band(2, 1, 12 * m, 18 * m, '가운데 나라')
      ..band(3, 2, 16 * m, 25 * m, '뒤 나라')
      ..item(LinkLayer.secSquare, 101, 0, -7 * m, 13 * m, ref: 1, name: '앞 나라', color: 0xabb3c9)
      ..item(LinkLayer.secSquare, 102, 1, 12 * m, 18 * m, ref: 2, name: '가운데 나라', color: 0xc8b193)
      ..item(LinkLayer.secSquare, 103, 2, 16 * m, 25 * m, ref: 3, name: '뒤 나라', color: 0xa295aa)
      ..item(LinkLayer.secLink, 201, 0, 13 * m, 16 * m, row2: 2, ref: 1, b: 3, color: 0xabb3c9, a: lkDown | lkQFirst))
    .build();

(TimelineScene, TimelinePainter) make(Uint8List bytes, {bool debug = true}) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m);
  final shape = layout();
  controller.setContentHeight(shape.totalHeight);
  final scene = TimelineScene(
    controller: controller,
    layout: shape,
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  controller.showRange(10 * m, 20 * m);
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = debug);
}

/// 타일이 다 오도록 여러 번 그린다(links_test의 notesOf와 같은 길).
Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }
}

List<String> noted(TimelinePainter painter, String kind) => [for (final v in painter.debugSink.notes[kind] ?? const <Object>[]) '$v'];

/// '1052.3,636.0,5.0,0.0' 같은 기록을 숫자로(띠 번호 · 낱말은 숫자만 남긴다).
List<double> nums(String text) => [for (final s in text.split(RegExp('[ ,~]'))) double.tryParse(s) ?? double.nan].where((v) => !v.isNaN).toList();

/// 한 장면을 그림으로 떠 바이트로(스위치를 켜고 끈 그림을 견줄 때).
Future<Uint8List> pixels(TimelinePainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1920, 1080);
  final data = await image.toByteData();
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    PaintPick.reset();
    LineAudit.capture = false;
    LineAudit.last = null;
  });

  const screen = Rect.fromLTRB(0, 0, 1000, 1000);
  // 띠 1(앞 · 줄 0) · 2(가운데 · 줄 1) · 3(뒤 · 줄 2)의 몸통 상자.
  const q = AuditBody(1, 0, Rect.fromLTRB(0, 0, 120, 50));
  const mid = AuditBody(2, 1, Rect.fromLTRB(80, 100, 200, 150));
  const p = AuditBody(3, 2, Rect.fromLTRB(90, 200, 300, 250));
  // 앞 나라 마름모(110, 25) → 통로 x 130 → 뒤 나라 구멍 앞(140, 225): 통로가 가운데 나라 몸통(100 ~ 150)을 지난다.
  const hv = [Offset(110, 25), Offset(130, 25), Offset(130, 225), Offset(140, 225)];

  group('선 감사의 셈(auditLines)', () {
    test('사이 띠 몸통 뒤로 지나는 몫만 숨은 px — 두 끝 띠 뒤는 세지 않는다', () {
      final r = LinkLayer.auditLines([const AuditLine(LineAuditKind.succession, 1, 3, hv)], [q, mid, p], screen);
      expect(r.lines, 1);
      expect(r.hiddenPx, closeTo(50, 1e-9), reason: '가운데 나라 몸통 100 ~ 150');
      expect(r.markedPx, 0);
      expect(r.invisible, 0, reason: '보이는 px = 230 − (앞 10 + 가운데 50 + 뒤 25 + 뒤 10) = 135');
      expect(r.detail.single, '승계 1→3 숨은 50px · 띠 2 50', reason: '이름을 모르면 번호만');
      final named = LinkLayer.auditLines([const AuditLine(LineAuditKind.succession, 1, 3, hv)], [q, mid, p], screen, nameOf: (b) => b == 2 ? '가운데' : '');
      expect(named.detail.single, '승계 1→3 숨은 50px · 띠 가운데(2) 50');
      expect(r.kinds[LineAuditKind.succession], (1, 50.0, 0));
    });

    test('화면 밖은 세지 않는다', () {
      final r = LinkLayer.auditLines([const AuditLine(LineAuditKind.succession, 1, 3, hv)], [q, mid, p], const Rect.fromLTRB(0, 120, 1000, 1000));
      expect(r.hiddenPx, closeTo(30, 1e-9), reason: '화면 윗변 120 ~ 가운데 나라 아랫변 150');
    });

    test('겹친 두 띠 뒤의 같은 구간은 한 번만', () {
      const other = AuditBody(4, 1, Rect.fromLTRB(125, 120, 260, 170));
      final r = LinkLayer.auditLines([const AuditLine(LineAuditKind.succession, 1, 3, hv)], [q, mid, other, p], screen);
      expect(r.hiddenPx, closeTo(70, 1e-9), reason: '100 ~ 150 ∪ 120 ~ 170 = 100 ~ 170');
    });

    test('굴 문을 둔 띠 뒤의 몫은 표시 있음으로 따로 센다', () {
      final r = LinkLayer.auditLines([const AuditLine(LineAuditKind.succession, 1, 3, hv, doors: {2})], [q, mid, p], screen);
      expect(r.hiddenPx, 0);
      expect(r.markedPx, closeTo(50, 1e-9));
      expect(r.detail, isEmpty);
    });

    test('다른 띠 몸통 안에서만 지나는 선은 안 보이는 선 · 6점 길은 S길 · 빠진 선은 그대로 넘긴다', () {
      final r = LinkLayer.auditLines(
        [
          const AuditLine(LineAuditKind.part, 1, 3, [Offset(100, 110), Offset(100, 140)]),
          const AuditLine(LineAuditKind.succession, 1, 3, [Offset(10, 25), Offset(40, 25), Offset(40, 60), Offset(5, 60), Offset(5, 225), Offset(95, 225)]),
          const AuditLine(LineAuditKind.move, 1, 3, [Offset(100, 120), Offset(150, 120)], topPx: 4),
        ],
        [q, mid, p], screen, missed: ['7→8 줄 0→2'],
      );
      expect(r.invisible, 1, reason: '띠 위 조각(topPx)이 있으면 보인다');
      expect(r.kinds[LineAuditKind.part]!.$3, 1);
      expect(r.backPaths, 1);
      expect(r.missing, 1);
      expect(r.missed.single, '7→8 줄 0→2');
      expect(r.summary, startsWith('선 3 · 숨은 80px · 표시 0px · 안 보임 1 · 빠짐 1 · S길 1'));
      expect(r.toJson()['hiddenPx'], 80.0);
    });
  });

  group('선 감사 — 그림판 장면', () {
    test('사이 줄 띠 뒤로 지나는 통로: 스위치 route를 끄면(그 전 길) 숨은 px = 그 띠 몸통의 키(윗변 ~ 몸통 아랫변)', () async {
      PaintPick.route = false;
      final (scene, painter) = make(crossTile());
      addTearDown(scene.dispose);
      await settle(scene, painter);
      final (top, bottom) = bodyOf(scene, painter);
      expect(bottom - top, greaterThan(20));
      final summary = noted(painter, '선감사').single;
      expect(summary, startsWith('선 1 · 숨은 ${(bottom - top).round()}px · 표시 0px · 안 보임 0 · 빠짐 0 · S길 0'));
      expect(noted(painter, '선감사-선').single, '승계 앞 나라(1)→뒤 나라(3) 숨은 ${(bottom - top).round()}px · 띠 가운데 나라(2) ${(bottom - top).round()}');
      expect(LineAudit.last?.hiddenPx, closeTo(bottom - top, 1e-6));
      expect(noted(painter, '굴문'), isEmpty, reason: '끄면 굴 문이 없다');
    });

    test('검사 기록을 끈 실제 앱은 찍기(capture)를 켤 때만 센다', () async {
      final (scene, painter) = make(crossTile(), debug: false);
      addTearDown(scene.dispose);
      await settle(scene, painter);
      expect(LineAudit.last, isNull, reason: '기록도 찍기도 꺼져 있으면 감사하지 않는다');
      LineAudit.capture = true;
      await settle(scene, painter);
      expect(LineAudit.last?.lines, 1);
      expect(LineAudit.last!.hiddenPx, 0, reason: '굴 문이 선 띠 뒤의 몫은 표시 있음');
      expect(LineAudit.last!.markedPx, greaterThan(20));
    });
  });

  group('굴 문(명세 04 3-9 · 이어 주는 선 걸음 5) — 다른 띠 뒤로 지나는 몫의 들고 나는 테마다', () {
    test('세로 획: 사이 줄 띠의 윗변 · 몸통 아랫변에 문(문 높이 4.4 × 테를 따라 3) 하나씩과 띠 안쪽 2px까지의 토막 — 숨은 px 0 · 표시 있음', () async {
      final (scene, painter) = make(crossTile());
      addTearDown(scene.dispose);
      await settle(scene, painter);
      final (top, bottom) = bodyOf(scene, painter);
      expect(noted(painter, '선감사').single, startsWith('선 1 · 숨은 0px · 표시 ${(bottom - top).round()}px · 안 보임 0 · 빠짐 0 · S길 0'));
      expect(noted(painter, '선감사-선'), isEmpty);
      final tunnel = noted(painter, '굴문').single;
      expect(tunnel, startsWith('2 세로 '), reason: '두 끝 띠(1 · 3)가 아닌 가운데 나라(2)에만');
      final x = nums(tunnel)[1];
      final line = nums(noted(painter, '선').single.split(' 짙기').first);
      expect(x, closeTo(line[2], 1e-6), reason: '세로 통로의 x');
      // 문(왼쪽 위 · 폭 · 높이): 윗변 테 px [top, top + 1]을 덮고 안팎 1px씩 — [top − 1, top + 2]. 아랫변은 [bottom − 2, bottom + 1].
      final doors = [for (final d in noted(painter, '문')) nums(d)];
      bool hasDoor(double y) => doors.any((d) => (d[0] - (x - 2.2)).abs() < .06 && (d[1] - y).abs() < .06 && (d[2] - 4.4).abs() < .06 && (d[3] - 3).abs() < .06);
      expect(hasDoor(top - 1), isTrue, reason: '윗변의 문: $doors');
      expect(hasDoor(bottom - 2), isTrue, reason: '몸통 아랫변의 문: $doors');
      // 토막: 문 바깥에서 문 안쪽 + 2까지(윗변 top − 1 ~ top + 4 · 아랫변 bottom − 4 ~ bottom + 1) — 선의 색 그대로.
      final segs = [for (final s in noted(painter, '조각')) nums(s)];
      int segAt(double a, double b) => segs.indexWhere((s) => (s[0] - x).abs() < .06 && (s[2] - x).abs() < .06 && (s[1] - a).abs() < .06 && (s[3] - b).abs() < .06);
      final upper = segAt(top - 1, top + 4), lower = segAt(bottom - 4, bottom + 1);
      expect(upper, isNot(-1), reason: '윗변 토막: $segs');
      expect(lower, isNot(-1), reason: '아랫변 토막: $segs');
      final colors = noted(painter, '조각색'), lineColor = noted(painter, '선색').single;
      expect([colors[upper], colors[lower]], [lineColor, lineColor], reason: '토막은 선의 색');
    });

    test('스위치 route를 끈 그림과는 굴 문 자리(문 · 토막의 상자)만 다르다 — 길은 그대로', () async {
      final (scene, painter) = make(crossTile());
      addTearDown(scene.dispose);
      await settle(scene, painter);
      final on = await pixels(painter);
      final linesOn = noted(painter, '선');
      final x = nums(noted(painter, '굴문').single)[1];
      final (top, bottom) = bodyOf(scene, painter);
      PaintPick.route = false;
      await settle(scene, painter);
      final off = await pixels(painter);
      expect(noted(painter, '선'), linesOn, reason: '띠 뒤 선의 길은 같다');
      var differ = 0;
      for (int i = 0; i < on.length; i += 4) {
        if (on[i] == off[i] && on[i + 1] == off[i + 1] && on[i + 2] == off[i + 2] && on[i + 3] == off[i + 3]) continue;
        differ++;
        final px = (i ~/ 4) % 1920, py = (i ~/ 4) ~/ 1920;
        final nearX = px >= x - 3.5 && px <= x + 3.5;
        final nearY = (py >= top - 2 && py <= top + 5) || (py >= bottom - 5 && py <= bottom + 2);
        expect(nearX && nearY, isTrue, reason: '굴 문 밖의 픽셀이 다름: ($px, $py) · 굴 문 x ${x.toStringAsFixed(1)} · 몸통 ${top.toStringAsFixed(1)} ~ ${bottom.toStringAsFixed(1)}');
      }
      expect(differ, greaterThan(0));
    });

    test('가로 획: 같은 줄에서 사이 띠를 지나는 선은 그 띠의 왼 · 오른 테에 문 — 두 끝 띠에는 두지 않는다', () async {
      // 걸음 6부터 꼬리 마름모 · 구멍이 보이는 쌍은 같은 줄 ⊓(명세 04 3-4)로 사이 띠를 줄 위 틈으로 넘는다 — 곧은 가로 획이 남는 것은 마름모가 꺼진 좁은 선대(30px 미만)뿐.
      final (scene, painter) = make(rowTile(frontFrom: 12.88 * m));
      addTearDown(scene.dispose);
      await settle(scene, painter);
      final tunnels = noted(painter, '굴문');
      expect(tunnels.length, 1, reason: '$tunnels');
      expect(tunnels.single, startsWith('5 가로 '));
      final y = nums(tunnels.single)[1];
      final v = scene.controller.view;
      final l = v.xOf(14 * m), r = v.xOf(16 * m);
      final doors = [for (final d in noted(painter, '문')) nums(d)];
      bool hasDoor(double x) => doors.any((d) => (d[0] - x).abs() < .06 && (d[1] - (y - 2.2)).abs() < .06 && (d[2] - 3).abs() < .06 && (d[3] - 4.4).abs() < .06);
      expect(hasDoor(l - 1), isTrue, reason: '왼 테 [l, l + 1]의 문: $doors');
      expect(hasDoor(r - 2), isTrue, reason: '오른 테 [r − 1, r]의 문: $doors');
      expect(noted(painter, '선감사').single, contains('숨은 0px'));
      expect(noted(painter, '같은줄위'), isEmpty, reason: '마름모가 꺼지면 ⊓를 세우지 않는다');
    });

    test('같은 줄 ⊓(걸음 6): 마름모 · 구멍이 보이면 사이 띠를 줄 위 틈으로 넘는다 — 굴 문 없이 숨은 px 0 · 표시 0 · 끄면 그 전 길(사이 띠 뒤 몸통 폭만큼 숨음)', () async {
      final (scene, painter) = make(rowTile());
      addTearDown(scene.dispose);
      await settle(scene, painter);
      expect(noted(painter, '같은줄위').single, startsWith('4→6 '));
      expect(noted(painter, '굴문'), isEmpty);
      expect(noted(painter, '선감사').single, startsWith('선 1 · 숨은 0px · 표시 0px · 안 보임 0 · 빠짐 0 · S길 0'));
      PaintPick.route = false;
      await settle(scene, painter);
      final v = scene.controller.view;
      expect(LineAudit.last!.hiddenPx, closeTo(v.xOf(16 * m) - v.xOf(14 * m), 1e-6), reason: '사이 나라 몸통 폭만큼 그 뒤로 숨는다');
    });

    // 4단계 마지막 합치기 검토 지적: 감독 결정 '맨 아래 한 번 긋고 위에 얹기'로 흐린 띠 칠도 그 자리 바탕과 섞은 불투명 종이라 뒤가 비치지 않는다 —
    // 예전처럼 흐린 띠를 건너뛰면 고른 띠의 짙은 선이 다른 줄의 흐린 띠 뒤에서 표시 없이 끊긴다. 흐린 띠에도 같은 굴 문을 둔다.
    test('흐린 띠(고르기로 밝기 < 1)에도 둔다 — 흐린 띠 칠도 불투명 종이라 뒤가 비치지 않는다', () async {
      final (scene, painter) = make(crossTile());
      addTearDown(scene.dispose);
      await settle(scene, painter);
      final plain = noted(painter, '굴문');
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(const em.Look(band: 3, row: 2));
      painter.debugSink.notes.clear();
      await settle(scene, painter);
      final dim = noted(painter, '굴문');
      expect(dim, isNotEmpty, reason: '가운데 나라는 다른 줄이라 .58로 흐리지만 칠은 불투명 종이 — 고른 띠로 가는 선에 굴 문');
      expect(dim, plain, reason: '흐리기 전과 같은 자리 · 같은 테');
    });

    test('1배 후보 스위치 cross: 문 대신 가려진 몫 전체를 띠 위에 옅은 토막(짙기 .75 — 종이 테와 미리 섞은 불투명 색)과 양쪽 1px 종이 테로', () async {
      PaintPick.cross = true;
      final (scene, painter) = make(crossTile());
      addTearDown(scene.dispose);
      await settle(scene, painter);
      final (top, bottom) = bodyOf(scene, painter);
      final tunnel = noted(painter, '굴문').single;
      expect(tunnel, endsWith(' 건넘'));
      final x = nums(tunnel)[1];
      final doors = [for (final d in noted(painter, '문')) nums(d)];
      // 직접 승계 굵기 1.6 → 종이 테 폭 1.6 + 2 = 3.6, 높이는 몸통 전체.
      expect(doors.any((d) => (d[0] - (x - 1.8)).abs() < .06 && (d[1] - top).abs() < .06 && (d[2] - 3.6).abs() < .06 && (d[3] - (bottom - top)).abs() < .06), isTrue, reason: '$doors');
      final seg = noted(painter, '조각').firstWhere((s) => (nums(s)[0] - x).abs() < .06 && (nums(s)[1] - top).abs() < .06);
      expect(nums(seg)[3], closeTo(bottom, .06));
      // 감독 결정 '맨 아래 한 번 긋고 위에 얹기'(4단계 마지막 합치기): 종이 테가 불투명(짙기 1)이면 옅은 획(.75)은 그 종이와 미리 섞은 불투명 색 —
      // 획은 종이 테 안에만 서므로 보이는 색은 짙기 .75로 종이 위에 얹은 것과 같다.
      expect(seg, endsWith('짙기 1.000'));
      final lines = noted(painter, '선'), lineColors = noted(painter, '선색');
      final li = lines.indexWhere((l) {
        final n = nums(l);
        for (int i = 0; i + 1 < n.length - 1; i += 2) {
          if ((n[i] - x).abs() < .06) return true;
        }
        return false;
      });
      expect(li, greaterThanOrEqualTo(0), reason: '$lines');
      final raw = int.parse(lineColors[li], radix: 16);
      final segColor = int.parse(noted(painter, '조각색')[noted(painter, '조각').indexOf(seg)], radix: 16);
      expect(segColor, over(withAlpha(0xff000000 | raw, .75), Look.paper) & 0xffffff, reason: '선색 ${lineColors[li]}');
      expect(LineAudit.last!.hiddenPx, 0);
      expect(LineAudit.last!.markedPx, closeTo(bottom - top, 1e-6));
    });

    test("흐린 선의 굴 문(감독 결정 '맨 아래 한 번 긋고 위에 얹기' — 4단계 마지막 합치기): 몸통 밖으로 나온 1px만 그 자리 바탕과 미리 섞은 불투명 종이 · 몸통 위는 흐림 그대로", () async {
      final (scene, painter) = make(crossTile());
      addTearDown(scene.dispose);
      await settle(scene, painter);
      expect(noted(painter, '문종이'), isEmpty, reason: '짙기 1이면 나누지 않는다(예전과 바이트 같음)');
      em.Emphasis.of(scene)
        ..reduceMotion = true
        ..set(const em.Look(band: 2));
      painter.debugSink.notes.clear();
      await settle(scene, painter);
      final (top, bottom) = bodyOf(scene, painter);
      final alpha = painter.links.linkAlpha(1, 3);
      expect(alpha, lessThan(1), reason: '가운데 나라를 고르면 앞 나라 → 뒤 나라 선은 흐림');
      expect(noted(painter, '굴문'), hasLength(1), reason: '고른 띠는 흐리지 않아 굴 문을 둔다');
      final papers = noted(painter, '문종이');
      final want = (over(withAlpha(Look.paper, alpha), Look.ground) & 0xffffff).toRadixString(16).padLeft(6, '0');
      List<double> box(String s) => nums(s.split(' ').first);
      // 윗변 문 [top − 1, top + 2]의 몸통 밖 [top − 1, top] · 아랫변 문 [bottom − 2, bottom + 1]의 몸통 밖 [bottom, bottom + 1].
      expect(papers.any((s) => (box(s)[1] - (top - 1)).abs() < .06 && (box(s)[3] - 1).abs() < .06 && s.endsWith(want)), isTrue, reason: '$papers · $want');
      expect(papers.any((s) => (box(s)[1] - bottom).abs() < .06 && (box(s)[3] - 1).abs() < .06 && s.endsWith(want)), isTrue, reason: '$papers · $want');
      expect(papers.where((s) => s.endsWith('반투명')), isEmpty);
      expect(papers.every((s) => box(s)[1] + box(s)[3] <= top + .06 || box(s)[1] >= bottom - .06), isTrue, reason: '가운데 나라 몸통 위 몫은 나누지 않는다: $papers');
    });
  });
}

/// 줄 1의 가운데 나라(2) 몸통의 윗변 · 아랫변(배치 px — 선 감사의 몸통과 같은 셈).
(double, double) bodyOf(TimelineScene scene, TimelinePainter painter) {
  final v = scene.controller.view, shape = scene.layout, geo = shape.geo(1);
  return (v.yOf(shape.rowTop(1) + geo.bandTop), v.yOf(shape.rowTop(1) + painter.bands.bodyBottomOf(shape, 1, 2)));
}

/// 줄 1의 앞 나라(4 · 13에서 끝남) → 같은 줄의 뒤 나라(6 · 17에서 시작) 직접 승계(이음매 아님). 사이에 다른 나라(5 · 14 ~ 16)가 끼어
/// 가로 획(마름모 → 구멍)이 그 띠 몸통 뒤로 지난다(조사 결함 '같은 줄 사이 띠' — 등불 왕국 → 하연 부흥국 사이의 하연 총관부와 같은 꼴).
/// [frontFrom]: 앞 나라의 시작(좁히면 꼬리 마름모가 꺼진다 — 30px 미만).
Uint8List rowTile({double frontFrom = -7 * m}) => (TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(4, 1, frontFrom, 13 * m, '앞 나라')
      ..band(5, 1, 14 * m, 16 * m, '사이 나라')
      ..band(6, 1, 17 * m, 25 * m, '뒤 나라')
      ..item(LinkLayer.secSquare, 104, 1, frontFrom, 13 * m, ref: 4, name: '앞 나라', color: 0xabb3c9)
      ..item(LinkLayer.secSquare, 105, 1, 14 * m, 16 * m, ref: 5, name: '사이 나라', color: 0xc8b193)
      ..item(LinkLayer.secSquare, 106, 1, 17 * m, 25 * m, ref: 6, name: '뒤 나라', color: 0xa295aa)
      ..item(LinkLayer.secLink, 201, 1, 13 * m, 17 * m, row2: 1, ref: 4, b: 6, color: 0xabb3c9, a: lkQFirst))
    .build();

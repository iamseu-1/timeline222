import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/links.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/tile.dart';
import 'package:archive_prototype/scene/viewport.dart' show SceneView;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 소속선(구역 22) · 옮겨 앉기 실(구역 52)의 0.1.1 고침(lib/scene/paint/links.dart `_planPart` · `_readParts` · `_planMoves` · `_floorOf` — 스위치 route 뒤).
// 결함 번호는 이어 주는 선 설계안 '작은 고침 묶음'의 번호(묶음 D — .claude/research/workflows/args/line-routing-prev.json):
//  · 18 · 45 폴더 밖(조감 · 스위치 folder 끔 · 접힌 그릇 안) 소속선이 사이 줄 띠 뒤로 지나면 굴 문(명세 04 3-9) — 굴 문 훑기가 소속선도 본다.
//  · 19 조감 · 덧단이 없는 줄에서는 매단 몫 0(옛 저장소 몫 c × 23을 쓰지 않음).
//  · 28 선 끝 · 매듭은 그 띠의 몸통 아랫변 · 꼬리표 밑 흰 사슬 단 밑(짧은 꼬리표가 줄의 띠 아랫변보다 위).
//  · 29 소속선 조각을 이어 읽음 · 시작이 화면 왼쪽 밖이면 화면 왼끝 + 12에 붙임.
//  · 34 옮겨 앉기: 앞 토막 네모 없이 구역 52 항목의 줄로 매듭 · 옮긴 해가 화면 왼쪽 밖이면 화면 왼끝 + 6에 붙임.

/// 단계 9에서 통 하나가 32px일 때의 1분 폭 — 자리는 '그림 영역 왼쪽에서 몇 px'로 적고 분으로 바꾼다(chains_paint_test와 같은 식). 타일 하나 = 8192px.
final ppm = 32 / bucketMinutes(9);
double at(double px) => px / ppm;
const tilePx = 8192.0;

/// 엔진 답 꼴의 줄 하나(줄 값이 실린 새 저장소): 지도자 칸만(사슬 없음). [hang]이면 매단 속국 줄 그만큼(덧단 줄도 그만큼).
Map<String, dynamic> row(int id, {int hang = 0}) => {
  'id': id, 'height': 0, 'band_top': 0, 'band_h': 0, 'dyn_top': -1, 'lead_top': -1, 'cab_top': -1, 'text_top': 0, 'text_lines': 1,
  'rail_top': 0, 'organ_top': -1, 'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0, 'cats': <int>[], 'fig': 0,
  'fig_wide': 0, 'dep': 0, 'zones': hang, 'hem': 0, 'variant': 0, 'rail': 0, 'cell_rows': 1, 'dynasty': 0, 'leader': 1, 'cabinet': 0,
  'hang': hang,
};

SceneLayout layoutOf({int hang = 0, int rows = 3}) => SceneLayout.fromJson({
  'packs': [
    {'id': 1, 'name': '소속 견본', 'events': 0},
  ],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '하연 갈래', 'color': 0xa0bcc5, 'key': 'part-a', 'dynasty': 0, 'leader': 1, 'cabinet': 0, 'organ': 0,
      'rail_levels': 2, 'rows': [for (int r = 0; r < rows; r++) row(r, hang: r == 0 ? hang : 0)],
    },
  ],
  'epochs': <dynamic>[],
  'categories': <dynamic>[],
  'axis': <dynamic>[],
})..reduceMotion = true;

/// 띠 look: 비트 20 = 칸이 있다 · 21 + 5 지도자. 0이면 칸 없는 띠 — 지도자 줄에서 사건 칸을 올린 짧은 꼬리표(몸통 아랫변이 줄의 띠 아랫변보다 14 위).
const leaderLook = 1 << 20 | 1 << 26, shortLook = 0;
const reed = 0xb1a0c9, sea = 0xabb3c9, sand = 0xc8b193;

(TimelineScene, TimelinePainter) make(Map<int, Uint8List> tiles, {int hang = 0, double from = 0}) {
  final layout = layoutOf(hang: hang);
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-at(100000), at(100000))
    ..setContentHeight(layout.totalHeight + 200);
  controller.showRange(at(from), at(from + 1920 - SceneView.gutter));
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    fetchTile: (level, x, chunk, packs) async => level == 9 && chunk == 0 && tiles[x] != null ? tiles[x]! : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

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

/// 관계선 층 기록('352.0,123.5 → …')의 수만.
List<double> nums(String text) => [for (final s in text.split(RegExp('[ ,]'))) double.tryParse(s) ?? double.nan].where((v) => !v.isNaN).toList();

/// 기록 '소속선'의 (x, 위 끝, 아래 끝) — 없으면 null.
List<double>? partOf(TimelinePainter painter) {
  final n = noted(painter, '소속선');
  return n.isEmpty ? null : nums(n.single);
}

/// 줄 [r]의 띠 아랫변(화면 y).
double bandBottom(TimelineScene scene, int r) {
  final layout = scene.layout, geo = layout.geo(r);
  return scene.controller.view.yOf(layout.rowTop(r) + geo.bandTop + geo.bandHeight);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(PaintPick.reset);

  test('19 조감: 상국 줄에 덧단이 없으면 매단 몫 0 — 소속선은 상국 띠 바로 밑에서(옛 저장소 몫 c × 23 = 138px 밑에서 떠 시작하거나 빠지지 않음)', () async {
    // 줄 0의 상국(1) → 줄 2의 소속(3) · 아래로 · 내보내기 c = 그 줄의 매단 줄 수 6(모두 펼친 상태로 센 값).
    final tile = (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, at(100), at(1500), '적석 제후 연방', look: leaderLook)
          ..band(3, 2, at(600), at(1200), '붉은바위 백령', look: leaderLook, color: reed)
          ..item(LinkLayer.secPart, 601, 0, at(600), at(1200), row2: 2, ref: 3, b: 1, a: 1, c: 6, color: sea))
        .build();
    for (final route in [true, false]) {
      PaintPick.route = route;
      final (scene, painter) = make({0: tile}, hang: 6);
      addTearDown(scene.dispose);
      scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
      await settle(scene, painter);
      expect(scene.layout.birdShape, isNotNull, reason: '조감');
      final part = partOf(painter);
      final under = bandBottom(scene, 0) + 1;
      if (route) {
        expect(part, isNotNull, reason: '조감에서도 소속선이 있다');
        expect(part![1], closeTo(under, .051), reason: '상국 띠 아랫변 + 1');
        expect(part[2], closeTo(scene.controller.view.yOf(scene.layout.rowTop(2) + scene.layout.geo(2).bandTop) - 2.5, .051), reason: '소속 띠 윗변 − 2.5');
      } else {
        expect(part == null || part[1] >= under + 138 - .1, isTrue, reason: '끈 길(예전): 6 × 23 밑에서 시작하거나 없음 — $part');
      }
    }
  });

  test('28 짧은 꼬리표(사건 칸을 올린 꼬리표)의 소속선은 그 몸통 아랫변에서 — 줄의 띠 아랫변 밑 허공이 아니라', () async {
    final tile = (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, at(100), at(1500), '갈대 연방', look: shortLook)
          ..band(3, 1, at(600), at(1200), '물안개 백령', look: leaderLook, color: reed)
          ..item(LinkLayer.secPart, 601, 0, at(600), at(1200), row2: 1, ref: 3, b: 1, a: 1, color: sea))
        .build();
    for (final route in [true, false]) {
      PaintPick.route = route;
      final (scene, painter) = make({0: tile});
      addTearDown(scene.dispose);
      await settle(scene, painter);
      final layout = scene.layout, v = scene.controller.view;
      final body = v.yOf(layout.rowTop(0) + painter.bands.bodyBottomOf(layout, 0, 1));
      expect(body, lessThan(bandBottom(scene, 0) - 10), reason: '칸 없는 띠는 지도자 줄에서 짧은 꼬리표');
      final part = partOf(painter)!;
      expect(part[1], closeTo((route ? body : bandBottom(scene, 0)) + 1, .051), reason: 'route $route — 위 끝');
    }
  });

  group('29 소속선 조각 이어 읽기 · 왼끝 붙임', () {
    /// 타일 0: 상국(줄 0) · 소속(줄 1)과 [start]부터의 소속선 조각(잘리지 않은 시작 · 오른쪽 잘림).
    Uint8List tile0(double start) => (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, at(start - 400), at(tilePx), '적석 제후 연방', look: leaderLook, flags: Tile.clipRight)
          ..band(3, 1, at(start - 200), at(tilePx), '붉은바위 백령', look: leaderLook, color: reed, flags: Tile.clipRight)
          ..item(LinkLayer.secSquare, 101, 0, at(start - 400), at(tilePx), ref: 1, name: '적석 제후 연방', color: sea, flags: Tile.clipRight)
          ..item(LinkLayer.secSquare, 103, 1, at(start - 200), at(tilePx), ref: 3, name: '붉은바위 백령', color: reed, flags: Tile.clipRight)
          ..item(LinkLayer.secPart, 601, 0, at(start), at(tilePx), row2: 1, ref: 3, b: 1, a: 1, color: sea, flags: Tile.clipRight))
        .build();

    /// 타일 1: 같은 셋의 왼쪽이 잘린 조각.
    Uint8List tile1() => (TileBuilder(level: 9, x: 1, chunk: 0)
          ..band(1, 0, 0, at(1500), '적석 제후 연방', look: leaderLook, flags: Tile.clipLeft)
          ..band(3, 1, 0, at(1200), '붉은바위 백령', look: leaderLook, color: reed, flags: Tile.clipLeft)
          ..item(LinkLayer.secSquare, 101, 0, 0, at(1500), ref: 1, name: '적석 제후 연방', color: sea, flags: Tile.clipLeft)
          ..item(LinkLayer.secSquare, 103, 1, 0, at(1200), ref: 3, name: '붉은바위 백령', color: reed, flags: Tile.clipLeft)
          ..item(LinkLayer.secPart, 601, 0, 0, at(1200), row2: 1, ref: 3, b: 1, a: 1, color: sea, flags: Tile.clipLeft))
        .build();

    test('시작이 화면 안이면 조각이 몇 개로 오든 제 시작 + 12', () async {
      final (scene, painter) = make({0: tile0(tilePx - 300), 1: tile1()}, from: tilePx - 600);
      addTearDown(scene.dispose);
      await settle(scene, painter);
      final v = scene.controller.view;
      expect(v.xOf(at(tilePx)), closeTo(v.left + 600, 1e-6), reason: '타일 경계가 화면 안');
      final part = partOf(painter)!;
      expect(part[0], closeTo(v.xOf(at(tilePx - 300)) + 12, .051));
    });

    test('실린 조각이 왼쪽 잘린 것뿐이면 시작을 모르므로 화면 왼끝 + 12에 붙인다 — 끈 길(예전)은 타일 경계 + 12의 가짜 자리', () async {
      // 타일 0(소속 시작이 든 조각)이 실리지 않은 장면 — 화면 왼끝 + 300에 타일 경계.
      for (final route in [true, false]) {
        PaintPick.route = route;
        final (scene, painter) = make({1: tile1()}, from: tilePx - 300);
        addTearDown(scene.dispose);
        await settle(scene, painter);
        final v = scene.controller.view;
        final part = partOf(painter)!;
        if (!route) {
          expect(part[0], closeTo(v.left + 300 + 12, .051), reason: '예전: 잘린 조각의 시작(타일 경계)을 소속 시작으로');
          continue;
        }
        // 붙는 머리 이름(화면 끝 + 6에 붙어 따라옴)의 끝은 예전부터 있던 탭 비킴이 비킨다.
        final tabEnd = painter.bands.headNameEnd[3];
        final pin = v.left + 12;
        expect(part[0], closeTo(tabEnd != null && pin < tabEnd + 6 ? tabEnd + 8 : pin, .051), reason: '화면 왼끝 + 12(머리 이름 끝 $tabEnd)');
        expect(part[0], lessThan(v.left + 200));
      }
    });

    test('조감: 시작이 화면 왼쪽 밖이면 화면 왼끝 + 12에 붙인다 — 끈 길(예전)은 선이 없다(조감에는 비킬 머리 이름이 없어 버림)', () async {
      final tile = (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, at(100), at(3000), '적석 제후 연방', look: leaderLook)
            ..band(3, 2, at(200), at(3000), '붉은바위 백령', look: leaderLook, color: reed)
            ..item(LinkLayer.secSquare, 101, 0, at(100), at(3000), ref: 1, name: '적석 제후 연방', color: sea)
            ..item(LinkLayer.secSquare, 103, 2, at(200), at(3000), ref: 3, name: '붉은바위 백령', color: reed)
            ..item(LinkLayer.secPart, 601, 0, at(200), at(3000), row2: 2, ref: 3, b: 1, a: 1, color: sea))
          .build();
      for (final route in [true, false]) {
        PaintPick.route = route;
        final (scene, painter) = make({0: tile}, from: 1000);
        addTearDown(scene.dispose);
        scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
        await settle(scene, painter);
        expect(scene.layout.birdShape, isNotNull);
        final part = partOf(painter);
        if (route) {
          expect(part![0], closeTo(scene.controller.view.left + 12, .051));
        } else {
          expect(part, isNull);
        }
      }
    });

    test('소속 띠가 화면 안에 들지 않으면 붙이지 않는다', () async {
      // 소속(줄 1)이 화면 왼끝 + 10에서 끝남 — 붙일 자리(왼끝 + 12) 앞.
      final tile = (TileBuilder(level: 9, x: 0, chunk: 0)
            ..band(1, 0, at(100), at(1500), '적석 제후 연방', look: leaderLook)
            ..band(3, 1, at(200), at(1010), '붉은바위 백령', look: leaderLook, color: reed)
            ..item(LinkLayer.secSquare, 101, 0, at(100), at(1500), ref: 1, name: '적석 제후 연방', color: sea)
            ..item(LinkLayer.secSquare, 103, 1, at(200), at(1010), ref: 3, name: '붉은바위 백령', color: reed)
            ..item(LinkLayer.secPart, 601, 0, at(200), at(1010), row2: 1, ref: 3, b: 1, a: 1, color: sea))
          .build();
      final (scene, painter) = make({0: tile}, from: 1000);
      addTearDown(scene.dispose);
      await settle(scene, painter);
      expect(partOf(painter), isNull);
    });
  });

  group('34 · 28 옮겨 앉기 실', () {
    /// 줄 0의 앞 토막(1 — [frontFrom] ~ 1000) → 줄 2의 뒤 토막(2 — 1000 ~ 1800) · 옮긴 해 1000. [frontSquare]가 거짓이면 앞 토막 네모(구역 20)를 싣지 않는다.
    Uint8List moveTile({bool frontSquare = true, int frontLook = leaderLook, double frontFrom = 100}) {
      final t = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(1, 0, at(frontFrom), at(1000), '보헤미아', look: frontLook, color: sand)
        ..band(2, 2, at(1000), at(1800), '보헤미아', look: leaderLook, color: sand)
        ..band(5, 1, at(100), at(1800), '오스트리아', look: leaderLook, color: reed)
        ..item(LinkLayer.secSquare, 105, 1, at(100), at(1800), ref: 5, name: '오스트리아', color: reed)
        ..item(LinkLayer.secSquare, 102, 2, at(1000), at(1800), ref: 2, name: '보헤미아', color: sand)
        ..item(LinkLayer.secMove, 701, 0, at(1000), at(1800), ref: 1, a: 0, b: 2, text2: 'mv')
        ..item(LinkLayer.secMove, 702, 2, at(1000), at(1800), ref: 2, a: 1, b: 1, text2: 'mv');
      if (frontSquare) t.item(LinkLayer.secSquare, 101, 0, at(frontFrom), at(1000), ref: 1, name: '보헤미아', color: sand);
      return t.build();
    }

    /// 앞 토막 바닥(화면 y — 몸통 아랫변).
    double floorOf(TimelineScene scene, TimelinePainter painter, int r, int band) =>
        scene.controller.view.yOf(scene.layout.rowTop(r) + painter.bands.bodyBottomOf(scene.layout, r, band));

    test('옮긴 해가 화면 왼쪽 밖이면 화면 왼끝 + 6에 붙여 곧게 뒤 토막으로 — 끈 길(예전)은 실이 없다 · 사이 줄 띠에는 굴 문', () async {
      for (final route in [true, false]) {
        PaintPick.route = route;
        final (scene, painter) = make({0: moveTile()}, from: 1100);
        addTearDown(scene.dispose);
        await settle(scene, painter);
        final moves = noted(painter, '옮겨앉기');
        if (!route) {
          expect(moves, isEmpty);
          continue;
        }
        final v = scene.controller.view;
        expect(moves.single, endsWith('붙임'));
        final n = nums(moves.single);
        final x = (v.left + 6).floorToDouble() + .5;
        expect(n[0], x, reason: '화면 왼끝 + 6');
        expect(n[1], closeTo(floorOf(scene, painter, 0, 1).roundToDouble() - .5, .051), reason: '앞 토막 바닥의 매듭');
        expect(n[2], x, reason: '곧은 세로');
        expect(n[3], greaterThan(scene.controller.view.yOf(scene.layout.rowTop(2) + scene.layout.geo(2).bandTop)), reason: '뒤 토막 안으로 든다');
        expect(noted(painter, '굴문').where((s) => s.startsWith('5 세로 ')), hasLength(1), reason: '사이 줄(오스트리아)의 테 — ${noted(painter, '굴문')}');
      }
    });

    test('앞 토막 네모가 실리지 않아도 구역 52 앞 끝 항목의 줄로 매듭을 센다 — 끈 길(예전)은 실이 없다', () async {
      for (final route in [true, false]) {
        PaintPick.route = route;
        final (scene, painter) = make({0: moveTile(frontSquare: false)});
        addTearDown(scene.dispose);
        await settle(scene, painter);
        final moves = noted(painter, '옮겨앉기');
        if (!route) {
          expect(moves, isEmpty);
          continue;
        }
        final v = scene.controller.view;
        final n = nums(moves.single);
        expect(n[0], (v.xOf(at(1000)) - 6).floorToDouble() + .5, reason: '뒤 토막 왼쪽 6 앞');
        expect(n[1], closeTo(floorOf(scene, painter, 0, 1).roundToDouble() - .5, .051), reason: '앞 토막 줄의 바닥');
        expect(n[2], v.xOf(at(1000)), reason: '뒤 토막 왼쪽 끝으로 꺾어 든다');
      }
    });

    test('28 매듭은 짧은 앞 토막 꼬리표의 몸통 아랫변에 — 줄의 띠 아랫변 밑 허공이 아니라', () async {
      for (final route in [true, false]) {
        PaintPick.route = route;
        final (scene, painter) = make({0: moveTile(frontLook: shortLook)});
        addTearDown(scene.dispose);
        await settle(scene, painter);
        final body = floorOf(scene, painter, 0, 1);
        expect(body, lessThan(bandBottom(scene, 0) - 10), reason: '칸 없는 띠는 짧은 꼬리표');
        final n = nums(noted(painter, '옮겨앉기').single);
        expect(n[1], closeTo((route ? body : bandBottom(scene, 0)).roundToDouble() - .5, .051), reason: 'route $route');
      }
    });
  });

  test('18 · 45 폴더 밖 소속선이 사이 줄 띠 뒤로 지나면 그 띠의 위 · 아래 테에 굴 문 — 끈 길(예전)은 표시 없이 숨는다', () async {
    // 줄 0의 상국(1) → 줄 2의 소속(3). 사이 줄 1에 다른 구성국(2)이 소속선 자리를 덮는다(펼친 연방의 빗살 — 소속 폴더가 없는 곳).
    final tile = (TileBuilder(level: 9, x: 0, chunk: 0)
          ..band(1, 0, at(100), at(1500), '적석 제후 연방', look: leaderLook)
          ..band(2, 1, at(400), at(1300), '검은내 백령', look: leaderLook, color: sand)
          ..band(3, 2, at(600), at(1200), '붉은바위 백령', look: leaderLook, color: reed)
          ..item(LinkLayer.secSquare, 101, 0, at(100), at(1500), ref: 1, name: '적석 제후 연방', color: sea)
          ..item(LinkLayer.secSquare, 102, 1, at(400), at(1300), ref: 2, name: '검은내 백령', color: sand)
          ..item(LinkLayer.secSquare, 103, 2, at(600), at(1200), ref: 3, name: '붉은바위 백령', color: reed)
          ..item(LinkLayer.secPart, 601, 0, at(600), at(1200), row2: 2, ref: 3, b: 1, a: 1, color: sea))
        .build();
    for (final route in [true, false]) {
      PaintPick.route = route;
      final (scene, painter) = make({0: tile});
      addTearDown(scene.dispose);
      await settle(scene, painter);
      expect(partOf(painter), isNotNull);
      final doors = noted(painter, '굴문');
      if (route) {
        expect(doors, hasLength(1), reason: '$doors');
        expect(doors.single, startsWith('2 세로 '), reason: '사이 줄의 구성국(2)에만 — 두 끝(1 · 3)은 건너뜀');
        expect(nums(doors.single)[1], closeTo(partOf(painter)![0], .051), reason: '소속선 x');
      } else {
        expect(doors, isEmpty);
      }
    }
  });
}

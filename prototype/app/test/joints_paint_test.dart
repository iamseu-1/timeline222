import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/emphasis.dart' as em;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/axis.dart' show AxisLook;
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/scopes.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/ruler.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'axis_model_test.dart' show cell, layoutOf;
import 'floor_rules_test.dart' as fr;
import 'scopes_paint_test.dart' as sp;
import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 가로 · 세로 구분선 맞닿음 걸음 2(감독 결정 2026-10-25 "모든 가로세로 구분선은 맞닿게" — 띠 몸통 밖의 나머지 · 띠 몸통은 floor_rules_test.dart):
//   · 날짜 칸 머리 단 — 모서리 칸 오른쪽 선이 줄 사이 구분선 줄(· 접힌 보조 달력의 투명한 1px)까지 끊김 없이 · 구분선과 T자 · 단추인 줄은 ㄱ자 귀
//   · 그릇 폴더 — 안쪽 겹선 왼쪽 위 직각 귀에 먹 한 번 · 둘째 탭(구역 53)의 세로 변이 몸통 윗변 줄까지 · 몸통 윗변이 탭 사이에서도 이어짐
//   · 그릇 상자 — 뚜껑 밑선이 양옆 테 사이에서만(흐린 상자의 귀에 먹 두 번 없음) · 상자 안 가로대는 테 바로 옆부터(예전 2px 틈)
//   · 할거기 경계 파선 — 띠 몸통의 가로 금 줄은 건너뜀(가로 금 하나 — 짙은 점 없음) · 다른 줄의 무늬는 그대로
// 꼴 off(`--paint-rows=off`)는 이 갈래 전 그림 그대로 — 시험마다 off의 옛 꼴도 함께 본다.

/// RGBA 바이트(1920 × 1080)에서 그 픽셀의 0xRRGGBBAA.
int at(Uint8List px, num x, num y) {
  final i = (y.floor() * 1920 + x.floor()) * 4;
  return px[i] << 24 | px[i + 1] << 16 | px[i + 2] << 8 | px[i + 3];
}

/// 그리개의 한 장면을 RGBA로(글줄이 다 준비될 때까지 되풀이).
Future<Uint8List> pixels(TimelinePainter painter) async {
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

/// 0xAARRGGBB 불투명 색을 [at]의 0xRRGGBBAA로.
int rgba(int argb) => (argb & 0xffffff) << 8 | 0xff;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(PaintPick.reset);

  group('날짜 칸 머리 단', () {
    /// 연도 · 공통 시대 · 접힌 보조 달력(투명한 1px) · 나라 시대 둘 · 간지 · 연호 묶음(단추) · 도읍 묶음(단추).
    Future<(TimelineScene, TimelinePainter, Uint8List)> head(FloorRule rule) async {
      PaintPick.rows = rule;
      final layout = layoutOf([
        cell(1, 0, 0, 100, 400, '공통 시대'),
        cell(1, 1, 0, 100, 400, '1번 시대'),
        cell(1, 2, 0, 100, 400, '2번 시대'),
        cell(2, 1, 0, 100, 400, '1번 연호', strip: 1),
        cell(3, 1, 0, 100, 400, '1번 도읍', strip: 101),
      ]);
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 1080)
        ..setExtent(minuteOfYear(-3000), minuteOfYear(3000))
        ..setContentHeight(layout.totalHeight);
      final scene = TimelineScene(controller: controller, layout: layout, fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build());
      addTearDown(scene.dispose);
      final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
      controller.showRange(minuteOfYear(240), minuteOfYear(340));
      painter.axis.restoreState(const {'show': {'ganji': true, 'eras': true, 'capitals': true}});
      return (scene, painter, await pixels(painter));
    }

    test('모서리 칸 오른쪽 선이 줄 사이 구분선 줄까지 이어진다(T자) · 접힌 보조 달력 줄도 · 단추인 줄은 위 줄에 선이 있으면 제 구분선 줄 한 칸(ㄱ자) — off는 예전 구멍', () async {
      final (scene, painter, b) = await head(FloorRule.b);
      final rows = painter.axis.model!.rows;
      final left = scene.controller.view.left;
      final edge = rgba(AxisLook.edge), x = left - 1;
      expect([for (final r in rows) r.kind.name], ['years', 'epoch', 'ganji', 'cal', 'epoch', 'epoch', 'group', 'group'], reason: '줄 구성');
      expect(rows[3].height, 1, reason: '접힌 보조 달력 줄은 투명한 구분선 1px');
      final buttons = {6, 7};
      for (final (i, r) in rows.indexed) {
        if (r.border && i != 3) expect(at(b, left + 5, r.top), rgba(AxisLook.rowLine), reason: '줄 $i 구분선(그림 영역만 — left부터)');
        if (!buttons.contains(i)) {
          for (double y = r.top; y < r.top + r.height; y++) {
            expect(at(b, x, y), edge, reason: '줄 $i(${r.kind.name}) y $y: 모서리 칸 선이 끊기지 않음');
          }
        }
      }
      // 첫 단추 줄(연호 묶음): 위 줄(나라 시대)에 선이 있어 제 구분선 줄까지 내려와 ㄱ자 귀 · 알맹이에는 선이 없다(css `border-right: none`).
      expect(at(b, x, rows[6].top), edge, reason: '단추 줄의 구분선 줄 — 귀');
      for (double y = rows[6].top + 1; y < rows[6].top + rows[6].height; y++) {
        expect(at(b, x, y), isNot(edge), reason: '단추 줄 알맹이 y $y');
      }
      // 둘째 단추 줄(도읍 묶음): 위 줄도 단추라 선이 없다.
      expect(at(b, x, rows[7].top), isNot(edge), reason: '단추 줄 뒤의 단추 줄은 귀 없음');
      // 맨 아래 단추 줄의 밑은 날짜 칸 밑줄(head − 1) 그대로.
      expect(at(b, x, scene.controller.view.head - 1), rgba(AxisLook.bottom));

      // 꼴 off: 예전 — 줄마다 알맹이만(구분선 줄 · 접힌 보조 달력 줄이 빔 · 단추 줄의 귀 없음).
      final (_, painterOff, off) = await head(FloorRule.off);
      final rowsOff = painterOff.axis.model!.rows;
      for (final i in [1, 2, 3, 4, 5, 6]) {
        expect(at(off, x, rowsOff[i].top), isNot(edge), reason: '꼴 off 줄 $i 구분선 줄의 구멍');
      }
      // 바뀐 픽셀은 모서리 칸 선의 열뿐.
      for (int y = 0; y < scene.controller.view.head; y++) {
        for (int xx = 0; xx < 1920; xx++) {
          if (xx == x) continue;
          if (at(b, xx, y) != at(off, xx, y)) fail('모서리 칸 선 밖의 픽셀이 바뀜: $xx,$y');
        }
      }
    });
  });

  group('그릇 폴더 · 상자', () {
    /// 폴더 s2(줄 2 ~ 4 · x 100 ~ 1500)와 [labels]의 둘째 탭(구역 53 — (이름, x0, x1)). [box]면 줄 3 ~ 4에 상자 s3(x 400 ~ 1300 · 깊이 1).
    Future<(TimelineScene, TimelinePainter, Uint8List)> scene(FloorRule rule, {List<(String, double, double)> labels = const [], bool box = false, bool dim = false}) async {
      PaintPick.rows = rule;
      final t = sp.scopeTile([('s2', '남곡 할거', 2, 4, 100, 1500, 3), if (box) ('s3', '서안 제후', 3, 4, 400, 1300, 2)], [2, 3, 4], (r) => r < 3 || !box ? 140.0 + 60 * r : 440.0 + 60 * r);
      for (final (i, (name, x0, x1)) in labels.indexed) {
        t.item(ScopeLayer.secLabel, 900 + i, 2, sp.px(x0), sp.px(x1), row2: 4, name: name);
      }
      final layout = sp.layoutOf([sp.scopeVariant(1, 's2', '남곡 할거', [2, 3, 4]), if (box) sp.scopeVariant(2, 's3', '서안 제후', [3, 4], depth: 1)]);
      final (s, painter) = sp.make(layout, t.build());
      addTearDown(s.dispose);
      expect(layout.openScope('s2', true), isTrue);
      if (box) expect(layout.openScope('s3', true), isTrue);
      s.controller.setContentHeight(layout.totalHeight);
      if (dim) {
        em.Emphasis.of(s)
          ..reduceMotion = true
          ..set(const em.Look(bands: {99})); // 강조(걸러 보기) 밖의 그릇은 .45(Dim.scopeDim) — 흐린 상자
      }
      await sp.settle(s, painter);
      painter.debugSink.clear();
      return (s, painter, await pixels(painter));
    }

    test('폴더 안쪽 겹선의 왼쪽 위 직각 귀는 먹 한 번(윗변과 같은 짙기) — off는 두 번(짙은 점)', () async {
      for (final rule in [FloorRule.b, FloorRule.off]) {
        final (_, painter, px) = await scene(rule);
        final f = sp.boxOf(painter, '폴더', '남곡 할거');
        final il = f[0] + FolderLook.inset, iT = f[1] + G.folderTab + FolderLook.inset;
        final corner = at(px, il, iT), top = at(px, il + 6, iT), side = at(px, il, iT + 6), inside = at(px, il + 6, iT + 6);
        expect(top, isNot(inside), reason: '$rule: 윗 겹선이 있다');
        expect(side, top, reason: '$rule: 왼쪽 겹선 = 윗 겹선 짙기');
        expect(at(px, il, iT + 1), side, reason: '$rule: 왼쪽 겹선은 귀 바로 밑부터 이어짐(틈 없음)');
        if (rule == FloorRule.off) {
          expect(corner, isNot(top), reason: '꼴 off: 귀에 먹 두 번(예전)');
        } else {
          expect(corner, top, reason: '꼴 b: 귀는 먹 한 번');
        }
      }
    });

    test('둘째 탭: 몸통 윗변이 어깨 탭과 탭 사이 · 탭과 탭 사이에서도 이어지고 탭의 세로 변이 윗변 줄까지 내려와 ㄱ자로 맞닿음 · 탭 아래는 열림 — off는 예전(마지막 탭 뒤부터만 · 귀 빔)', () async {
      for (final rule in [FloorRule.b, FloorRule.off]) {
        final (_, painter, px) = await scene(rule, labels: [('청림기', 520, 600), ('수해기', 700, 780)]);
        final tab0 = RegExp(r'([\d.]+)~([\d.]+)').firstMatch(sp.noted(painter, '폴더탭').toSet().single)!;
        final tabR0 = double.parse(tab0.group(2)!).round();
        final tabs = [for (final s in sp.noted(painter, '둘째탭').toSet()) sp.nums(s)];
        expect(tabs, hasLength(2), reason: '$rule: 둘째 탭 둘');
        final body = tabs.first[2].round();
        final edgeAt = at(px, tabs.last[1] + 20, body); // 마지막 탭 뒤의 몸통 윗변(두 꼴 모두 있음)
        final open = at(px, tabs.first[0] + 10, body + 5); // 몸통 안(바탕)
        expect(edgeAt, isNot(open), reason: '$rule: 마지막 탭 뒤 윗변');
        final xa1 = tabs.first[0].round(), xr1 = tabs.first[1].round(), xa2 = tabs.last[0].round();
        // 매다는 실(첫 줄 띠의 구멍에서 몸통 윗변의 매듭까지 — 매듭은 지름 3)이 지나는 열은 건너뛴다 — 몸통 안 1 · 4px 밑이 바탕과 다른 열.
        bool thread(int x) => at(px, x, body + 1) != at(px, tabR0 + 2, body + 1) || at(px, x, body + 4) != at(px, tabR0 + 2, body + 4);
        if (rule == FloorRule.b) {
          for (int x = tabR0; x < xa1; x++) {
            if (!thread(x)) expect(at(px, x, body), edgeAt, reason: '꼴 b: 어깨 탭과 첫 둘째 탭 사이 윗변 x $x');
          }
          for (int x = xr1; x < xa2; x++) {
            if (!thread(x)) expect(at(px, x, body), edgeAt, reason: '꼴 b: 둘째 탭 사이 윗변 x $x');
          }
          for (final s in tabs) {
            final xa = s[0].round(), xr = s[1].round();
            expect(at(px, xa, body), at(px, xa, body - 4), reason: '꼴 b: 탭 왼쪽 변이 윗변 줄까지');
            expect(at(px, xr - 1, body), at(px, xr - 1, body - 4), reason: '꼴 b: 탭 오른쪽 변이 윗변 줄까지');
            expect(at(px, xa + 5, body), isNot(edgeAt), reason: '꼴 b: 탭 아래는 열림');
          }
        } else {
          expect(at(px, tabR0 + 1, body), isNot(edgeAt), reason: '꼴 off: 어깨 탭과 첫 둘째 탭 사이가 빔(예전)');
          expect(at(px, xa1, body), isNot(at(px, xa1, body - 4)), reason: '꼴 off: 탭 세로 변이 윗변 한 줄 위에서 멈춤(예전)');
        }
      }
    });

    test('상자: 뚜껑 밑선은 양옆 테 사이에서만(흐린 상자의 테 줄에 먹 한 번) · 상자 안 가로대는 테 바로 옆부터 — off는 예전 가로대 2px 틈(귀 짙음은 세로줄 얹기 뒤로 없음)', () async {
      for (final rule in [FloorRule.b, FloorRule.off]) {
        final (_, painter, px) = await scene(rule, box: true, dim: true);
        final box = sp.boxOf(painter, '상자', '서안 제후');
        final left = box[0], right = box[0] + box[2], body = box[1] + G.boxLid;
        final side = at(px, left, body + 4), sideR = at(px, right - 1, body + 4);
        final lid = at(px, left + 20, body);
        expect(lid, isNot(at(px, left + 20, body + 4)), reason: '$rule: 뚜껑 밑선');        if (rule == FloorRule.b) {
          expect(at(px, left, body), side, reason: '꼴 b: 왼쪽 테의 뚜껑 밑선 줄은 먹 한 번');
          expect(at(px, right - 1, body), sideR, reason: '꼴 b: 오른쪽 테도');
          expect(at(px, left + 1, body), lid, reason: '꼴 b: 밑선은 테 바로 옆부터');
          expect(at(px, right - 2, body), lid, reason: '꼴 b: 밑선은 오른쪽 테 바로 앞까지');
        } else {
          // 세로줄 얹기(4단계 마지막 합치기)로 흐린 상자의 테 · 밑선도 그 자리 바탕과 미리 섞은 불투명 색이라, 꼴 off에서 밑선이 테 줄까지 가도
          // 뒤에 긋는 테가 그 점을 덮는다 — 먹이 두 번 쌓여 짙은 점(예전 반투명 꼴)은 이제 어느 꼴에서도 없다.
          expect(at(px, left, body), side, reason: '꼴 off: 밑선이 테 줄까지 가도 불투명 테가 덮음(세로줄 얹기 뒤)');
        }
        final rails = {for (final s in sp.noted(painter, '가로대')) sp.nums(s)[0].toInt(): sp.nums(s)};
        expect(rails.keys, contains(4), reason: '$rule: 상자 둘째 줄의 가로대');
        final rail = rails[4]!, inset = rule == FloorRule.b ? 1.0 : FolderLook.railInset;
        expect(rail[1], left + inset, reason: '$rule: 가로대 왼쪽 끝');
        expect(rail[1] + rail[3], right - inset, reason: '$rule: 가로대 오른쪽 끝');
        if (rule == FloorRule.b) {
          final y = rail[2];
          expect(at(px, left + 1, y), at(px, left + 30, y), reason: '꼴 b: 가로대가 왼쪽 테 바로 옆까지');
          expect(at(px, right - 2, y), at(px, left + 30, y), reason: '꼴 b: 오른쪽 테 바로 앞까지');
        }
        // 폴더 가로대(폴더 둘째 줄 3은 상자 첫 줄이라 없음)는 그대로 — 폴더 안쪽 겹선 옆(+3).
        expect(rails.keys.toSet(), {4});
      }
    });
  });

  group('할거기 경계 파선', () {
    /// floor_rules_test의 띠(시기 · 지도자 · 내각 층 · 사건 칸)에 할거기 칠(구역 25) x 600 ~ 1000 — 경계 파선이 띠 몸통의 가로 금을 가로지른다.
    Future<(TimelinePainter, Uint8List)> hollow(FloorRule rule) async {
      PaintPick.rows = rule;
      final builder = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(1, 0, fr.at(100), fr.at(1600), '첫불 성채국', look: fr.bandLook)
        ..cell(20, 0, fr.at(150), fr.at(1400), '장부 학파\t복구기', kind: 4, lane: 0, style: fr.st(32, seq: 0))
        ..cell(10, 0, fr.at(150), fr.at(700), '은결 나나나', kind: 1, style: fr.st(0, seq: 0))
        ..cell(11, 0, fr.at(700), fr.at(1400), '둘째 지도자', kind: 1, style: fr.st(0, seq: 1))
        ..cell(30, 0, fr.at(150), fr.at(1400), '서목 윤 대재상', kind: 2, style: fr.st(0, seq: 0))
        ..item(ScopeLayer.secHollow, 700, 0, fr.at(600), fr.at(1000), ref: 1, color: 0xd4a39b);
      final (scene, painter) = fr.make(builder.build());
      addTearDown(scene.dispose);
      await fr.loadAll(scene);
      scene.prepare();
      return (painter, await pixels(painter));
    }

    test('파선은 띠 몸통의 가로 금 줄(색줄 아랫금 · 층 사이 · 사건 칸 윗줄)을 칠하지 않고 종이 칠도 파선 열을 비킨다 — 그 점은 칠 밖 옆 열과 같은 가로 금 하나 · 다른 줄의 무늬는 off와 같음', () async {
      final (painter, b) = await hollow(FloorRule.b);
      final rows = [...?painter.bands.innerRows[1]]..sort();
      expect(rows.length, greaterThanOrEqualTo(4), reason: '색줄 아랫금 · 층 사이 둘 · 사건 칸 윗줄');
      final notes = sp.noted(painter, '할거기').toSet();
      expect(notes, hasLength(1));
      final v = sp.nums(notes.single); // 띠 왼쪽,위,너비,높이
      final xl = v[1].floor(), xr = (v[1] + v[3] - 1).floor(), top = v[2], bottom = v[2] + v[4];
      final (_, off) = await hollow(FloorRule.off);
      var dashed = 0, on = 0;
      for (final x in [xl, xr]) {
        final out = x == xl ? x - 1 : x + 1, inside = x == xl ? x + 1 : x - 1; // 칠 밖 · 칠 안의 옆 열
        for (double y = top; y < bottom; y++) {
          if (rows.contains(y)) {
            expect(at(b, x, y), at(b, out, y), reason: '꼴 b: 가로 금 줄 $y의 파선 열 $x는 칠 밖과 같은 가로 금 하나(먹 한 번 · 옅은 점 없음)');
            expect(at(b, x, y), isNot(at(b, x, y - 1)), reason: '꼴 b: 가로 금 줄 $y의 파선 열 $x에 가로 금이 있다');
            if (at(off, x, y) != at(off, inside, y)) dashed++;
          } else {
            // 무늬(파선이 선 줄)는 그대로 — 꼴 b는 파선 열이 칠 밖(띠 칠)이라 칠 밖 옆 열과, 꼴 off는 칠 안이라 칠 안 옆 열과 견준다.
            final onB = at(b, x, y) != at(b, out, y), onOff = at(off, x, y) != at(off, inside, y);
            expect(onB, onOff, reason: '가로 금이 아닌 줄 $y의 파선 무늬는 그대로');
            if (onB) on++;
          }
        }
      }
      expect(on, greaterThan(10), reason: '파선이 있다');
      expect(dashed, greaterThan(0), reason: '꼴 off에서는 파선이 가로 금을 지나는 점이 있었다(짙은 점)');
    });
  });
}

import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row(int id, int height) => {
  'id': id, 'height': height, 'band_top': 19, 'band_h': height - 19, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

/// 자료집 3개: 첫째와 둘째는 트랙을 하나씩 갖고, 셋째(덧붙임)는 트랙이 없다.
Map<String, dynamic> layoutJson() => {
  'packs': [
    {'id': 1, 'name': '별여울 하나', 'events': 10},
    {'id': 2, 'name': '별여울 둘', 'events': 20},
    {'id': 3, 'name': '별여울 덧붙임', 'events': 5},
  ],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [row(0, 100), row(1, 140)]},
    {'id': 2, 'pack': 2, 'ord': 1, 'name': '여울 갈래', 'rows': [row(2, 120)]},
    {'id': 3, 'pack': 1, 'ord': 2, 'name': '나루 갈래', 'rows': [row(3, 160), row(4, 100)]},
  ],
  'epochs': [
    {'id': 1, 'pack': 1, 'start': -5000, 'end': 9000, 'color': 0xc8b193, 'name': '첫째 시대'},
  ],
};

void main() {
  group('단계', () {
    test('통 너비는 단계마다 네 배이고 타일은 통 256개다', () {
      expect(bucketMinutes(0), 1);
      expect(bucketMinutes(8), 65536);
      expect(tileSpan(8), 16777216);
      expect(tileOf(-1, 8), -1, reason: '기원전은 내림');
      expect(tileOf(0, 8), 0);
      expect(tileOf(16777216, 8), 1);
      expect(tileOrigin(8, -1), -16777216);
    });

    test('통이 16px 이상인 가장 작은 단계를 고른다', () {
      expect(levelFor(16 / bucketMinutes(5)), 5, reason: '정확히 16px');
      expect(levelFor(15.9 / bucketMinutes(5)), 6);
      expect(levelFor(1700 / 72), 0, reason: '가장 좁은 보기: 72분');
      expect(levelFor(1700 / (5500 * 525960)), 13, reason: '전체 보기: 5,500년');
      expect(levelFor(1e-12), levelMax, reason: '아무리 넓어도 마지막 단계');
      expect(levelFor(1000), 0);
    });

    test('경계에서는 지금 단계를 8%만큼 붙든다', () {
      expect(levelFor(15.9 / bucketMinutes(5), current: 5), 5, reason: '16px 바로 아래에서 흔들려도 그대로');
      expect(levelFor(14 / bucketMinutes(5), current: 5), 6, reason: '14.72px 아래로 내려가면 성긴 단계로');
      expect(levelFor(66 / bucketMinutes(5), current: 5), 5, reason: '64px를 조금 넘어도 그대로');
      expect(levelFor(70 / bucketMinutes(5), current: 5), 4, reason: '69.12px를 넘으면 촘촘한 단계로');
    });
  });

  group('보기', () {
    test('분과 화면 자리를 오간다', () {
      final v = SceneView()
        ..setSize(1920, 1080)
        ..lo = -1.3e9
        ..ppm = 1700 / (5500 * 525960);
      expect(v.plotWidth, 1920 - SceneView.gutter);
      for (final minute in [-1.3e9, -5.0e8, 0.0, 26640720.0]) {
        expect(v.minuteAt(v.xOf(minute)), closeTo(minute, 1e-6 / v.ppm));
      }
      expect(v.xOf(v.lo), SceneView.gutter);
      expect(v.span, closeTo(5500 * 525960 * (1920 - 240) / 1700, 1)); // 왼쪽 칸 240(리메이크 2부 — 목업 GUT)
    });

    test('돋보기는 같은 창에 더 적은 배치 px을 보인다', () {
      final v = SceneView()
        ..setSize(1920, 1080)
        ..ppm = .001;
      final wide = v.span;
      v.mag = 2;
      expect(v.plotWidth, 1920 / 2 - SceneView.gutter);
      expect(v.bodyHeight, 1080 / 2 - SceneView.rulerHeight);
      expect(v.span, lessThan(wide), reason: '해마다의 폭(ppm)은 그대로라 보이는 기간이 준다');
      expect(v.layoutOf(const (960.0, 540.0)), (480.0, 270.0));
    });
  });

  group('줄 자리', () {
    test('트랙 순서대로 줄을 쌓고 이분 탐색으로 줄을 찾는다', () {
      final l = SceneLayout.fromJson(layoutJson());
      expect(l.rowCount, 5);
      expect([for (int r = 0; r < 5; r++) l.rowTop(r)], [0, 100, 240, 360, 520]);
      expect(l.totalHeight, 620);
      expect(l.rowAt(0), 0);
      expect(l.rowAt(99.9), 0);
      expect(l.rowAt(100), 1);
      expect(l.rowAt(519), 3);
      expect(l.rowAt(9999), 4, reason: '아래로 벗어나면 마지막 줄');
      expect(l.rowAt(-5), 0);
      expect(l.geo(1).height, 140);
      expect(l.geo(1).bandTop, 19);
      expect(l.tracks.map((t) => (t.name, t.firstRow, t.rowCount)).toList(), [('해솔 갈래', 0, 2), ('여울 갈래', 2, 1), ('나루 갈래', 3, 2)]);
      expect(l.packs.map((p) => p.name).toList(), ['별여울 하나', '별여울 둘', '별여울 덧붙임']);
      expect(l.enabledPacks, [1, 2, 3]);
    });

    test('자료집을 끄면 그 트랙의 줄이 빠지고 아래 줄이 올라온다', () {
      final l = SceneLayout.fromJson(layoutJson());
      final before = l.version;
      l.enable({1, 3});
      l.finishFlow(); // 켜고 끄기는 흐른다(4단계 1걸음) — 여기서는 다 흐른 자리를 본다
      expect(l.version, greaterThan(before));
      expect(l.isVisible(2), isFalse);
      expect(l.rowTop(2), -1);
      expect([l.rowTop(0), l.rowTop(1), l.rowTop(3), l.rowTop(4)], [0, 100, 240, 400]);
      expect(l.totalHeight, 500);
      expect(l.rowAt(250), 3, reason: '끈 줄은 건너뛴다');
      expect(l.enabledPacks, [1, 3]);
      // 트랙이 없는 덧붙임 자료집을 끄면 줄은 그대로고 판 번호만 오른다(타일을 다시 받아야 하므로).
      final v = l.version;
      l.enable({1});
      l.finishFlow();
      expect(l.totalHeight, 500);
      expect(l.version, greaterThan(v));
      // 같은 조합을 다시 주면 판이 오르지 않는다.
      final same = l.version;
      l.enable({1});
      expect(l.version, same);
      l.enable(<int>{});
      l.finishFlow();
      expect(l.totalHeight, 0);
      expect(l.rowAt(10), -1);
    });
  });
}

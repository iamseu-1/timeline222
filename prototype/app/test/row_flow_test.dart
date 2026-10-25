import 'package:archive_prototype/motion.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/row_flow.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart';

// 줄 자리의 흐름과 세로 닻(움직임 원칙 ③ · ⑧ · 명세 05 6.5 · 6.6).
// 뼈대(support/fold_rows.dart): 칸 층이 없고 기간 막대는 '넉넉하게'에서만 → 두 장 꼬리표(리메이크 2부) 띠 = 이름 색줄 14 + 사건 칸 18(글줄 1) = 32,
// 줄의 몫은 첫 줄 5 + 32 = 37 · 그다음 3 + 5 + 32 = 40. 트랙 1 = 4+37+40+40+4 = 125, 트랙 2 = 4+37+40+4 = 85.
// 트랙끼리는 틈 없이 이어 쌓인다 — 트랙 높이가 아래 1px 테를 품은 값이다(명세 05 1.2 · 실측 9.2).

const _before = [4.0, 41.0, 81.0, 129.0, 166.0], _beforeTotal = 210.0;

/// 줄 1을 접은 뒤: 트랙 1이 85(4 + 37 + 40 + 4)로 줄고 아래가 따라 올라온다.
const _after = [4.0, -1.0, 41.0, 89.0, 126.0], _afterTotal = 170.0;

List<double> tops(SceneLayout l) => [for (int r = 0; r < l.rowCount; r++) l.rowTop(r)];

double progressAt(double ms, MotionToken token) => SpringSimulation(Motion.spring(token), 0, 1, 0).x(ms / 1000).clamp(0.0, 1.0);

void main() {
  test('움직임 값은 움직임 원칙의 것이다', () {
    expect(Motion.move, 400);
    expect(Motion.snap, 180);
    expect(Motion.bounce(MotionToken.move), .2);
  });

  group('줄 자리의 흐름', () {
    test('접기는 snap 스프링으로 옛 자리에서 새 자리로 흐른다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      expect(tops(l), _before);
      expect(l.totalHeight, _beforeTotal);
      expect(l.flowing, isFalse);

      l.setFolded({1});
      expect(l.flowing, isTrue);
      expect(tops(l), _before, reason: '첫 장면에는 아직 옛 자리다 — 팍 뛰지 않는다');
      expect(l.totalHeight, _beforeTotal);

      l.tickFlow(180);
      final t = progressAt(180, MotionToken.snap);
      expect(l.rowTop(2), closeTo(81 + (41 - 81) * t, 1e-9));
      expect(l.totalHeight, closeTo(_beforeTotal + (_afterTotal - _beforeTotal) * t, 1e-9));
      expect(l.flowing, isTrue);

      l.tickFlow(180);
      expect(l.flowing, isFalse);
      expect(tops(l), _after);
      expect(l.totalHeight, _afterTotal);
      expect(l.trackTop(1), 85, reason: '트랙 사이에 빈 틈은 없다 — 1px 테는 트랙 높이 안에');
      expect(l.trackHeight(0), 85);
    });

    test('접히는 줄은 높이 0으로 줄고, 다 줄 때까지 보인다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      expect(l.geo(1).height, 40);
      l.setFolded({1});
      expect(l.isVisible(1), isTrue, reason: '접히는 동안에도 그려야 한다');
      l.tickFlow(180);
      final t = progressAt(180, MotionToken.snap);
      expect(l.geo(1).height, closeTo(40 * (1 - t), 1e-9));
      expect(l.geo(1).bandTop, 8, reason: '안의 단은 제자리 — 내용이 찌그러지지 않는다');
      expect(l.rowClip(1), closeTo(40 * (1 - t), 1e-9));
      expect(l.rowClip(0), isNull, reason: '높이가 그대로인 줄은 자르지 않는다');
      l.tickFlow(180);
      expect(l.isVisible(1), isFalse);
      expect(l.rowTop(1), -1);
      expect(l.rowClip(1), isNull);
    });

    // ── 연출이 읽는 값(계약 3-1절 · 지금 연표의 `_gatherDraw` · `_squash`) ─────────────
    //
    // 줄 쌓기가 주는 것은 **줄 단위**다: 어디에서 와서(옛 자리 · 옛 높이 · 옛 생김새) 얼마나 왔는가(진행).
    // 줄 안의 띠 하나하나를 따로 옮기는 일은 띠의 옛 줄을 아는 쪽(타일 · 층)의 몫이다.

    test('흐르는 동안 옛 자리 · 옛 높이 · 진행 · 옮긴 거리를 읽을 수 있다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      expect(l.flowProgress, 1, reason: '흐르지 않으면 다 온 것이다');
      expect(l.stackCause, StackCause.none);
      final version = l.flowVersion;

      l.setFolded({1});
      expect(l.stackCause, StackCause.rows);
      expect(l.flowVersion, version + 1, reason: '흐름이 새로 시작될 때마다 오른다');
      expect(l.flowProgress, 0);
      expect(l.flowRemain, Motion.snap);
      // 줄 2는 81에서 41로 올라온다 — 그 거리가 지금 연표 `_gather`의 줄별 `dy`다.
      expect(l.rowFromTop(2), 81);
      expect(l.rowShift(2), 81 - 41);
      expect(l.rowFromHeight(1), 40);
      expect(l.wasVisible(1), isTrue);
      expect(l.isGoneRow(1), isTrue, reason: '이번 흐름에 사라진다');
      expect(l.isBornRow(1), isFalse);

      l.tickFlow(180);
      expect(l.flowProgress, closeTo(progressAt(180, MotionToken.snap), 1e-9));
      expect(l.flowElapsed, 180);
      expect(l.rowShift(2), 81 - 41, reason: '흐르는 동안 출발 자리는 그대로다');
      l.finishFlow();
      expect(l.flowProgress, 1);
      expect(l.flowRemain, 0);
    });

    test('밀도 · 조감이 바뀌면 잔상이 읽을 옛 모습(was-bird)을 함께 준다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      expect(l.metricsChanged, isFalse);
      expect(l.wasBird, isNull);

      // 조감으로 — 흐르는 동안 잔상은 **옛 모습**(보통 밀도)이어야 한다.
      expect(l.setConditions(l.conditions.copyWith(density: 2)), isTrue);
      expect(l.stackCause, StackCause.conditions);
      expect(l.metricsChanged, isTrue);
      expect(l.wasBird, isNull, reason: '옛 모습은 조감이 아니었다');
      expect(l.fromMetrics.tab, ViewMetrics.normal.tab);
      expect(l.metrics.tab, 0);
      expect(l.rowFromHeight(0), 37, reason: '옛 줄의 높이 — 잔상이 그 크기로 옅어진다');
      l.finishFlow();
      expect(l.metricsChanged, isFalse, reason: '다 흐르면 잔상도 끝이다');

      // 조감에서 나오면 잔상은 조감 모양 그대로(`.was-bird-a`).
      expect(l.setConditions(l.conditions.copyWith(density: 0)), isTrue);
      expect(l.wasBird, BirdShape.a);
      expect(l.fromMetrics.folded, 22);
      expect(l.metricsChanged, isTrue);
    });

    test('소속 펼치기 · 대범위 모아 보기는 접기와 갈라 알린다(모여드는 연출)', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      l.foldTrack(l.tracks[0].id, true);
      expect(l.stackCause, StackCause.view);
      l.finishFlow();
      l.setViewState(l.viewState.withScopeOpen('없는 대범위', true));
      expect(l.stackCause, StackCause.variants, reason: '켠 변형이 바뀌면 띠가 모여든다');
    });

    test('새로 펴지는 줄은 높이 0에서 자란다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      l.setFolded({1});
      l.finishFlow();
      l.setFolded(const {});
      expect(l.isVisible(1), isTrue);
      expect(l.geo(1).height, 0);
      expect(l.rowClip(1), 0, reason: '아직 보일 몫이 없다');
      l.tickFlow(180);
      final t = progressAt(180, MotionToken.move);
      expect(l.geo(1).height, closeTo(40 * t, 1e-9));
      expect(l.geo(1).bandTop, 8, reason: '펴지는 줄은 새 생김새로, 위에서부터 드러난다');
      l.tickFlow(180);
      expect(tops(l), _before);
      expect(l.rowClip(1), isNull);
    });

    test('도중에 목표가 바뀌면 지금 값에서 이어 흐른다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      l.setFolded({1});
      l.tickFlow(180);
      final mid = l.rowTop(2);
      l.setFolded(const {}); // 되돌린다
      expect(l.rowTop(2), closeTo(mid, 1e-9), reason: '그 자리에서 다시 출발 — 튀지 않는다');
      l.tickFlow(360);
      expect(tops(l), _before);
    });

    test('재입력 직후에도 줄의 속도는 끊기지 않는다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      l.setFolded({1});
      l.tickFlow(69.9);
      final before = l.rowTop(2);
      l.tickFlow(.1);
      final at = l.rowTop(2), speed = (at - before) / .0001;
      l.setFolded(const {});
      expect(l.rowTop(2), at);
      l.tickFlow(.1);
      expect((l.rowTop(2) - at) / .0001, closeTo(speed, 10));
      for (var i = 0; i < 100; i++) {
        l.tickFlow(8);
        expect(l.geo(1).height, greaterThanOrEqualTo(0));
        expect(l.rowTop(2), greaterThanOrEqualTo(l.rowTop(1) + l.geo(1).height - .1));
      }
      expect(tops(l), _before);
    });

    test('움직임 줄이기면 흐르지 않고 바로 간다', () {
      final l = SceneLayout.fromJson(twoTrackLayout())..reduceMotion = true;
      l.setFolded({1});
      expect(l.flowing, isFalse);
      expect(tops(l), _after);
    });

    test('자료집 켬/끔도 흐른다(4단계 1걸음) — 첫 장면은 옛 자리, 다 흐르면 새 자리', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      l.enable({2});
      expect(l.flowing, isTrue);
      expect(l.rowTop(0), 4, reason: '사라지는 줄도 첫 장면에는 옛 자리에 있다');
      expect(l.isGoneRow(0), isTrue);
      l.finishFlow();
      expect(l.rowTop(0), -1);
      expect(l.rowTop(3), 4);
    });

    test('흐르는 동안에도 줄 찾기와 보이는 줄 훑기가 맞는다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      l.setFolded({1});
      expect(l.visibleRows(0, 4), [0, 1, 2, 3, 4], reason: '접히는 중인 줄도 아직 목록에 있다');
      l.tickFlow(360);
      expect(l.visibleRows(0, 4), [0, 2, 3, 4]);
      expect(l.rowAt(60), 2, reason: '줄 1이 빠지고 줄 2가 41로 올라왔다(줄 3은 89)');
      expect(l.rowAt(0), 0);
      expect(l.rowAt(9999), 4);
    });
  });

  group('세로 닻', () {
    test('위쪽 줄이 접혀도 보던 줄은 화면에서 제자리다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      final a = RowAnchor()..capture(l, 50, 100); // 가운데 100 → 그보다 위의 가장 아래 줄은 2(81)
      expect(a.row, 2);
      expect(a.offset, 31);
      l.setFolded({1});
      l.finishFlow();
      expect(a.keep(l), 10, reason: '줄 2가 41로 올라왔으니 보기도 40만큼 올라간다');
      expect(l.rowTop(2) - 10, 31, reason: '화면에서 떨어진 거리는 그대로');
    });

    test('고른 사건의 줄을 먼저 붙잡는다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      final a = RowAnchor()..capture(l, 50, 100, preferred: 4);
      expect(a.row, 4);
      expect(a.offset, 116);
      l.setFolded({1});
      l.finishFlow();
      expect(a.keep(l), 10);
    });

    test('흐르는 동안에도 같은 진행값으로 따라간다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      final a = RowAnchor()..capture(l, 50, 100);
      l.setFolded({1});
      l.tickFlow(180);
      final t = progressAt(180, MotionToken.snap);
      expect(a.keep(l), closeTo(81 + (41 - 81) * t - 31, 1e-9));
      expect(l.rowTop(2) - a.keep(l)!, closeTo(31, 1e-9), reason: '매 장면 제자리');
    });

    test('붙잡은 줄이 접혀 사라지면 닻을 놓는다', () {
      final l = SceneLayout.fromJson(twoTrackLayout())..reduceMotion = true;
      final a = RowAnchor()..capture(l, 100, 200, preferred: 1);
      expect(a.row, 1);
      l.setFolded({1});
      expect(a.keep(l), isNull);
      expect(a.has, isFalse);
    });

    test('트랙을 접고 펼 때는 그 트랙의 위를 붙잡는다', () {
      final l = SceneLayout.fromJson(twoTrackLayout())..reduceMotion = true;
      final a = RowAnchor()..captureTrack(l, 50, 1); // 트랙 2의 위는 125
      expect(a.track, 1);
      expect(a.row, -1);
      expect(a.offset, 75);
      l.setViewState(const ViewState(foldedTracks: {1})); // 위 트랙이 125에서 34로 줄었다
      expect(l.trackTop(1), 34);
      expect(a.keep(l), -41, reason: '트랙 2의 위가 화면에서 75px 아래에 머물게');
      expect(l.trackTop(1) - a.keep(l)!, 75);
    });

    test('붙잡은 트랙이 꺼져 사라지면 닻을 놓는다', () {
      final l = SceneLayout.fromJson(twoTrackLayout())..reduceMotion = true;
      final a = RowAnchor()..captureTrack(l, 0, 1);
      expect(a.has, isTrue);
      l.setViewState(const ViewState(offTracks: {2}));
      expect(a.keep(l), isNull);
      expect(a.has, isFalse);
    });

    test('보이는 줄이 없으면 붙잡지 않는다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      l.enable(<int>{});
      l.finishFlow();
      final a = RowAnchor()..capture(l, 0, 200);
      expect(a.has, isFalse);
      expect(a.keep(l), isNull);
    });
  });
}

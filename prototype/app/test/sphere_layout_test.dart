import 'package:archive_prototype/scene/layout.dart'; // view_state.dart를 다시 내보낸다
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart';

// 문화권 머리 단(리메이크 조각 ② · 설계 4-6 #1 A · #5 B · 계약 3절 머리의 상자).
// 뼈대(support/fold_rows.dart의 twoTrackLayout)에 문화권을 얹는다: 트랙 1 = 동아시아(처음 펼침), 트랙 2 = 초원.
// 트랙 1의 높이 125 · 트랙 2의 높이 85(문화권 없이는 0 · 125에 이어 쌓여 전체 210 — 리메이크 2부의 두 장 꼬리표 띠 32).
// 문화권이 있으면: 머리 단 20 · 펼친 문화권은 그 아래 4 뒤에 트랙 · 문화권 사이 6 · 접힌 문화권은 머리 단 20뿐.
// 리메이크 4단계 과제 3: 펼친 문화권에 시대 · 주기 줄(sphereLines kind 2 · 3)이 있으면 머리 단 20 밑에 (시대 14) + (주기 13) + 2를 더한 뒤 4 아래에 트랙.
// 과제 4 걸음 1: 사람 띠(kind 1)는 그 밑에 줄 수 × 16을 더한다(때가 겹치지 않는 사람은 한 줄 — 앞뒤 틈 2해).

Map<String, dynamic> sphereLayout({bool steppeDefault = false}) {
  final json = twoTrackLayout();
  final tracks = json['tracks'] as List;
  (tracks[0] as Map)['sphere'] = 'east-asia';
  (tracks[1] as Map)['sphere'] = 'steppe';
  json['spheres'] = [
    {'id': 'east-asia', 'name': '동아시아', 'order': 1, 'count': 12, 'default': !steppeDefault},
    {'id': 'steppe', 'name': '초원', 'order': 2, 'count': 8, 'default': steppeDefault},
  ];
  return json;
}

SceneLayout build(Map<String, dynamic> json) => SceneLayout.fromJson(json)..reduceMotion = true;
List<double> tops(SceneLayout l) => [for (int r = 0; r < l.rowCount; r++) l.rowTop(r)];

/// 문화권 [sphere]의 시대 줄 하나 + 주기 줄(연호 눈금) 하나 — 머리 단 밑 높이 14 + 13 + 2 = 29.
List<Map<String, dynamic>> epochAndCycle(String sphere) => [
  {'kind': 2, 'sphere': sphere, 'start': 1000, 'end': 9000, 'name': '$sphere 시대', 'uid': 'ep-$sphere', 'color': 0xc8b193, 'data': '', 'pack': 1},
  {'kind': 3, 'sphere': sphere, 'start': 0, 'end': 0, 'name': '연호', 'uid': '', 'color': 0, 'data': '{"era":"연호","from":1,"step":10,"label":"연호"}', 'pack': 1},
];

/// 쌓은 자리 — [줄마다 위 자리, 트랙마다 위 자리, 전체 높이, 문화권마다 머리 단 위 · 높이].
List<Object> placed(SceneLayout l) => [
  tops(l), [for (int t = 0; t < l.tracks.length; t++) l.trackTop(t)], l.totalHeight,
  [for (int k = 0; k < l.spheres.length; k++) (l.sphereHeadTop(k), l.sphereHeadHeight(k))],
];

/// 흐름을 [dt]ms씩 끝까지 돌리며 장면마다 [check]를 부른다(흐르는 동안의 값을 보는 검사).
int flowEach(SceneLayout l, void Function() check, {double dt = 8}) {
  int frames = 0;
  check();
  while (l.flowing && frames < 500) {
    l.tickFlow(dt);
    check();
    frames++;
  }
  return frames;
}

void main() {
  // 이 파일의 손셈 자리는 민족 머리 줄이 없는 쌓기(0.1.0) 기준이다 — 머리 줄(0.1.1 감독 고름 나 · 트랙 첫 줄 묶음마다 +14)의 쌓기는 gutter_test가 본다.
  setUp(() => PaintPick.people = false);
  tearDown(PaintPick.reset);
  test('문화권이 없는 배치(옛 저장소)는 예전 그대로 — 머리 단 없이 트랙끼리 이어 쌓인다', () {
    final l = build(twoTrackLayout());
    expect(l.spheres, isEmpty);
    expect([l.trackTop(0), l.trackTop(1)], [0, 125]);
    expect(l.totalHeight, 210);
    expect(l.sphereHeadTop(0), -1);
    expect([l.isTrackHidden(0), l.isTrackHidden(1)], [false, false]);
  });

  test('처음에는 자료의 default 문화권 하나만 펴고 나머지는 접는다(설계 4-6 #1 A)', () {
    final l = build(sphereLayout());
    expect([for (final s in l.spheres) s.id], ['east-asia', 'steppe']);
    expect(l.viewState.foldedSpheres, {'steppe'});
    // 동아시아: 머리 단 0 · 그 아래 4 뒤에 트랙 1(24 ~ 149). 초원: 6 뒤 155에 머리 단 하나(접힘) — 전체 155 + 20 = 175.
    expect(l.sphereHeadTop(0), 0);
    expect(l.trackTop(0), 24);
    expect(l.sphereHeadTop(1), 155);
    expect(l.totalHeight, 175);
    expect([l.isTrackHidden(0), l.isTrackHidden(1)], [false, true]);
    expect(tops(l).sublist(0, 3), [28, 65, 105], reason: '트랙 1의 줄은 머리 단 24만큼 내려선다');
    expect([l.isVisible(3), l.isVisible(4)], [false, false], reason: '접힌 문화권의 줄은 보이지 않는다');
    // default가 둘째 문화권이면 그것만 편다.
    final m = build(sphereLayout(steppeDefault: true));
    expect(m.viewState.foldedSpheres, {'east-asia'});
  });

  test('접힌 문화권을 펴면 그 트랙이 머리 단 아래 4 뒤에 서고, 다시 접으면 머리 단 하나로 줄어든다', () {
    final l = build(sphereLayout());
    expect(l.foldSphere('steppe', false), isTrue);
    expect(l.sphereHeadTop(1), 155);
    expect(l.trackTop(1), 179);
    expect(l.trackHeight(1), 85);
    expect(l.totalHeight, 264);
    expect([l.rowTop(3), l.rowTop(4)], [183, 220]);
    expect(l.foldSphere('east-asia', true), isTrue);
    // 동아시아도 접으면 머리 단 둘만: 0 · 20 + 6 = 26 — 전체 26 + 20 + 4 + 85 = 135.
    expect(l.sphereHeadTop(0), 0);
    expect(l.sphereHeadTop(1), 26);
    expect(l.totalHeight, 135);
    expect([l.isVisible(0), l.isVisible(3)], [false, true]);
  });

  test('문화권이 하나뿐이면 아무것도 접지 않는다', () {
    final json = sphereLayout();
    (json['tracks'] as List)[1]['sphere'] = 'east-asia';
    json['spheres'] = [(json['spheres'] as List)[0]];
    final l = build(json);
    expect(l.viewState.foldedSpheres, isEmpty);
    // 머리 단 하나(0) · 트랙 1 24 ~ 149 · 트랙 2는 같은 문화권이라 틈 없이 149 ~ 234.
    expect([l.trackTop(0), l.trackTop(1)], [24, 149]);
    expect(l.totalHeight, 234);
  });

  test('가려는 곳 펴기는 접힌 문화권부터 편다', () {
    final l = build(sphereLayout());
    final next = l.revealFor(3);
    expect(next.foldedSpheres, isEmpty);
    expect(l.setViewState(next), isTrue);
    expect(l.isVisible(3), isTrue);
  });

  test('끈 트랙(필터)만 남은 문화권은 머리 단도 없다', () {
    final l = build(sphereLayout());
    expect(l.offTrack(2, true), isTrue);
    expect(l.sphereHeadTop(1), -1);
    expect(l.totalHeight, 149);
  });

  group('머리 단 밑 시대 · 주기 줄(4단계 과제 3)', () {
    test('줄 있는 펼친 문화권은 트랙이 줄 높이 29만큼 내려서고, 아래 문화권도 그만큼 밀린다', () {
      final json = sphereLayout()..['sphereLines'] = epochAndCycle('east-asia');
      final l = build(json);
      // 동아시아: 머리 단 0 · 상자 20 + 29 = 49 · 그 아래 4 뒤 53에 트랙 1(53 ~ 178). 초원(접힘): 6 뒤 184에 머리 단 하나 — 전체 204.
      expect(l.sphereHeadTop(0), 0);
      expect(l.sphereHeadHeight(0), 49);
      expect(l.trackTop(0), 53);
      expect(tops(l).sublist(0, 3), [57, 94, 134]);
      expect(l.sphereHeadTop(1), 184);
      expect(l.sphereHeadHeight(1), 20);
      expect(l.totalHeight, 204);
      // 접으면 머리 단 20 하나로(줄 높이 없음) — 줄 없는 배치와 같은 자리.
      expect(l.foldSphere('east-asia', true), isTrue);
      final bare = build(sphereLayout())..foldSphere('east-asia', true);
      expect(placed(l), placed(bare));
    });

    test('접힌 문화권은 줄이 있어도 머리 단 20뿐 — 펴면 그때 29가 든다', () {
      final json = sphereLayout()..['sphereLines'] = epochAndCycle('steppe');
      final l = build(json);
      expect(placed(l), placed(build(sphereLayout())), reason: '초원(접힘)의 줄은 쌓기에 들지 않는다');
      expect(l.sphereHeadHeight(1), 20);
      expect(l.foldSphere('steppe', false), isTrue);
      expect(l.sphereHeadTop(1), 155);
      expect(l.sphereHeadHeight(1), 49);
      expect(l.trackTop(1), 155 + 49 + 4);
      expect(l.totalHeight, 208 + 85);
    });

    test('쌓기에 드는 줄이 없는 자료(때 없는 시대 · 깨진 주기 · 모르는 문화권의 줄과 사람 띠)는 쌓기가 4단계 전과 같다', () {
      final json = sphereLayout()
        ..['sphereLines'] = [
          {'kind': 1, 'sphere': 'nowhere', 'start': 1000, 'end': 9000, 'name': '별여울 임금', 'data': '[{"uid":"a","cell":0},{"uid":"b","cell":2}]'},
          {'kind': 2, 'sphere': 'east-asia', 'start': 0, 'end': 0, 'name': '때 없는 시대'},
          {'kind': 3, 'sphere': 'east-asia', 'data': '{"names":'},
          ...epochAndCycle('nowhere'),
        ];
      for (final steppeOpen in [false, true]) {
        final l = build(json), bare = build(sphereLayout());
        if (steppeOpen) {
          l.foldSphere('steppe', false);
          bare.foldSphere('steppe', false);
        }
        expect(placed(l), placed(bare));
        expect([l.sphereHeadHeight(0), l.sphereHeadHeight(1)], [20, 20]);
      }
    });

    test('사람 띠(과제 4 걸음 1): 펼친 문화권은 줄 수 × 16을 더 내려선다 — 겹치는 둘은 두 줄(16 × 2 + 2), 시대 · 주기 줄과 함께면 그 밑에 · 접히면 머리 단 20뿐', () {
      Map<String, Object> person(String name, int start, int end, [String sphere = 'east-asia']) =>
          {'kind': 1, 'sphere': sphere, 'start': start, 'end': end, 'name': name, 'uid': 'fig-$name', 'data': '[{"uid":"a","cell":0},{"uid":"b","cell":2}]'};
      // 분 0(1970년) ~ 2000만 분(약 38해) · 겹치는 둘 → 두 줄. 2해 넘게 떨어진 셋째는 첫 줄에.
      final two = build(sphereLayout()
        ..['sphereLines'] = [person('가', 0, 20000000), person('나', 10000000, 30000000), person('다', 22000000, 40000000)]);
      expect(two.sphereRowsOf(0).lanes, 2);
      expect([for (final p in two.sphereRowsOf(0).persons) p.lane], [0, 1, 0]);
      expect(two.sphereHeadHeight(0), 20 + 16 * 2 + 2);
      expect(two.trackTop(0), 20 + 34 + 4);
      expect(two.sphereHeadTop(1), 155 + 34);
      expect(two.totalHeight, 175 + 34);
      // 시대 · 주기 줄 + 사람 한 줄: 14 + 13 + 16 + 2 = 45.
      final all = build(sphereLayout()..['sphereLines'] = [...epochAndCycle('east-asia'), person('가', 0, 20000000)]);
      expect(all.sphereHeadHeight(0), 65);
      expect(all.sphereRowsOf(0).personTop, 27);
      expect(all.trackTop(0), 69);
      // 접힌 초원의 사람 띠는 쌓기에 들지 않고, 펴면 그때 18이 든다.
      final steppe = build(sphereLayout()..['sphereLines'] = [person('초원 임금', 0, 20000000, 'steppe')]);
      expect(placed(steppe), placed(build(sphereLayout())));
      expect(steppe.foldSphere('steppe', false), isTrue);
      expect(steppe.sphereHeadHeight(1), 38);
      expect(steppe.trackTop(1), 155 + 38 + 4);
      // 동아시아를 접으면 사람 띠 높이도 빠진다 — 줄 없는 배치와 같은 자리.
      expect(two.foldSphere('east-asia', true), isTrue);
      expect(placed(two), placed(build(sphereLayout())..foldSphere('east-asia', true)));
    });

    test('흐르는 동안 머리 단 자리가 끊기지 않는다 — 접고 펼 때 머리 단은 제자리, 상자 높이 · 트랙 자리가 한 시계로 흐른다', () {
      final json = sphereLayout()..['sphereLines'] = [...epochAndCycle('east-asia'), ...epochAndCycle('steppe')];
      final l = SceneLayout.fromJson(json); // 움직임 그대로(흐름)
      expect(l.sphereHeadTop(1), 184);
      // 초원 펴기: 초원 머리 단은 184에 그대로, 상자는 20 → 49로, 트랙 2는 늘 머리 단 + 상자 + 4.
      expect(l.foldSphere('steppe', false), isTrue);
      expect(l.flowing, isTrue);
      var lastH = 0.0;
      final frames = flowEach(l, () {
        expect(l.sphereHeadTop(1), closeTo(184, 1e-6));
        final h = l.sphereHeadHeight(1);
        expect(h, greaterThanOrEqualTo(lastH - 1e-9), reason: '상자 높이는 늘기만 한다');
        expect(h, inInclusiveRange(20, 49));
        expect(l.trackTop(1), closeTo(184 + h + 4, 1e-6));
        lastH = h;
      });
      expect(frames, greaterThan(5), reason: '여러 장면에 걸쳐 흐른다');
      expect(lastH, 49);
      // 동아시아 접기: 동아시아 머리 단은 0에 그대로, 초원 머리 단은 위로 이어서 흐른다(장면 사이에 크게 뛰지 않음).
      expect(l.foldSphere('east-asia', true), isTrue);
      var lastTop = l.sphereHeadTop(1);
      flowEach(l, () {
        expect(l.sphereHeadTop(0), closeTo(0, 1e-6));
        expect(l.trackTop(0), closeTo(l.sphereHeadTop(0) + l.sphereHeadHeight(0) + 4, 1e-6));
        final top = l.sphereHeadTop(1);
        expect((top - lastTop).abs(), lessThan(20), reason: '초원 머리 단이 한 장면에 뛰지 않는다');
        lastTop = top;
      });
      expect(l.sphereHeadHeight(0), 20);
      expect(l.sphereHeadTop(1), 26);
    });

    test('뼈대를 갈아 끼울 때(replaceWith)도 머리 단은 옛 자리에서 흐른다 — 줄이 새로 든 문화권의 상자가 자란다', () {
      final l = SceneLayout.fromJson(sphereLayout());
      final fresh = SceneLayout.fromJson(sphereLayout()..['sphereLines'] = epochAndCycle('east-asia'));
      l.replaceWith(fresh, view: l.viewState, from: l.snapshot());
      expect(l.flowing, isTrue);
      flowEach(l, () {
        expect(l.sphereHeadTop(0), closeTo(0, 1e-6));
        expect(l.trackTop(0), closeTo(l.sphereHeadHeight(0) + 4, 1e-6));
      });
      expect(l.sphereHeadHeight(0), 49);
      expect(l.trackTop(0), 53);
    });
  });

  group('머리 단 고정(4단계 과제 3 걸음 4 — sphereHeadBox)', () {
    /// 그림판 위가 50인 보기 — 몸통 [top]만큼 내려 봄.
    SceneView view(double top) => SceneView()
      ..head = 50
      ..top = top;

    test('줄 있는 펼친 문화권: 제자리가 그림판 위보다 아래면 제자리 · 위로 지나가면 그림판 위에 붙고 · 문화권 끝이 다가오면 밀려 올라간다', () {
      // 동아시아: 머리 단 0 · 상자 49 · 트랙 1 53 ~ 178(문화권 끝). 초원(접힘): 184.
      final l = build(sphereLayout()..['sphereLines'] = epochAndCycle('east-asia'));
      expect(l.sphereBottom(0), 178);
      expect(l.sphereHeadBox(0, view(0)), (top: 50.0, height: 49.0, stuck: false), reason: '제자리(그림판 위와 같은 자리)');
      expect(l.sphereHeadBox(0, view(30)), (top: 50.0, height: 49.0, stuck: true), reason: '제자리 20 → 그림판 위 50에 붙음');
      expect(l.sphereHeadBox(0, view(79)), (top: 50.0, height: 49.0, stuck: true), reason: '문화권 끝 149 − 49 = 100 — 아직 붙은 채');
      // 문화권 끝(50 + 178 − 150 = 78)에 상자 아랫변이 닿은 채 밀려 올라간다: 78 − 49 = 29.
      expect(l.sphereHeadBox(0, view(150)), (top: 29.0, height: 49.0, stuck: true));
      expect(l.sphereHeadBox(0, view(200)), (top: -21.0, height: 49.0, stuck: true), reason: '문화권이 다 지나가면 상자도 그림판 위로 사라진다(아랫변 28 < 50)');
      // 정수 px — 몸통 자리가 소수여도 상자는 정수 자리.
      expect(l.sphereHeadBox(0, view(30.4))!.top, 50);
      expect(l.sphereHeadBox(0, view(150.4))!.top, (50 + 178 - 150.4).roundToDouble() - 49);
    });

    test('줄 없는 문화권 · 접힌 문화권 · 머리 단이 없는 문화권은 늘 제자리(옛 모습 그대로)', () {
      final bare = build(sphereLayout());
      expect(bare.sphereHeadBox(0, view(30)), (top: 20.0, height: 20.0, stuck: false), reason: '줄 없는 문화권은 붙지 않는다(감독 몫)');
      // 초원의 줄은 초원이 접힌 동안 붙지 않는다 — 접힌 머리 단 155(제자리 50 + 155 − 190 = 15).
      final steppe = build(sphereLayout()..['sphereLines'] = epochAndCycle('steppe'));
      expect(steppe.sphereHeadBox(1, view(190)), (top: 15.0, height: 20.0, stuck: false));
      // 펴면 붙는다: 머리 단 155 · 상자 49 · 트랙 2 208 ~ 293.
      expect(steppe.foldSphere('steppe', false), isTrue);
      expect(steppe.sphereBottom(1), 293);
      expect(steppe.sphereHeadBox(1, view(190)), (top: 50.0, height: 49.0, stuck: true));
      expect(steppe.sphereHeadBox(0, view(190)), (top: -140.0, height: 20.0, stuck: false), reason: '줄 없는 동아시아는 제자리(화면 위)');
      // 끈 트랙만 남은 문화권은 머리 단이 없다.
      expect(steppe.offTrack(2, true), isTrue);
      expect(steppe.sphereHeadBox(1, view(0)), isNull);
      expect(steppe.sphereBottom(1), -1);
    });

    test('사람 띠만 있는 문화권도 붙고, 흐르는 동안에는 흐르는 상자 높이 · 트랙 끝으로 셈한다', () {
      final l = SceneLayout.fromJson(sphereLayout()
        ..['sphereLines'] = [
          {'kind': 1, 'sphere': 'east-asia', 'start': 0, 'end': 20000000, 'name': '가', 'uid': 'fig-가', 'data': '[{"uid":"a","cell":0},{"uid":"b","cell":2}]'},
        ]);
      // 동아시아: 상자 20 + 16 + 2 = 38 · 트랙 1 42 ~ 167.
      expect(l.sphereHeadBox(0, view(10)), (top: 50.0, height: 38.0, stuck: true));
      // 초원 펴기(흐름) — 동아시아는 위라 그대로, 초원은 펴는 동안 제자리(줄이 없어 붙지 않음).
      expect(l.foldSphere('steppe', false), isTrue);
      flowEach(l, () {
        expect(l.sphereHeadBox(0, view(10)), (top: 50.0, height: 38.0, stuck: true));
        expect(l.sphereHeadBox(1, view(200))!.stuck, isFalse);
      });
      // 동아시아를 접으면(흐르는 동안에도) 붙지 않는다 — 접힌 문화권은 제자리.
      expect(l.foldSphere('east-asia', true), isTrue);
      flowEach(l, () => expect(l.sphereHeadBox(0, view(10)), (top: 40.0, height: l.sphereHeadHeight(0).roundToDouble(), stuck: false)));
    });
  });

  test('보기 상태 값: 문화권 접힘은 쌓기에 들고 글자 id로 넣고 뺀다', () {
    const a = ViewState();
    final b = a.withSphereFolded('steppe', true);
    expect(b.isSphereFolded('steppe'), isTrue);
    expect(a.stacksSameAs(b), isFalse);
    expect(b.withSphereFolded('steppe', false), a);
    expect(identical(b.withSphereFolded('steppe', true).foldedSpheres, b.foldedSpheres), isTrue);
  });
}

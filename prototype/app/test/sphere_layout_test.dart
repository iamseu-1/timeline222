import 'package:archive_prototype/scene/layout.dart'; // view_state.dart를 다시 내보낸다
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart';

// 문화권 머리 단(리메이크 조각 ② · 설계 4-6 #1 A · #5 B · 계약 3절 머리의 상자).
// 뼈대(support/fold_rows.dart의 twoTrackLayout)에 문화권을 얹는다: 트랙 1 = 동아시아(처음 펼침), 트랙 2 = 초원.
// 트랙 1의 높이 125 · 트랙 2의 높이 85(문화권 없이는 0 · 125에 이어 쌓여 전체 210 — 리메이크 2부의 두 장 꼬리표 띠 32).
// 문화권이 있으면: 머리 단 20 · 펼친 문화권은 그 아래 4 뒤에 트랙 · 문화권 사이 6 · 접힌 문화권은 머리 단 20뿐.

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

void main() {
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

  test('보기 상태 값: 문화권 접힘은 쌓기에 들고 글자 id로 넣고 뺀다', () {
    const a = ViewState();
    final b = a.withSphereFolded('steppe', true);
    expect(b.isSphereFolded('steppe'), isTrue);
    expect(a.stacksSameAs(b), isFalse);
    expect(b.withSphereFolded('steppe', false), a);
    expect(identical(b.withSphereFolded('steppe', true).foldedSpheres, b.foldedSpheres), isTrue);
  });
}

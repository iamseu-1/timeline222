import 'package:archive_prototype/scene/layout.dart'; // view_state.dart를 다시 내보낸다
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart';

// 보기 상태에 따른 줄 쌓기 — 트랙 접기 · 민족 접기 · 트랙 끔 · 밀도와 조감 · 자동 조감(명세 05 5절 · 7절 · 계약 3-1절).
// 뼈대(support/fold_rows.dart): 트랙 1은 줄 0 · 1 · 2(민족 묶음 하나 — 첫 줄 0 · 셋), 트랙 2는 줄 3 · 4(묶음 첫 줄 3 · 둘).
// 칸 층이 없어 띠 안이 이름 색줄과 사건 칸뿐이다(리메이크 2부 두 장 꼬리표 — 자동 밀도는 글줄 하나 · 기간 막대는 '넉넉하게'에서만): 띠 14 + 18 = 32,
// 줄의 몫은 첫 보이는 줄 0 + 줄 위 틈 5 + 32 = 37 · 그다음 3 + 5 + 32 = 40.
// 트랙 1 = 4 + 37 + 40 + 40 + 4 = 125, 트랙 2 = 4 + 37 + 40 + 4 = 85, 트랙끼리는 틈 없이 이어 쌓인다.

List<double> tops(SceneLayout l) => [for (int r = 0; r < l.rowCount; r++) l.rowTop(r)];
List<double> heights(SceneLayout l) => [for (int r = 0; r < l.rowCount; r++) l.geo(r).height];

SceneLayout build() => SceneLayout.fromJson(twoTrackLayout())..reduceMotion = true;

void main() {
  // 이 파일의 손셈 자리는 민족 머리 줄이 없는 쌓기(0.1.0) 기준이다 — 머리 줄(0.1.1 감독 고름 나 · 트랙 첫 줄 묶음마다 +14)의 쌓기는 gutter_test가 본다.
  setUp(() => PaintPick.people = false);
  tearDown(PaintPick.reset);
  group('보기 상태 값', () {
    test('묶음의 열쇠는 트랙 · 첫 줄 · 깊이 · 종류로 하나씩 갈린다', () {
      // 지금 연표는 민족 id를 쓰지만 {op:layout}의 groups에는 id가 없다. 같은 줄에서 시작하는 겹친 묶음
      // (민족 · 하위 민족 · 문화)을 서로 가리려면 깊이와 종류까지 넣어야 한다.
      expect(ViewState.groupKey(1, 1, 0, 0), '1|1:0:0');
      expect(ViewState.groupKey(1, 1, 1, 0), isNot(ViewState.groupKey(1, 1, 0, 0)));
      expect(ViewState.groupKey(1, 1, 0, 2), isNot(ViewState.groupKey(1, 1, 0, 0)));
      expect(ViewState.groupKey(2, 1, 0, 0), isNot(ViewState.groupKey(1, 1, 0, 0)));
    });

    test('대범위 가지의 열쇠는 지금 연표와 같은 `<트랙 id>|__scope:<uid>`다', () {
      // 지금 연표의 `peopleKey`(js 357) = `${tr.id}|${gp.key}`이고, 가지의 묶음 이름은 `__scope:<uid>`다.
      // 가지는 드는 줄이 이어져 있지 않고 켤 때마다 생겼다 사라지므로 첫 줄로 가릴 수 없다 — 그래서 규칙을 넓혔다.
      expect(ViewState.variantGroupKey(1, '__scope:mw/scope-warlords'), '1|__scope:mw/scope-warlords');
      expect(ViewState.variantGroupKey(2, '__scope:s'), isNot(ViewState.variantGroupKey(1, '__scope:s')));
      // 두 꼴은 `|` 뒤의 모양이 달라 부딪치지 않는다.
      expect(ViewState.variantGroupKey(1, '__scope:s'), isNot(ViewState.groupKey(1, 0, 0, 2)));
      // 접고 펴는 길은 민족 묶음과 하나다.
      final folded = const ViewState().withGroupFolded(ViewState.variantGroupKey(1, '__scope:s'), true);
      expect(folded.isGroupFolded('1|__scope:s'), isTrue);
      expect(folded.isGroupFolded(ViewState.groupKey(1, 0, 0, 2)), isFalse);
    });

    test('넣고 빼면 새 값이 나오고, 같은 값을 또 넣으면 그대로다', () {
      const a = ViewState();
      final b = a.withTrackFolded(3, true);
      expect(b.foldedTracks, {3});
      expect(a.foldedTracks, isEmpty, reason: '불변 값 — 옛 값은 그대로');
      expect(identical(b.withTrackFolded(3, true).foldedTracks, b.foldedTracks), isTrue);
      expect(b.withTrackFolded(3, false), a);
    });

    test('펼친 소속 · 켠 대범위는 줄을 옮겨 쌓는다(계약 3-2절의 변형)', () {
      const a = ViewState();
      final b = a.copyWith(expandedHosts: {7});
      expect(a == b, isFalse);
      expect(a.stacksSameAs(b), isFalse, reason: '변형은 줄을 옮겨 쌓는다');
      final l = build();
      final version = l.stackVersion;
      expect(l.setViewState(b), isTrue, reason: '달라진 것은 맞다');
      expect(l.stackVersion, greaterThan(version), reason: '다시 쌓았다');
      // 저장소에 그 변형이 없으면 줄은 그대로다(켠 것이 하나도 없다).
      expect(l.variantKeys, isEmpty);
    });

    test('선반에 둔 그릇(과제 7 걸음 3)도 줄 쌓기를 바꾼다 — 견줌 · stacksSameAs · 넣고 빼기 · 그릇을 꺼도 기억은 남는다', () {
      const a = ViewState(openScopes: {'s'});
      final b = a.withScopeShelved('s', true);
      expect(b.shelvedScopes, {'s'});
      expect(a.shelvedScopes, isEmpty, reason: '불변 값 — 옛 값은 그대로');
      expect(a == b, isFalse);
      expect(a.stacksSameAs(b), isFalse, reason: '켜는 변형(scope: ↔ shelf:)이 바뀐다');
      expect(identical(b.withScopeShelved('s', true), b), isTrue, reason: '바뀌는 것이 없으면 그 값 그대로');
      expect(identical(a.withScopeShelved('s', false), a), isTrue);
      expect(b.withScopeShelved('s', false), a);
      // 차례는 보지 않는다 · 같은 값이면 해시도 같다.
      const x = ViewState(shelvedScopes: {'p', 'q'}), y = ViewState(shelvedScopes: {'q', 'p'});
      expect(x == y, isTrue);
      expect(x.stacksSameAs(y), isTrue);
      expect(x.hashCode, y.hashCode);
      // 그릇을 끄고 켜는 길(withScopeOpen · copyWith)은 선반 기억을 건드리지 않는다.
      expect(b.withScopeOpen('s', false).shelvedScopes, {'s'});
      expect(b.copyWith(openScopes: const {}).shelvedScopes, {'s'});
      // 보기 상태에 넣으면 다시 쌓는다 — 저장소에 그 선반 변형이 없으면 켜는 것은 없다.
      final l = build();
      final version = l.stackVersion;
      expect(l.setViewState(b), isTrue);
      expect(l.stackVersion, greaterThan(version));
      expect(l.variantKeys, isEmpty);
      expect(l.setViewState(b.withScopeShelved('s', true)), isFalse, reason: '같은 값');
    });

    test('접거나 편 트랙이 하나뿐이면 그 트랙을 알려 준다(누른 트랙의 위를 붙잡으려고)', () {
      const a = ViewState(foldedTracks: {1});
      expect(ViewState.foldToggled(a, a.withTrackFolded(2, true)), 2);
      expect(ViewState.foldToggled(a, a.withTrackFolded(1, false)), 1);
      expect(ViewState.foldToggled(a, const ViewState(foldedTracks: {2, 3})), -1, reason: '한꺼번에 접으면 누른 트랙이 없다');
      expect(ViewState.foldToggled(a, a.copyWith(offTracks: {5})), -1);
    });
  });

  group('트랙 접기', () {
    test('접힌 트랙은 높이 34로 굳고 그 줄은 모두 안 보인다', () {
      final l = build();
      expect(l.setViewState(const ViewState(foldedTracks: {1})), isTrue);
      expect(l.trackHeight(0), 34);
      expect(l.trackTop(0), 0);
      expect(l.trackTop(1), 34, reason: '아래 트랙이 바로 붙어 올라온다');
      expect(l.totalHeight, 34 + 85);
      for (final r in [0, 1, 2]) {
        expect(l.isVisible(r), isFalse);
        expect(l.rowTop(r), -1);
      }
      expect(l.isVisible(3), isTrue);
      expect(l.isTrackFolded(1), isTrue);
      expect(l.isTrackFolded(2), isFalse);
    });

    test('모두 접기 · 모두 펴기', () {
      final l = build();
      expect(l.allFolded, isFalse);
      expect(l.foldAll(true), isTrue);
      expect(l.allFolded, isTrue);
      expect(l.totalHeight, 68);
      expect(l.foldAll(true), isFalse, reason: '이미 다 접혔다');
      expect(l.foldAll(false), isTrue);
      expect(l.totalHeight, 125 + 85);
    });

    test('가는 막대의 자리는 5 + 단 × 8, 조감은 상자 안에서 가운데(명세 05 5.3 · 실측 9.2)', () {
      final l = build();
      expect([l.miniTop(0), l.miniTop(1), l.miniTop(2)], [5, 13, 21]);
      expect(l.foldedHeight, 34);
      expect(l.miniHeight, 6);
      // 접힌 민족 줄(30)에서도 같은 자리다.
      expect(l.miniTop(0, l.foldedGroupHeight), 5);
      l.setConditions(const ViewConditions(density: 2));
      expect(l.foldedHeight, 22);
      expect(l.miniHeight, 3);
      expect([l.miniTop(0), l.miniTop(1), l.miniTop(2)], [5.5, 9.5, 13.5]);
      expect(l.miniTop(0, l.foldedGroupHeight), 1.5, reason: '접힌 민족 줄(14)에서는 G_BIRD.miniTop 1.5');
    });
  });

  group('민족 접기', () {
    test('묶음의 줄들이 첫 줄 자리에 한 줄(30 · 탭 0)로 합쳐진다', () {
      final l = build();
      final track = l.tracks[0], group = track.groups.single;
      expect(l.groupKeyOf(track, group), '1|0:0:0');
      expect(l.foldGroup(track, group, true), isTrue);
      expect(l.isGroupFolded(group), isTrue);
      expect(l.isFoldedGroupRow(0), isTrue);
      expect(l.mergedGroups, {0: 3});

      expect(l.geo(0).height, 30, reason: '첫 보이는 줄이라 틈 0 · 접힌 민족 줄은 탭도 0');
      expect(l.geo(0).bandHeight, 30);
      expect(l.tabOf(0), 0);
      for (final r in [1, 2]) {
        expect(l.isVisible(r), isFalse, reason: '합쳐진 줄에 들던 줄은 안 보인다');
        expect(l.rowTop(r), -1);
        expect(l.isMergedAway(r), isTrue);
      }
      expect(l.trackHeight(0), 4 + 30 + 4);
      expect(l.trackTop(1), 38);
      expect(l.totalHeight, 38 + 85);
      expect(l.visibleRowCount(0), 1);
    });

    test('접어서 보이는 줄이 줄어도 자동 밀도의 글줄은 머리 한 줄이다(리메이크 2부 — 예전: 여섯 이하면 둘)', () {
      final l = SceneLayout.fromJson(sevenRowLayout())..reduceMotion = true;
      final track = l.tracks[0], group = track.groups.firstWhere((g) => g.firstRow == 1); // 줄 1~3
      expect(l.visibleRowCount(0), 7);
      expect(l.baseLines(0), 1);
      expect(l.nameSize(0), 12.5);
      // 사건 글은 글줄 수와 상관없이 9.5(꼬리표 갈래 E — 머리 이름 9와 한 계통 · 예전 11.5 · 12).
      expect(l.eventSize(0), 9.5);

      expect(l.foldGroup(track, group, true), isTrue);
      expect(l.visibleRowCount(0), 5, reason: '7줄 가운데 셋이 한 줄로 — 5줄');
      expect(l.baseLines(0), 1, reason: '두 장 꼬리표의 사건 칸은 한 줄 — 줄이 여섯 이하가 되어도 그대로');
      expect(l.nameSize(0), 12.5);
      expect(l.eventSize(0), 9.5);
      expect(l.geo(0).textLines, 1);
    });

    test('접힌 묶음 안의 민족 경계는 틈을 벌리지 않는다', () {
      // 줄 3이 새 묶음의 첫 줄이지만 줄 1~3이 한 줄로 합쳐지면 그 경계는 사라진다.
      final l = SceneLayout.fromJson(sevenRowLayout())..reduceMotion = true;
      final track = l.tracks[0];
      final outer = track.groups.firstWhere((g) => g.firstRow == 1);
      expect(l.geo(4).bandTop, 3 + 5, reason: '접기 전: 보통 틈 3 + 줄 위 틈 5');
      l.foldGroup(track, outer, true);
      expect(l.geo(4).bandTop, 3 + 5, reason: '합쳐진 줄 안의 경계는 세지 않는다 — 민족 틈 14가 붙지 않는다');
    });
  });

  group('가려는 곳 펴기(revealFor)', () {
    // 트랙 하나에 줄 여섯. 줄 1~3은 민족 묶음, 줄 4는 줄 1의 소속(변형 `host:h1`), 줄 5는 줄 4의 소속(변형 `host:h2`) —
    // 겹겹으로 숨은 줄까지 한 번에 펴는지 본다(지금 연표의 `focusOn` ③은 상위 사슬을 끝까지 따라 올라간다).
    Map<String, dynamic> nested() => {
      'packs': [
        {'id': 1, 'name': '별여울 기록집', 'events': 0},
      ],
      'tracks': [
        {
          'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'color': 0xc27a45, 'rail_levels': 2,
          'rows': [
            {...foldRow(0)},
            {...foldRow(1, groupStart: 1)},
            {...foldRow(2)},
            {...foldRow(3)},
            {...foldRow(4, kind: 1), 'variant': 1},
            {...foldRow(5, kind: 1), 'variant': 2},
          ],
          'groups': [
            {'depth': 0, 'first': 1, 'count': 3, 'name': '별여울 사람', 'color': 0xc27a45, 'kind': 0},
          ],
        },
      ],
      'epochs': <Map<String, dynamic>>[],
      'variants': [
        {
          'id': 1, 'key': 'host:h1', 'kind': 1, 'track': 1, 'band': 11, 'uid': '', 'name': '은륜 제국',
          'rows': [
            {'row': 4, 'after': 1, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
            {'row': 2, 'after': 4, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
          ],
          'groups': <Map<String, dynamic>>[],
        },
        {
          'id': 2, 'key': 'host:h2', 'kind': 1, 'track': 1, 'band': 22, 'uid': '', 'name': '파도문 자치령',
          'rows': [
            {'row': 5, 'after': 4, 'ord': 0, 'new': 1, 'scope_pad': 0, 'group_start': 0},
            {'row': 2, 'after': 5, 'ord': 0, 'new': 0, 'scope_pad': 0, 'group_start': 0},
          ],
          'groups': <Map<String, dynamic>>[],
        },
      ],
    };

    test('볼 수 있는 줄은 지금 보기 상태를 그대로 돌려준다', () {
      final l = build();
      expect(identical(l.revealFor(0), l.viewState), isTrue);
      expect(identical(l.revealFor(-1), l.viewState), isTrue, reason: '없는 줄도 그대로');
      expect(identical(l.revealFor(99), l.viewState), isTrue);
    });

    test('접힌 트랙 · 그 줄을 감춘 접힌 민족을 한 번에 편다', () {
      final l = SceneLayout.fromJson(sevenRowLayout())..reduceMotion = true;
      final track = l.tracks[0];
      final outer = track.groups.firstWhere((g) => g.firstRow == 1); // 줄 1~3
      l.foldTrack(track.id, true);
      l.foldGroup(track, outer, true);
      expect(l.isVisible(2), isFalse);

      final next = l.revealFor(2);
      expect(next.isTrackFolded(track.id), isFalse);
      expect(next.isGroupFolded(l.groupKeyOf(track, outer)), isFalse);
      // 한 번만 넣으면 다시 쌓기도 한 번이다.
      final version = l.stackVersion;
      expect(l.setViewState(next), isTrue);
      expect(l.stackVersion, version + 1);
      expect(l.isVisible(2), isTrue);
    });

    test('합쳐진 줄 자신으로 갈 때는 그 묶음을 펴지 않는다', () {
      final l = SceneLayout.fromJson(sevenRowLayout())..reduceMotion = true;
      final track = l.tracks[0];
      final outer = track.groups.firstWhere((g) => g.firstRow == 1);
      l.foldGroup(track, outer, true);
      expect(l.isFoldedGroupRow(1), isTrue);
      expect(identical(l.revealFor(1), l.viewState), isTrue, reason: '줄 1은 이미 보인다 — 접힌 민족 줄 그대로');
    });

    test('켜지 않은 변형의 줄은 그 변형을, 겹겹이면 얹히는 줄의 변형까지 켠다', () {
      final l = SceneLayout.fromJson(nested())..reduceMotion = true;
      expect(l.isVisible(4), isFalse);
      expect(l.isVisible(5), isFalse);

      // 줄 4는 변형 하나만 켜면 보인다.
      final one = l.revealFor(4);
      expect(one.expandedHosts, {11});
      // 줄 5는 제 변형(host:h2)과 그것이 얹히는 줄 4의 변형(host:h1)이 함께 켜져야 보인다.
      final two = l.revealFor(5);
      expect(two.expandedHosts, {11, 22});
      expect(l.setViewState(two), isTrue);
      expect(l.isVisible(5), isTrue);
      expect(l.isVisible(4), isTrue);
      expect(l.variantKeys, ['host:h1', 'host:h2']);
    });

    test('변형의 줄이 접힌 민족 안에 있으면 그 묶음도 함께 편다', () {
      final l = SceneLayout.fromJson(nested())..reduceMotion = true;
      final track = l.tracks[0];
      final group = track.groups.single; // 줄 1~3
      l.foldGroup(track, group, true);
      // 줄 4는 줄 1(묶음의 첫 줄) 아래에 얹히지만, 줄 5는 줄 4를 거쳐 얹힌다.
      final next = l.revealFor(5);
      expect(next.expandedHosts, {11, 22});
      expect(l.setViewState(next), isTrue);
      expect(l.isVisible(5), isTrue);
    });
  });

  group('트랙 끔(필터)', () {
    test('끈 트랙은 줄이 빠지고 아래가 올라온다 — 흐르지 않는다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      expect(l.setViewState(const ViewState(offTracks: {1})), isTrue);
      expect(l.flowing, isFalse, reason: '자료집 끔과 같은 길');
      expect(l.trackTop(0), -1);
      expect(l.trackHeight(0), 0);
      expect(l.trackTop(1), 0);
      expect(l.rowTop(0), -1);
      expect(l.rowTop(3), 4);
      expect(l.totalHeight, 85);
      expect(l.isTrackOff(1), isTrue);
    });

    test('접기는 흐르고, 끔은 흐르지 않는다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      expect(l.setViewState(const ViewState(foldedTracks: {1})), isTrue);
      expect(l.flowing, isTrue);
      l.finishFlow();
      expect(l.setViewState(const ViewState(foldedTracks: {1}, offTracks: {2})), isTrue);
      expect(l.flowing, isFalse);
    });
  });

  group('밀도와 조감', () {
    test('조감은 줄이 띠 하나뿐이고 칸 · 글줄 · 막대 · 탭이 모두 빠진다(명세 05 7.2)', () {
      final l = build();
      l.setConditions(const ViewConditions(density: 2));
      expect(l.bird, isTrue);
      expect(l.birdShape, BirdShape.a);
      final g = l.geo(1);
      expect(g.bandHeight, BirdShape.a.bandHeight);
      expect(g.textLines, 1);
      expect(g.lineH, BirdShape.a.bandHeight, reason: '글줄 하나가 띠 전체 — 네모 · 승계선이 닿는 곳이 띠의 세로 가운데');
      expect([g.dynastyTop, g.leaderTop, g.cabinetTop, g.railTop, g.organTop, g.figTop, g.depTop, g.zoneTop, g.hemTop], everyElement(-1.0));
      expect(g.railLevels, 0);
      expect(l.tabOf(1), 0);
      // 트랙 위아래 4 · 줄 사이 6 · 민족 경계 +6.
      expect(l.trackHeight(0), 4 + 21 + 6 + 21 + 6 + 21 + 4);
      expect(l.trackHeight(1), 4 + 21 + 6 + 21 + 4);
      expect(l.totalHeight, 83 + 56);
      expect(l.nameSize(1), 10.5);
      expect(l.eventSize(1), 10);
    });

    test('모양 c는 띠가 8px이다', () {
      final l = build();
      l.setConditions(const ViewConditions(density: 2, birdShape: BirdShape.c));
      expect(l.geo(1).bandHeight, 8);
      expect(l.trackHeight(0), 4 + 8 + 6 + 8 + 6 + 8 + 4);
      expect(l.totalHeight, 44 + 30);
      expect(BirdShape.c.name, isFalse);
      expect(BirdShape.c.dots, isFalse);
      expect(BirdShape.a.dots, isTrue);
      expect(BirdShape.b.dots, isFalse);
    });

    test('밀도가 정하는 글자 크기(명세 05 7.1 — 사건 글은 꼬리표 갈래 E에서 조감 10 · 그 밖 9.5)', () {
      final l = build();
      expect(l.nameSize(0), 12.5, reason: '자동은 줄 수와 상관없이 머리 한 줄(리메이크 2부 — 예전: 줄이 셋이면 글줄 둘)');
      expect(l.baseLines(0), 1);
      expect(l.eventSize(0), 9.5);
      l.setConditions(const ViewConditions(density: 1));
      expect([l.nameSize(0), l.eventSize(0), l.baseLines(0)], [12.5, 9.5, 1]);
      l.setConditions(const ViewConditions(density: -1));
      expect([l.nameSize(0), l.eventSize(0), l.baseLines(0)], [13.5, 9.5, 2]);
      l.setConditions(const ViewConditions(density: 2));
      expect([l.nameSize(0), l.eventSize(0), l.baseLines(0)], [10.5, 10, 1]);
    });

    test('자동 조감이 걸리면 밀도는 그대로인 채 조감으로 그린다', () {
      final l = build();
      l.setConditions(const ViewConditions(autoBird: true));
      expect(l.conditions.density, 0, reason: '사람이 고른 밀도는 그대로다');
      expect(l.bird, isTrue);
      expect(l.geo(1).bandHeight, BirdShape.a.bandHeight);
    });
  });

  group('자동 조감의 문턱', () {
    test('들어갈 때 2,600년 · 나갈 때 2,392년(8% 여유)', () {
      final bird = AutoBird()..enable(true, 1000);
      expect(bird.past, isFalse);
      expect(bird.measure(2599), isFalse);
      expect(bird.measure(2600), isTrue);
      expect(bird.measure(2400), isTrue, reason: '들어간 뒤에는 2,392년까지 버틴다');
      expect(bird.measure(2392), isTrue);
      expect(bird.measure(2391), isFalse);
      expect(AutoBird.enterYears, 2600);
      expect(AutoBird.leaveYears, closeTo(2392, 1e-9));
    });

    test('정착 때 한 번만 바뀐다', () {
      final bird = AutoBird()..enable(true, 100);
      expect(bird.settle(3000, density: 0, active: false), isTrue);
      expect(bird.settle(3000, density: 0, active: true), isNull, reason: '이미 걸려 있으면 알릴 것이 없다');
      expect(bird.settle(2500, density: 0, active: true), isNull, reason: '나가는 문턱 위라 그대로');
      expect(bird.settle(100, density: 0, active: true), isFalse);
    });

    test('자동 조감이 걸린 채 다른 밀도를 고르면 문턱 아래로 내려올 때까지 쉰다', () {
      final bird = AutoBird()..enable(true, 3000);
      expect(bird.wanted, isTrue);
      bird.chose(1); // 빽빽하게를 골랐다
      expect(bird.hold, isTrue);
      expect(bird.from, 1);
      expect(bird.settle(3000, density: 1, active: true), isFalse, reason: '쉬는 동안은 조감을 풀어 고른 밀도로');
      expect(bird.settle(100, density: 1, active: false), isNull);
      expect(bird.hold, isFalse, reason: '문턱 아래로 내려오면 쉼이 풀린다');
      expect(bird.settle(3000, density: 1, active: false), isTrue, reason: '다시 넓게 보면 또 조감');
    });

    test('조감을 손으로 고르면 쉼이 풀리고, 자동 조감은 밀도 조감을 건드리지 않는다', () {
      final bird = AutoBird()
        ..enable(true, 3000)
        ..chose(0);
      expect(bird.hold, isTrue);
      bird.chose(2);
      expect(bird.hold, isFalse);
      expect(bird.settle(3000, density: 2, active: false), isNull, reason: '밀도가 조감이면 자동 조감은 나설 일이 없다');
    });

    test('손으로 풀면 쉬고, 끄면 아무 일도 하지 않는다', () {
      final bird = AutoBird()..enable(true, 3000);
      bird.leave();
      expect(bird.wanted, isFalse);
      expect(bird.settle(3000, density: 0, active: true), isFalse);
      bird.enable(false, 3000);
      expect(bird.settle(3000, density: 0, active: false), isNull);
    });
  });
}

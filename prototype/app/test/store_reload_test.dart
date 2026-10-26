import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/motion.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/row_labels.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/tile_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart';
import 'support/pack_scene.dart';
import 'support/tile_builder.dart';

// 저장소를 다시 지었을 때(DLC 더하기 · 빼기 · 판 올리기)의 뼈대 바꾸기와 줄 흐름 — 4단계 1걸음(`docs/설계-아카이브-4단계-1걸음-DLC-앱-안에서.md` 3-3절).
//
// 뼈대(support/fold_rows.dart): 두 장 꼬리표 띠 = 이름 색줄 14 + 사건 칸 18 = 32(리메이크 2부) → 줄의 몫은 첫 줄 37 · 그다음 40, 트랙 = 4 + 몫들 + 4.
// 별여울 갈래(줄 셋) = 125, 해솔 갈래(줄 둘) = 85 → 전체 210.

/// 두 트랙 뼈대에 글자 열쇠를 붙인다(다시 지은 저장소가 주는 꼴).
Map<String, dynamic> keyed() {
  final json = twoTrackLayout();
  final packs = json['packs'] as List, tracks = json['tracks'] as List;
  (packs[0] as Map)['key'] = 'starbrook-pack';
  (packs[1] as Map)['key'] = 'haesol-pack';
  (tracks[0] as Map)['key'] = 'starbrook';
  (tracks[1] as Map)['key'] = 'haesol';
  return json;
}

/// 다시 지은 뼈대: 새 DLC(3번)의 트랙 '은빛 나루 갈래'(줄 둘)가 두 트랙 **사이**에 들어와 줄 번호가 모두 바뀐다.
/// 별여울 갈래는 줄 0~2, 은빛 나루 갈래는 3~4, 해솔 갈래는 5~6이 된다.
Map<String, dynamic> rebuiltWithMiddleTrack() => {
  'packs': [
    {'id': 1, 'name': '별여울 기록집', 'events': 12, 'key': 'starbrook-pack'},
    {'id': 2, 'name': '해솔 기록집', 'events': 8, 'key': 'haesol-pack'},
    {'id': 3, 'name': '은빛 나루 기록집', 'events': 5, 'key': 'silverbay-pack'},
  ],
  'tracks': [
    {
      'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'key': 'starbrook', 'color': 0xc27a45, 'rail_levels': 2,
      'rows': [foldRow(0, groupStart: 1), foldRow(1), foldRow(2)],
      'groups': [
        {'depth': 0, 'first': 0, 'count': 3, 'name': '별여울 사람', 'color': 0xc27a45, 'kind': 0},
      ],
    },
    {
      'id': 3, 'pack': 3, 'ord': 1, 'name': '은빛 나루 갈래', 'key': 'silverbay', 'color': 0x9a8e7c, 'rail_levels': 2,
      'rows': [foldRow(3, groupStart: 1), foldRow(4)],
      'groups': [
        {'depth': 0, 'first': 3, 'count': 2, 'name': '은빛 나루 사람', 'color': 0x9a8e7c, 'kind': 0},
      ],
    },
    {
      'id': 2, 'pack': 2, 'ord': 2, 'name': '해솔 갈래', 'key': 'haesol', 'color': 0x7a95c2, 'rail_levels': 2,
      'rows': [foldRow(5, groupStart: 1), foldRow(6)],
      'groups': [
        {'depth': 0, 'first': 5, 'count': 2, 'name': '해솔 사람', 'color': 0x7a95c2, 'kind': 0},
      ],
    },
  ],
  'epochs': <Map<String, dynamic>>[],
};

/// 다시 지은 뼈대: 남의 줄에 사건만 얹는 DLC(4번)가 들어와 별여울 갈래의 줄이 셋에서 넷으로 **늘었다**(트랙은 그대로).
Map<String, dynamic> rebuiltWithExtraRow() {
  final json = keyed();
  final packs = json['packs'] as List;
  packs.add({'id': 4, 'name': '덧붙인 기록집', 'events': 2, 'key': 'extend-pack'});
  final tracks = json['tracks'] as List;
  (tracks[0] as Map)['rows'] = [foldRow(0, groupStart: 1), foldRow(1), foldRow(2), foldRow(3)];
  ((tracks[0] as Map)['groups'] as List)[0] = {'depth': 0, 'first': 0, 'count': 4, 'name': '별여울 사람', 'color': 0xc27a45, 'kind': 0};
  (tracks[1] as Map)['rows'] = [foldRow(4, groupStart: 1), foldRow(5)];
  ((tracks[1] as Map)['groups'] as List)[0] = {'depth': 0, 'first': 4, 'count': 2, 'name': '해솔 사람', 'color': 0x7a95c2, 'kind': 0};
  return json;
}

List<double> tops(SceneLayout l) => [for (int r = 0; r < l.rowCount; r++) l.rowTop(r)];

/// 장면을 한 번 그린다(결과는 버린다) — 타일 받기 · 그리기 흐름을 돌리는 데만 쓴다.
void paintOnce(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 500));
  recorder.endRecording().dispose();
}

void main() {
  // 이 파일의 손셈 자리는 민족 머리 줄이 없는 쌓기(0.1.0) 기준이다 — 머리 줄(0.1.1 감독 고름 나 · 트랙 첫 줄 묶음마다 +14)의 쌓기는 gutter_test가 본다.
  setUp(() => PaintPick.people = false);
  tearDown(PaintPick.reset);
  group('트랙의 짝짓기 열쇠', () {
    test('글자 id가 있으면 그것, 없으면 DLC 열쇠(없으면 이름)와 트랙 이름', () {
      final withKeys = SceneLayout.fromJson(keyed());
      expect(withKeys.trackIdentity(0), 'k:starbrook');
      final plain = SceneLayout.fromJson(twoTrackLayout());
      expect(plain.trackIdentity(0), 'n:#별여울 기록집|별여울 갈래');
      expect(plain.trackIdentity(1), 'n:#해솔 기록집|해솔 갈래');
      expect(withKeys.packs.first.key, 'starbrook-pack');
      expect(plain.packs.first.key, '', reason: '옛 저장소는 빈 글');
    });
  });

  group('뼈대 바꾸기(다시 지은 저장소)', () {
    test('사이에 들어온 새 트랙은 제자리에서 0에서 자라나고, 남은 트랙의 줄은 옛 자리에서 새 자리로 흐른다', () {
      final l = SceneLayout.fromJson(keyed());
      expect(tops(l), [4, 41, 81, 129, 166]);
      expect(l.totalHeight, 210);
      final version = l.version;

      l.replaceWith(SceneLayout.fromJson(rebuiltWithMiddleTrack()), from: l.snapshot());
      expect(l.packs.map((p) => p.key), ['starbrook-pack', 'haesol-pack', 'silverbay-pack']);
      expect(l.tracks.map((t) => t.key), ['starbrook', 'silverbay', 'haesol']);
      expect(l.rowCount, 7);
      expect(l.enabledPacks, [1, 2, 3], reason: '켠 DLC를 주지 않으면 모두 켠다');
      expect(l.version, isNot(version), reason: '새 저장소 — 옛 판 번호의 타일과 섞이지 않는다');
      expect(l.flowing, isTrue);
      expect(l.stackCause, StackCause.packs);
      // 첫 장면: 별여울 갈래의 줄은 옛 자리 그대로, 해솔 갈래의 줄(이제 5 · 6)도 옛 자리(129 · 166)에서 출발한다.
      expect(tops(l).sublist(0, 3), [4, 41, 81]);
      expect([l.rowTop(5), l.rowTop(6)], [129, 166]);
      expect(l.totalHeight, 210);
      // 새 트랙(은빛 나루 갈래)은 제자리(125)에서 높이 0으로 출발하고 그 줄은 새로 난 줄이다.
      expect(l.trackTop(1), 125);
      expect(l.trackHeight(1), 0);
      expect(l.isBornRow(3), isTrue);
      expect(l.isBornRow(4), isTrue);
      expect(l.isBornRow(0), isFalse);
      expect(l.geo(3).height, 0);
      expect(l.rowShift(5), -85, reason: '옮겨 온 거리 = 옛 자리 − 새 자리(129 − 214)');
      expect(l.rowShift(3), 0, reason: '새로 난 줄은 옮기지 않고 자라나기만 한다');

      l.tickFlow(180);
      final t = SpringSimulation(Motion.spring(MotionToken.move), 0, 1, 0).x(.18);
      expect(l.trackHeight(1), closeTo(85 * t, 1e-9));
      expect(l.rowTop(5), closeTo(129 + (214 - 129) * t, 1e-9));
      expect(l.totalHeight, closeTo(210 + (295 - 210) * t, 1e-9));

      for (int i = 0; i < 12; i++) {
        l.tickFlow(16);
      }
      expect(l.flowing, isFalse);
      expect(tops(l), [4, 41, 81, 129, 166, 214, 251]);
      expect(l.totalHeight, 295);
      expect(l.trackHeight(1), 85);
      expect(l.trackTop(2), 210);
    });

    test('줄이 늘어난 트랙은 있던 줄이 차례로 짝지어지고 늘어난 줄만 새로 난다', () {
      final l = SceneLayout.fromJson(keyed());
      l.replaceWith(SceneLayout.fromJson(rebuiltWithExtraRow()), from: l.snapshot());
      expect(l.rowCount, 6);
      expect(l.flowing, isTrue);
      expect(tops(l).sublist(0, 3), [4, 41, 81], reason: '있던 세 줄은 옛 자리');
      expect(l.isBornRow(3), isTrue, reason: '늘어난 넷째 줄');
      expect([l.rowTop(4), l.rowTop(5)], [129, 166], reason: '해솔 갈래의 줄(이제 4 · 5)은 옛 자리에서');
      l.finishFlow();
      // 별여울 갈래 = 4 + 37 + 40 × 3 + 4 = 165, 해솔 갈래 = 85.
      expect(tops(l), [4, 41, 81, 121, 169, 206]);
      expect(l.totalHeight, 250);
    });

    test('켠 DLC · 보기 상태를 새 번호로 받아 쌓고, 출발 자리를 주지 않으면 흐르지 않는다', () {
      final l = SceneLayout.fromJson(keyed());
      l.replaceWith(SceneLayout.fromJson(rebuiltWithMiddleTrack()), enabled: {1, 2}, view: const ViewState(foldedTracks: {2}));
      expect(l.flowing, isFalse);
      expect(l.enabledPacks, [1, 2]);
      expect(l.isPackEnabled(3), isFalse);
      expect(l.isVisible(3), isFalse, reason: '끈 DLC의 줄');
      expect(l.isTrackFolded(2), isTrue);
      expect(l.trackHeight(2), 34, reason: '접힌 트랙');
      expect(l.trackTop(1), -1, reason: '끈 DLC의 트랙');
    });

    test('옛 뼈대에서 접혀 있던 트랙의 줄은 새로 난 줄처럼 자라난다', () {
      final l = SceneLayout.fromJson(keyed());
      l.setViewState(const ViewState(foldedTracks: {2}));
      l.finishFlow();
      expect(l.trackHeight(1), 34);
      l.replaceWith(SceneLayout.fromJson(rebuiltWithMiddleTrack()), from: l.snapshot());
      expect(l.flowing, isTrue);
      expect(l.trackTop(2), 125, reason: '접혀 있던 해솔 갈래의 옛 자리');
      expect(l.trackHeight(2), 34);
      expect(l.isBornRow(5), isTrue, reason: '접혀 안 보이던 줄은 옛 자리가 없다');
      l.finishFlow();
      expect(l.trackHeight(2), 85, reason: '보기 상태를 주지 않았으니 펴진 채로');
    });
  });

  group('켜고 끄기의 흐름', () {
    test('끄면 그 DLC의 줄이 사라지는 줄이 되어 접히고 아래가 따라 올라온다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      l.enable({1});
      expect(l.flowing, isTrue);
      expect(l.stackCause, StackCause.packs);
      expect(l.isGoneRow(3), isTrue);
      expect(l.isVisible(3), isTrue, reason: '접히는 동안에도 그린다');
      expect(l.rowTop(3), 129, reason: '첫 장면은 옛 자리');
      l.tickFlow(180);
      final t = SpringSimulation(Motion.spring(MotionToken.snap), 0, 1, 0).x(.18);
      expect(l.geo(3).height, closeTo(37 * (1 - t), 1e-9));
      expect(l.totalHeight, closeTo(210 + (125 - 210) * t, 1e-9));
      l.tickFlow(180);
      expect(l.flowing, isFalse);
      expect(l.isVisible(3), isFalse);
      expect(l.totalHeight, 125);
    });

    test('켜면 그 트랙이 0에서 자라난다', () {
      final l = SceneLayout.fromJson(twoTrackLayout());
      l.enable({1});
      l.finishFlow();
      l.enable({1, 2});
      expect(l.flowing, isTrue);
      expect(l.isBornRow(3), isTrue);
      expect(l.trackHeight(1), 0);
      expect(l.trackTop(1), 125);
      l.finishFlow();
      expect(l.trackHeight(1), 85);
      expect(tops(l), [4, 41, 81, 129, 166]);
    });

    test('움직임 줄이기면 바로 새 자리로 간다', () {
      final l = SceneLayout.fromJson(twoTrackLayout())..reduceMotion = true;
      l.enable({1});
      expect(l.flowing, isFalse);
      expect(l.totalHeight, 125);
    });
  });

  group('장면의 뼈대 바꾸기', () {
    test('보관을 비우고 새 판 번호로 타일을 다시 받으며, 새 DLC의 줄이 자라난다', () async {
      final (scene, painter, asked) = makePackScene();
      for (int i = 0; i < 40; i++) {
        paintOnce(painter);
        await pumpEventQueue();
      }
      expect(scene.cache.count, greaterThan(0));
      final before = scene.layout.version, requests = asked.length;
      final fresh = SceneLayout.fromJson({
        'packs': [
          {'id': 1, 'name': '별여울 기록집', 'events': 1250, 'key': 'a'},
          {'id': 2, 'name': '해솔 기록집', 'events': 2, 'key': 'b'},
          {'id': 3, 'name': '은빛 나루 기록집', 'events': 2, 'key': 'c'},
          {'id': 8, 'name': '덧붙인 기록집', 'events': 1, 'key': 'd'},
          {'id': 9, 'name': '새로 더한 기록집', 'events': 4, 'key': 'e'},
        ],
        'tracks': [
          {'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'rows': [packRow(0), packRow(1)]},
          {'id': 2, 'pack': 2, 'ord': 1, 'name': '해솔 갈래', 'rows': [packRow(2), packRow(3)]},
          {'id': 3, 'pack': 3, 'ord': 2, 'name': '은빛 나루 갈래', 'rows': [packRow(4), packRow(5)]},
          {'id': 4, 'pack': 9, 'ord': 3, 'name': '새로 더한 갈래', 'rows': [packRow(6), packRow(7)]},
        ],
        'epochs': [],
      });
      // 왼쪽 칸의 줄 이름도 줄 번호로 받아 둔 것이다 — 바꿔 넣으면 버리고 새 저장소에 다시 묻는다(2026-10-16: 옛 저장소의 이름이 남았던 것).
      final labels = RowLabels()
        ..attach(scene)
        ..accept({0: const [RowLabel(name: '옛 저장소의 나라')]});
      expect(labels.of(0).single.name, '옛 저장소의 나라');
      final labelsBefore = labels.version;
      scene.replaceLayout(fresh, enabled: {1, 2, 3, 8, 9});
      expect(labels.has(0), isFalse, reason: '바꿔 넣은 저장소에서는 같은 번호가 다른 줄이다');
      expect(labels.of(0), isEmpty);
      expect(labels.version, greaterThan(labelsBefore), reason: '그리는 쪽이 이름 자리를 새로 고치게');
      expect(scene.cache.count, 0, reason: '옛 저장소의 타일은 모두 버린다(줄 번호가 다르다)');
      expect(scene.layout.version, isNot(before));
      expect(scene.layout.packs.length, 5);
      expect(scene.layout.enabledPacks, [1, 2, 3, 8, 9]);
      expect(scene.layout.flowing, isTrue);
      expect(scene.layout.isBornRow(6), isTrue);
      expect(scene.layout.trackHeight(3), 0);
      expect(scene.layout.rowTop(0), 0, reason: '있던 줄은 옛 자리');
      expect(scene.selectedEventId, isNull);
      expect(scene.labelOutput, isNull);
      for (int i = 0; i < 25; i++) {
        scene.tick(16);
      }
      expect(scene.layout.flowing, isFalse);
      expect(scene.layout.totalHeight, 142 * 8);
      expect(scene.layout.rowTop(7), 142 * 7);
      for (int i = 0; i < 40; i++) {
        paintOnce(painter);
        await pumpEventQueue();
      }
      expect(asked.length, greaterThan(requests), reason: '새 판 번호로 타일을 다시 받는다');
      expect(asked.last, [1, 2, 3, 8, 9]);
      expect(scene.stats.blanks, 0);
    });

    test('제자리 고쳐 쓰기(keepBefore: 16)면 묶음 0 · 1의 타일 보관이 남고 묶음 2부터는 다시 받는다 · 0이면 모두 · −1이면 아무것도 버리지 않는다', () async {
      // 트랙 셋 × 줄 여덟 = 줄 24(묶음 0 · 1 · 2). 엔진 apply가 셋째 트랙(자리 16부터)만 고쳐 썼다(first_pos 16 — 계약 2-7).
      Map<String, dynamic> threeTracks(int lastColor) => {
        'packs': [
          {'id': 1, 'name': '별여울 기록집', 'events': 1, 'key': 'a'},
          {'id': 2, 'name': '해솔 기록집', 'events': 1, 'key': 'b'},
          {'id': 3, 'name': '은빛 나루 기록집', 'events': 1, 'key': 'c'},
        ],
        'tracks': [
          for (int t = 0; t < 3; t++)
            {'id': t + 1, 'pack': t + 1, 'ord': t, 'name': '갈래 $t', 'key': 'k$t', 'color': t == 2 ? lastColor : 0x9ab0c0, 'rows': [for (int r = 0; r < 8; r++) packRow(t * 8 + r)]},
        ],
        'epochs': [],
      };
      final asked = <int>[];
      final scene = TimelineScene(
        controller: TimelineController()..resize(1920, 500),
        layout: SceneLayout.fromJson(threeTracks(0x7a95c2)),
        fetchTile: (level, x, chunk, packs) async {
          asked.add(chunk);
          return TileBuilder(level: level, x: x, chunk: chunk).build();
        },
      );
      Future<void> fill() async {
        scene.cache.want([for (int c = 0; c < 3; c++) TileKey(9, 1, c, scene.layout.version)], const []);
        for (int i = 0; i < 10; i++) {
          await pumpEventQueue();
        }
      }

      bool has(int chunk) => scene.cache.get(TileKey(9, 1, chunk, scene.layout.version)) != null;
      await fill();
      expect([has(0), has(1), has(2)], [true, true, true]);
      final before = scene.layout.version;
      scene.storeWriting = true;
      scene.replaceLayout(SceneLayout.fromJson(threeTracks(0xc27a45)), keepBefore: 16);
      expect(scene.layout.version, isNot(before), reason: '새 판 번호');
      expect(scene.storeWriting, isFalse, reason: '뼈대를 바꾸면 멈췄던 물음을 푼다');
      expect([has(0), has(1), has(2)], [true, true, false], reason: '(c + 1) × 8 ≤ 16인 묶음만 새 판 번호로 옮겨 남긴다');
      asked.clear();
      await fill();
      expect(asked, [2], reason: '묶음 2만 다시 받는다');

      // 0이면(앞에서부터 바뀜 · 바꿔 넣은 저장소) 모두 버리고, −1이면(바뀐 트랙 없음) 모두 남긴다.
      scene.replaceLayout(SceneLayout.fromJson(threeTracks(0x7a95c2)), keepBefore: 0);
      expect([has(0), has(1), has(2)], [false, false, false]);
      await fill();
      scene.replaceLayout(SceneLayout.fromJson(threeTracks(0x7a95c2)), keepBefore: -1);
      expect([has(0), has(1), has(2)], [true, true, true]);
      // 묶음에 걸치면 그 묶음은 버린다(자리 12 — 묶음 1의 끝 줄이 고쳐 쓴 덩이에 든다).
      scene.replaceLayout(SceneLayout.fromJson(threeTracks(0x7a95c2)), keepBefore: 12);
      expect([has(0), has(1), has(2)], [true, false, false]);
    });

    test('쓰는 동안(storeWriting) 새 타일을 묻지 않고, 풀면 다음 물음부터 받는다', () async {
      final asked = <int>[];
      final scene = TimelineScene(
        controller: TimelineController()..resize(1920, 500),
        layout: SceneLayout.fromJson(keyed()),
        fetchTile: (level, x, chunk, packs) async {
          asked.add(chunk);
          return TileBuilder(level: level, x: x, chunk: chunk).build();
        },
      );
      scene.storeWriting = true;
      scene.cache.want([TileKey(9, 1, 0, scene.layout.version)], const []);
      await pumpEventQueue();
      expect(asked, isEmpty);
      scene.storeWriting = false;
      scene.cache.want([TileKey(9, 1, 0, scene.layout.version)], const []);
      await pumpEventQueue();
      expect(asked, [0]);
    });

    test('쓰는 동안의 다른 조회는 새 뼈대로 바꿀 때(또는 실패로 풀 때)까지 기다린다(storeSettled — 고침 1회차 걱정 2)', () async {
      final scene = TimelineScene(
        controller: TimelineController()..resize(1920, 500),
        layout: SceneLayout.fromJson(keyed()),
        fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      var settled = false;
      await scene.storeSettled.then((_) => settled = true);
      expect(settled, isTrue, reason: '쓰지 않는 동안은 곧바로');
      // 고쳐 쓰는 중: 뼈대를 바꿀 때까지 기다린다(COMMIT 뒤 새 줄 번호의 답이 옛 뼈대에 들어오지 않게).
      settled = false;
      scene.storeWriting = true;
      scene.storeSettled.then((_) => settled = true).ignore();
      await pumpEventQueue();
      expect(settled, isFalse);
      scene.replaceLayout(SceneLayout.fromJson(keyed()), keepBefore: -1);
      await pumpEventQueue();
      expect(settled, isTrue, reason: '새 뼈대로 바꾸면 풀린다');
      // 실패(저장소 그대로)로 풀어도 풀린다.
      settled = false;
      scene.storeWriting = true;
      scene.storeSettled.then((_) => settled = true).ignore();
      await pumpEventQueue();
      expect(settled, isFalse);
      scene.storeWriting = false;
      await pumpEventQueue();
      expect(settled, isTrue);
    });

    test('제자리 고쳐 쓰기라도 변형을 켠 동안은 −1이 아니면 타일을 모두 버린다(다른 트랙의 띠 · 칸을 옮기거나 가린다)', () async {
      final json = keyed()
        ..['variants'] = [
          {'id': 1, 'key': 'host:a', 'kind': 1, 'track': 1, 'band': 100, 'uid': 'a', 'name': '펼침', 'rows': [], 'groups': []},
        ];
      final scene = TimelineScene(
        controller: TimelineController()..resize(1920, 500),
        layout: SceneLayout.fromJson(json),
        fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
      );
      scene.layout.setViewState(const ViewState(expandedHosts: {100}));
      expect(scene.layout.variantKeys, ['host:a'], reason: '장면: 변형 하나를 켰다');
      Future<void> fill() async {
        scene.cache.want([TileKey(9, 1, 0, scene.layout.version)], const []);
        for (int i = 0; i < 5; i++) {
          await pumpEventQueue();
        }
      }

      await fill();
      expect(scene.cache.count, 1);
      scene.replaceLayout(SceneLayout.fromJson(json), view: const ViewState(expandedHosts: {100}), keepBefore: 16);
      expect(scene.cache.count, 0);
      await fill();
      scene.replaceLayout(SceneLayout.fromJson(json), view: const ViewState(expandedHosts: {100}), keepBefore: -1);
      expect(scene.cache.count, 1, reason: '바뀐 트랙이 없으면 켠 변형이 같을 때 남긴다');
      scene.replaceLayout(SceneLayout.fromJson(json), keepBefore: -1);
      expect(scene.cache.count, 0, reason: '켠 변형이 달라지면 늘 버린다');
    });

    test('바꿀 때 보던 줄은 (트랙 · 차례)로 찾아 화면에서 제자리다', () async {
      final (scene, painter, _) = makePackScene();
      scene.controller.resize(1920, scene.controller.view.head + 426);
      scene.controller.scrollTo(300); // 2번 줄(해솔 갈래의 첫 줄)이 화면 위에 걸친 자리
      for (int i = 0; i < 20; i++) {
        paintOnce(painter);
        await pumpEventQueue();
      }
      final v = scene.controller.view;
      final was = v.yOf(scene.layout.rowTop(3));
      // 다시 지은 뼈대: 별여울 갈래에 줄이 하나 늘어 해솔 갈래의 줄 번호가 밀린다(2 · 3 → 3 · 4).
      final fresh = SceneLayout.fromJson({
        'packs': [
          {'id': 1, 'name': '별여울 기록집', 'events': 1250},
          {'id': 2, 'name': '해솔 기록집', 'events': 2},
          {'id': 3, 'name': '은빛 나루 기록집', 'events': 2},
          {'id': 8, 'name': '덧붙인 기록집', 'events': 1},
        ],
        'tracks': [
          {'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'rows': [packRow(0), packRow(1), packRow(2)]},
          {'id': 2, 'pack': 2, 'ord': 1, 'name': '해솔 갈래', 'rows': [packRow(3), packRow(4)]},
          {'id': 3, 'pack': 3, 'ord': 2, 'name': '은빛 나루 갈래', 'rows': [packRow(5), packRow(6)]},
        ],
        'epochs': [],
      });
      scene.replaceLayout(fresh, enabled: {1, 2, 3, 8});
      scene.tick(400);
      expect(scene.layout.rowTop(3), 142 * 3, reason: '해솔 갈래의 첫 줄은 이제 3번');
      expect(v.yOf(scene.layout.rowTop(4)), closeTo(was, 1e-6), reason: '보던 줄(해솔 갈래의 둘째 줄 — 차례 1)은 화면에서 제자리');
    });
  });
}

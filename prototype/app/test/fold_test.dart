import 'dart:async';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/fold.dart';
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fold_rows.dart';
import 'support/tile_builder.dart';

// 빈 줄 접기의 판단(명세 05 6.1 · 6.4 · 움직임 원칙 ④).

SceneView view({double lo = 0, double ppm = 1}) => SceneView()
  ..setSize(1920, 500)
  ..lo = lo
  ..ppm = ppm;

void main() {
  // 이 파일의 손셈 자리는 민족 머리 줄이 없는 쌓기(0.1.0) 기준이다 — 머리 줄(0.1.1 감독 고름 나 · 트랙 첫 줄 묶음마다 +14)의 쌓기는 gutter_test가 본다.
  setUp(() => PaintPick.people = false);
  tearDown(PaintPick.reset);
  group('접힘 규칙', () {
    const rows = [0, 1, 2, 3];

    test('near에 든 줄은 펴지고, far에도 없는 줄만 접히고, 그 사이는 지금 상태를 지킨다', () {
      // 0 near · 1 far에만 있음 · 2 far에도 없음 · 3 far에만 있으나 지금 접혀 있음
      final folded = foldedRowsOf(rows: rows, near: {0}, far: {0, 1, 3}, folded: {3}, first: false, keepOpen: false);
      expect(folded, {2, 3}, reason: '펴져 있던 1은 far 안에 있으니 그대로, 접혀 있던 3은 near에 들어야만 펴진다');
    });

    test('첫 장면은 이력이 없어 near만 본다', () {
      expect(foldedRowsOf(rows: rows, near: {1}, far: {0, 1, 2, 3}, folded: const {}, first: true, keepOpen: false), {0, 2, 3});
    });

    test('움직이는 동안과 정착을 기다리는 동안은 펴지기만 한다', () {
      // 지금 0 · 1이 펴져 있다. far 밖으로 나간 1도 keepOpen이면 접히지 않고, near에 든 2는 움직이는 중에도 바로 펴진다.
      final keep = foldedRowsOf(rows: rows, near: {2}, far: {0}, folded: {2, 3}, first: false, keepOpen: true);
      expect(keep, {3}, reason: '접히는 것은 미루고 펴지는 것만');
      final settle = foldedRowsOf(rows: rows, near: {2}, far: {0}, folded: {3}, first: false, keepOpen: false);
      expect(settle, {1, 3}, reason: '정착하면 far 밖의 1이 접힌다');
    });
  });

  group('물음의 범위', () {
    test('near는 보기 ± 폭의 25% · far는 ± 75% · fade는 44px의 몫', () {
      final v = view();
      final q = FoldQuery.of(v);
      expect(v.plotWidth, 1680, reason: '1920 − 왼쪽 칸 240(리메이크 2부 — 목업 GUT)');
      expect(q.nearLo, -420);
      expect(q.nearHi, 1680 + 420);
      expect(q.farLo, -1260);
      expect(q.farHi, 1680 + 1260);
      expect(q.fade, 44, reason: '미정인 끝을 넓히는 FADE 44px을 분으로');
      expect(q.toQuery(const [1, 2]), {
        'op': 'rows_near',
        'near': [-420, 2100],
        'far': [-1260, 2940],
        'fade': 44,
        'packs': [1, 2],
      });
    });

    test('배율이 절반이면 넓히는 몫도 두 배다', () {
      final q = FoldQuery.of(view(ppm: .5));
      expect(q.fade, 88);
      expect(q.nearLo, -840);
    });
  });

  group('묻는 때', () {
    late SceneLayout layout;
    late List<Map<String, dynamic>> asked;
    late List<Completer<Map<String, dynamic>>> waiting;
    late List<Set<int>> applied;
    late RowFolder folder;

    setUp(() {
      layout = SceneLayout.fromJson(twoTrackLayout());
      asked = [];
      waiting = [];
      applied = [];
      folder = RowFolder(
        layout: layout,
        ask: (q) {
          asked.add(q);
          final c = Completer<Map<String, dynamic>>();
          waiting.add(c);
          return c.future;
        },
        onFolded: applied.add,
      );
    });

    Future<void> answer(int index, {List<int> near = const [], List<int> far = const []}) async {
      waiting[index].complete({'near': near, 'far': far});
      await pumpEventQueue();
    }

    test('보기가 폭의 10% 넘게 옮겨졌거나 배율이 바뀌었을 때만 묻는다', () async {
      folder.maybeAsk(view(), layout.enabledPacks);
      expect(asked.length, 1, reason: '첫 장면에는 묻는다');
      await answer(0, near: [0], far: [0]);
      folder.maybeAsk(view(lo: 100), layout.enabledPacks);
      expect(asked.length, 1, reason: '폭 1680의 10%인 168보다 적게 움직였다');
      folder.maybeAsk(view(lo: 200), layout.enabledPacks);
      expect(asked.length, 2);
      await answer(1, near: [0], far: [0]);
      folder.maybeAsk(view(lo: 200), layout.enabledPacks);
      expect(asked.length, 2, reason: '제자리면 묻지 않는다');
      folder.maybeAsk(view(lo: 200, ppm: 2), layout.enabledPacks);
      expect(asked.length, 3, reason: '배율이 바뀌면 묻는다');
    });

    test('저장소를 고쳐 쓰는 동안 멈췄다가 실패로 풀리면 보던 자리의 접힘을 다시 묻는다(멈춘 동안의 답은 버렸다 — 과제 8 고침 2회차)', () async {
      folder.maybeAsk(view(), layout.enabledPacks);
      await answer(0, near: [0], far: [0]);
      expect(asked.length, 1);
      folder.paused = true;
      folder.maybeAsk(view(), layout.enabledPacks);
      expect(asked.length, 1, reason: '멈춘 동안은 묻지 않는다');
      folder.paused = false;
      folder.maybeAsk(view(), layout.enabledPacks);
      expect(asked.length, 2, reason: '풀리면 제자리여도 다시 묻는다');
    });

    test('한 번에 하나만 묻고, 기다리는 동안 바뀐 것은 답이 온 뒤 그때의 보기로 한 번만 다시 묻는다', () async {
      final moving = view();
      folder.maybeAsk(moving, layout.enabledPacks);
      // 답을 기다리는 동안 보기가 여러 번 바뀌어도(확대 · 돋보기는 장면마다 바뀐다) 물음은 더 나가지 않는다 — 큰 저장소에서 자료 처리부가 밀려 타일이 굶지 않게.
      for (final lo in [3000.0, 6000.0, 9999.0]) {
        moving.lo = lo;
        folder.maybeAsk(moving, layout.enabledPacks);
      }
      expect(asked.length, 1);
      expect(folder.asking, isTrue);
      await answer(0, near: [0, 1], far: [0, 1, 2, 3, 4]);
      expect(asked.length, 2, reason: '답이 오면 마지막 보기로 한 번만 다시 묻는다');
      expect(applied.single, {2, 3, 4}, reason: '먼저 온 답은 그대로 쓴다(더 새 답이 아직 없다)');
      await answer(1, near: [4], far: [4]);
      expect(folder.folded, {0, 1, 2, 3});
      expect(folder.asking, isFalse);
    });

    test('끈 자료집의 줄은 접힘 집합에 넣지 않는다', () async {
      layout.enable({1});
      folder.maybeAsk(view(), layout.enabledPacks);
      await answer(0, near: [0]);
      expect(applied.single, {1, 2}, reason: '2번 자료집의 줄 3 · 4는 건드리지 않는다');
    });
  });

  group('정착', () {
    late SceneLayout layout;
    late List<Completer<Map<String, dynamic>>> waiting;
    late List<Set<int>> applied;
    late RowFolder folder;

    setUp(() {
      layout = SceneLayout.fromJson(twoTrackLayout());
      waiting = [];
      applied = [];
      folder = RowFolder(
        layout: layout,
        ask: (q) {
          final c = Completer<Map<String, dynamic>>();
          waiting.add(c);
          return c.future;
        },
        onFolded: applied.add,
      );
    });

    Future<void> answer(int index, {List<int> near = const [], List<int> far = const []}) async {
      waiting[index].complete({'near': near, 'far': far});
      await pumpEventQueue();
    }

    test('움직이는 동안 온 답은 펴기만 하고, 관성이 멎은 장면에 바로 접힌다', () async {
      folder.maybeAsk(view(), layout.enabledPacks);
      waiting[0].complete({'near': [0, 1, 2, 3, 4], 'far': [0, 1, 2, 3, 4]});
      await pumpEventQueue();
      expect(applied, isEmpty, reason: '모두 펴진 그대로');

      // 관성이 돈다 → 접힘은 미룬다.
      folder.tick(moving: true, coasting: true, nowMs: 0);
      expect(folder.settleWaiting, isTrue);
      folder.maybeAsk(view(lo: 99999), layout.enabledPacks);
      waiting[1].complete({'near': [0], 'far': [0, 1]});
      await pumpEventQueue();
      expect(applied, isEmpty, reason: '움직이는 동안은 접지 않는다');

      // 관성이 멎은 장면 — 기다림 0.
      folder.tick(moving: false, coasting: false, nowMs: 16);
      expect(applied.single, {2, 3, 4});
      expect(folder.settled, isTrue);
    });

    test('휠 · 미끄러짐이 멎으면 300ms 뒤에 접히고, 기다리는 동안 다시 누르면 예약을 거둔다', () async {
      folder.maybeAsk(view(), layout.enabledPacks);
      waiting[0].complete({'near': [0, 1, 2, 3, 4], 'far': [0, 1, 2, 3, 4]});
      await pumpEventQueue();
      folder.tick(moving: true, coasting: false, nowMs: 0); // 휠의 미끄러짐
      folder.maybeAsk(view(lo: 99999), layout.enabledPacks);
      waiting[1].complete({'near': [0], 'far': [0]});
      await pumpEventQueue();
      expect(applied, isEmpty);

      folder.tick(moving: false, coasting: false, nowMs: 100); // 멎음 → 100 + 300에 정착
      folder.tick(moving: false, coasting: false, nowMs: 399);
      expect(applied, isEmpty, reason: '아직 300ms가 안 됐다');
      expect(folder.settleWaiting, isTrue);
      expect(folder.settled, isFalse);

      // 기다리는 동안 다시 손이 닿았다 → 예약을 거두고, 뗄 때 다시 300ms.
      folder.tick(moving: true, coasting: false, nowMs: 399);
      folder.tick(moving: false, coasting: false, nowMs: 500);
      folder.tick(moving: false, coasting: false, nowMs: 700);
      expect(applied, isEmpty);
      folder.tick(moving: false, coasting: false, nowMs: 800);
      expect(applied.single, {1, 2, 3, 4});
    });

    test('멈춰 있을 때 온 답은(멀리 가기의 도착 · 다시 배치) 기다림 없이 바로 접힌다', () async {
      folder.maybeAsk(view(), layout.enabledPacks);
      waiting[0].complete({'near': [3], 'far': [3]});
      await pumpEventQueue();
      expect(applied.single, {0, 1, 2, 4});
      expect(folder.settled, isTrue);
    });

    test('장면에 붙이면: 그리기 직전에 묻고 · 답이 오면 접고 · 흐르는 동안 붙잡은 줄이 제자리고 · 다 되면 가라앉는다', () async {
      final controller = TimelineController()
        ..resize(1920, 500)
        ..setExtent(0, 100000);
      final l = SceneLayout.fromJson(twoTrackLayout());
      controller.setContentHeight(l.totalHeight);
      controller.showRange(0, 1000);
      final asked = <Map<String, dynamic>>[];
      final scene = TimelineScene(
        controller: controller,
        layout: l,
        fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
        labelCompute: (input) async => placeLabels(input),
        ask: (q) async {
          asked.add(q);
          return {'near': [0, 2, 3, 4], 'far': [0, 2, 3, 4]};
        },
      );
      addTearDown(scene.dispose);
      scene.measureName = (title, importance) => 10;
      expect(scene.settled, isTrue);

      scene.prepare();
      expect(asked.single['op'], 'rows_near');
      expect(scene.settled, isFalse, reason: '답을 기다리는 동안은 가라앉지 않았다');
      await pumpEventQueue();
      expect(l.foldedRows, {1});
      expect(l.flowing, isTrue, reason: '줄 자리가 흐르기 시작했다');
      expect(scene.busy.value, isTrue, reason: '흐르는 동안 화면의 시계가 돈다');

      scene.tick(360);
      expect(l.flowing, isFalse);
      expect(scene.settled, isTrue);
      expect(controller.view.top, 0, reason: '위쪽이 줄었으니 붙잡은 줄을 따라 맨 위에 머문다');
      expect(l.totalHeight, 170, reason: '보이는 네 줄에 줄 위 틈 5px을 포함한 몫(두 장 꼬리표 띠 32 — 트랙 1 = 4 + 37 + 40 + 4 · 트랙 2 = 4 + 37 + 40 + 4)');

      // 제자리에서는 더 묻지 않는다.
      scene.prepare();
      expect(asked.length, 1);
    });

    test('접힌 트랙 · 끈 트랙 · 접힌 민족에 합쳐진 줄은 접힘을 묻지 않는다', () async {
      // 어차피 보이지 않는 줄이라 접힘 집합에 넣지 않는다(명세 05 5절).
      layout.setViewState(const ViewState(foldedTracks: {2}));
      folder.maybeAsk(view(), layout.enabledPacks);
      await answer(0, near: [0]);
      expect(applied.single, {1, 2}, reason: '접힌 트랙 2의 줄 3 · 4는 빠진다');

      final l = SceneLayout.fromJson(twoTrackLayout());
      final got = <Set<int>>[];
      final f = RowFolder(layout: l, ask: (q) async => {'near': <int>[], 'far': <int>[]}, onFolded: got.add);
      l.setViewState(const ViewState(offTracks: {1}));
      l.foldGroup(l.tracks[1], l.tracks[1].groups.single, true); // 줄 3 · 4가 줄 3 하나로
      f.maybeAsk(view(), l.enabledPacks);
      await pumpEventQueue();
      expect(got.single, {3}, reason: '끈 트랙 1의 줄과 합쳐져 사라진 줄 4는 빠지고, 합쳐진 줄 3만 남는다');
    });

    test('접힌 민족 줄은 그 묶음의 줄 어디에든 내용이 있으면 펴진다', () async {
      layout.foldGroup(layout.tracks[0], layout.tracks[0].groups.single, true); // 줄 0~2 → 줄 0
      folder.maybeAsk(view(), layout.enabledPacks);
      // 답은 저장소의 본디 줄 번호로 온다 — 내용이 있는 것은 합쳐져 사라진 줄 2뿐이다.
      await answer(0, near: [2], far: [2]);
      expect(applied.single, {3, 4}, reason: '합쳐진 줄 0은 묶음 안에 내용이 있으니 펴 둔다');
    });

    test('보기 상태가 바뀌면 그 자리에서 다시 셈한다 — 트랙을 펴도 빈 줄은 처음부터 접혀 있다', () async {
      layout.setViewState(const ViewState(foldedTracks: {1}));
      folder.maybeAsk(view(), layout.enabledPacks);
      await answer(0, near: [3], far: [3]);
      expect(applied.single, {4}, reason: '접힌 트랙 1의 줄은 아직 묻지 않았다');
      layout.setViewState(const ViewState());
      folder.recheck();
      expect(applied.last, {0, 1, 2, 4}, reason: '펴는 그 장면에 이미 접힌 크기 — 커졌다 줄어드는 두 단계가 없다');
    });

    test('자료집이 바뀌면 접힘의 기억을 버린다', () async {
      folder.maybeAsk(view(), layout.enabledPacks);
      waiting[0].complete({'near': [0], 'far': [0, 1]});
      await pumpEventQueue();
      expect(folder.folded, {1, 2, 3, 4});
      folder.forget();
      expect(folder.folded, isEmpty);
      folder.maybeAsk(view(), layout.enabledPacks);
      waiting[1].complete({'near': [0, 1], 'far': [0, 1, 2]});
      await pumpEventQueue();
      expect(applied.last, {2, 3, 4}, reason: '이력 없이 near만 본다 — far에만 있는 2도 접힌다');
    });
  });

  // 보기 상태와 자동 조감이 장면(scene.dart)에 붙는 자리 — 명세 05 5.1 · 7.6 · 움직임 원칙 ④ · ⑧.
  group('보기 상태와 자동 조감', () {
    const year = 525960.0;
    late TimelineController controller;
    late SceneLayout l;
    late TimelineScene scene;

    setUp(() {
      controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 120)
        ..setExtent(0, 6000 * year);
      l = SceneLayout.fromJson(twoTrackLayout());
      controller.setContentHeight(l.totalHeight);
      scene = TimelineScene(
        controller: controller,
        layout: l,
        fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
        labelCompute: (input) async => placeLabels(input),
      );
      addTearDown(scene.dispose);
    });

    test('트랙을 접고 펼 때는 누른 트랙의 위가 제자리다(_pressHold)', () {
      expect(scene.applyViewState(const ViewState(foldedTracks: {1})), isTrue);
      expect(l.trackHeight(0), 34);
      // 접힌 채 전체 34 + 85 = 119 · 몸통 46이라 73까지 내려갈 수 있다.
      controller.scrollTo(50);
      expect(controller.view.top, 50);

      expect(scene.applyViewState(const ViewState()), isTrue);
      expect(l.trackTop(0), 0);
      expect(l.trackHeight(0), 125, reason: '세 줄에 줄 위 틈 5px을 포함한 트랙(4 + 37 + 40 + 40 + 4)');
      expect(controller.view.top, 50, reason: '펴는 트랙의 위가 제자리 — 아래가 밀린다(화면 가운데 줄을 붙잡았다면 50 + (125 − 34) = 141로 튀었을 것)');
    });

    test('트랙을 하나만 건드린 것이 아니면 화면 가운데 줄을 붙잡는다', () {
      controller.scrollTo(100);
      expect(scene.applyViewState(const ViewState(foldedTracks: {1, 2})), isTrue);
      expect(l.totalHeight, 68);
      expect(controller.view.top, 68 - controller.view.bodyHeight, reason: '붙잡을 줄이 모두 사라져 스크롤 끝에 붙는다');
    });

    test('자동 조감은 정착 때 걸리고, 사람이 고른 밀도는 그대로다', () {
      final told = <(int, bool)>[];
      scene.onDensity = (density, {required bool auto}) => told.add((density, auto));
      controller.showRange(0, 1000 * year);
      scene.autoBird = (true, 0);
      expect(l.bird, isFalse, reason: '1,000년은 문턱 아래');
      expect(told, isEmpty);

      controller.showRange(0, 3000 * year);
      expect(l.bird, isFalse, reason: '옮기는 도중에는 바뀌지 않는다(원칙 ④)');
      scene.settleNow();
      expect(l.bird, isTrue);
      expect(l.conditions.density, 0, reason: '밀도는 사람이 고른 그대로 — 조감은 자동 조감이 덧씌운 것');
      expect(l.geo(1).bandHeight, BirdShape.a.bandHeight);
      expect(told, [(2, true)]);

      controller.showRange(0, 2500 * year);
      scene.settleNow();
      expect(l.bird, isTrue, reason: '나가는 문턱은 2,392년 — 2,500년에서는 아직 조감');

      controller.showRange(0, 2000 * year);
      scene.settleNow();
      expect(l.bird, isFalse);
      expect(told.last, (0, true), reason: '직전 밀도로 되돌아간다');
    });

    test('자동 조감이 걸린 채 다른 밀도를 고르면 조감을 떠나 쉰다', () {
      controller.showRange(0, 3000 * year);
      scene.autoBird = (true, 0);
      expect(l.bird, isTrue);
      expect(scene.applyDensity(1), isTrue);
      expect(l.bird, isFalse);
      expect(l.conditions.density, 1);
      scene.settleNow();
      expect(l.bird, isFalse, reason: '문턱을 넘어 있어도 쉬는 중이라 되돌아오지 않는다');
      expect(scene.autoBirdState.hold, isTrue);
      expect(scene.autoBird, (true, 1));
    });

    test('자동 조감을 손으로 풀면 고른 밀도로 돌아간다', () {
      controller.showRange(0, 3000 * year);
      scene.autoBird = (true, -1);
      expect(l.bird, isTrue);
      scene.leaveAutoBird();
      expect(l.bird, isFalse);
      expect(l.conditions.density, 0, reason: '밀도 값 자체는 건드리지 않는다 — 알림으로만 −1을 말한다');
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

// 실제 앱에서 원래 줄의 rows_near 답을 받은 뒤 판을 켜면, 옛 답으로 판의 새 줄을 모두 접던 경로.
// 판의 줄 번호가 바뀌는 켬 · 교체 · 끔과 늦은 답을 실제 RowFolder로 잇는다.
const _threeLands = 'view:v-three-lands', _overSea = 'view:v-16og913';

class _BoardScene {
  _BoardScene({bool lens = false}) {
    final json = Map<String, dynamic>.from(jsonDecode(File('test/fixtures/board-views-layout.json').readAsStringSync()) as Map);
    if (lens) {
      (json['variants'] as List).add({
        'id': 4, 'key': 'theme:faction', 'kind': 4, 'uid': 'faction', 'rows': <dynamic>[], 'groups': <dynamic>[],
      });
    }
    layout = SceneLayout.fromJson(json)..reduceMotion = true;
    controller = TimelineController()
      ..reduceMotion = true
      ..resize(1920, 1080)
      ..setExtent(-1000000000, 0)
      ..setContentHeight(layout.totalHeight)
      ..showRange(-900000000, -700000000);
    scene = TimelineScene(
      controller: controller,
      layout: layout,
      fetchTile: (level, x, chunk, packs) async => TileBuilder(level: level, x: x, chunk: chunk).build(),
      labelCompute: (input) async => placeLabels(input),
      ask: (query) {
        variants.add(layout.variantsOn.map((v) => v.key).toSet());
        final reply = Completer<Map<String, dynamic>>();
        replies.add(reply);
        return reply.future;
      },
    );
    if (lens) scene.applyThemeLens('faction', slots: {'sv-east', 'sv-west', 'sv-south'});
  }

  late final SceneLayout layout;
  late final TimelineController controller;
  late final TimelineScene scene;
  final replies = <Completer<Map<String, dynamic>>>[];
  final variants = <Set<String>>[];

  void ask() => scene.folder.maybeAsk(controller.view, layout.enabledPacks);

  Future<void> answer(int at, List<int> rows) async {
    replies[at].complete({'near': rows, 'far': rows});
    await pumpEventQueue();
  }

  void board(String key) {
    expect(scene.applyViewState(layout.withBoardState(key), hold: (-1, 0)), isTrue);
    // archive_app._applyBoard의 나머지 순서까지 재현한다. 내부 기억만 비우면 실제 접힘은 지워지지 않는다.
    controller.setContentHeight(layout.totalHeight);
    scene.folder.forget();
    scene.requestFrame();
  }

  void visible(List<int> rows) {
    for (final row in rows) {
      expect(layout.isVisible(row), isTrue, reason: '새 판의 줄 $row는 새 rows_near 답이 오기 전에 옛 판의 답으로 접히지 않는다');
    }
  }

  void dispose() {
    scene.dispose();
    controller.dispose();
  }
}

void main() {
  for (final lens in [false, true]) {
    test('옛 줄 조회 뒤 판 켬 · 다른 판 · 끔에서 접힘을 새로 묻는다${lens ? ' — 렌즈 함께' : ''}', () async {
      final h = _BoardScene(lens: lens);
      addTearDown(h.dispose);
      h.ask();
      await h.answer(0, [0, 2, 3]);
      expect(h.layout.foldedRows, {1, 4});

      h.board(_threeLands);
      h.visible([5, 6, 7]);
      expect(h.layout.foldedRows, isEmpty);
      h.ask();
      expect(h.variants.last, {_threeLands, if (lens) 'theme:faction'});
      await h.answer(1, [5, 6, 7]);
      h.visible([5, 6, 7]);
      expect(h.layout.trackHeight(h.layout.boardTrackIndex), greaterThan(34));

      // 실제로 빈 판 줄을 접은 뒤 바꾸어도 그 접힘이 다음 판이나 원래 줄에 남지 않는다.
      h.scene.folder.forget();
      h.ask();
      await h.answer(2, [5]);
      expect(h.layout.foldedRows, {6, 7});
      h.board(_overSea);
      h.visible([8, 9, 10]);
      expect(h.layout.foldedRows, isEmpty);
      h.ask();
      expect(h.variants.last, {_overSea, if (lens) 'theme:faction'});
      await h.answer(3, [8, 10]);
      expect(h.layout.foldedRows, {9});
      h.visible([8, 10]);

      h.board('');
      h.visible([0, 1, 2, 3, 4]);
      expect(h.layout.foldedRows, isEmpty);
      h.ask();
      expect(h.variants.last, {if (lens) 'theme:faction'});
      await h.answer(4, [0, 2, 3]);
      expect(h.layout.foldedRows, {1, 4});
      h.visible([0, 2, 3]);
    });
  }

  test('판 전환 전에 시작한 줄 조회의 늦은 답은 버리고 켠 판과 렌즈로 다시 묻는다', () async {
    final h = _BoardScene(lens: true);
    addTearDown(h.dispose);
    h.ask();
    h.board(_threeLands);
    h.ask();
    expect(h.replies, hasLength(1), reason: '물음은 한 번에 하나');
    await h.answer(0, [0, 2, 3]);
    expect(h.replies, hasLength(2));
    expect(h.layout.foldedRows, isEmpty, reason: '늦은 원래 줄의 답이 판 줄을 접지 않는다');
    h.visible([5, 6, 7]);
    expect(h.variants.last, {_threeLands, 'theme:faction'});
    await h.answer(1, [5, 7]);
    expect(h.layout.foldedRows, {6});
    h.visible([5, 7]);
  });
}

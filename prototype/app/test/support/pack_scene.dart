import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/labels.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart';

import 'scene_text.dart';
import 'tile_builder.dart';

// 자료집 켬/끔 검사가 함께 쓰는 장면.

Map<String, dynamic> packRow(int id) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

const _m = 1000000.0;
final _ppm = 32 / bucketMinutes(9); // 통 32px → 단계 9
double _px(double pixels) => pixels / _ppm;

/// 자료집 셋(1 · 2 · 3)이 트랙을 하나씩(줄 둘씩) 갖고, 8번 자료집은 트랙 없이 남의 줄(4번 줄)에 사건만 덧붙인다.
/// 창 높이 500(몸통 426)이라 세로로 움직일 수 있다. 셋째 값은 자료 처리부에 물은 자료집 조합의 기록.
(TimelineScene, TimelinePainter, List<List<int>>) makePackScene() {
  final controller = TimelineController()
    ..resize(1920, 500)
    ..setExtent(-2000 * _m, 2000 * _m)
    ..setContentHeight(142 * 6);
  final origin = tileOrigin(9, 1).toDouble();
  controller.showRange(origin, origin + (1920 - SceneView.gutter) / _ppm);
  final asked = <List<int>>[];
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson({
      'packs': [
        {'id': 1, 'name': '별여울 기록집', 'events': 1250},
        {'id': 2, 'name': '해솔 기록집', 'events': 2},
        {'id': 3, 'name': '은빛 나루 기록집', 'events': 2},
        {'id': 8, 'name': '덧붙인 기록집', 'events': 1},
      ],
      'tracks': [
        {'id': 1, 'pack': 1, 'ord': 0, 'name': '별여울 갈래', 'rows': [packRow(0), packRow(1)]},
        {'id': 2, 'pack': 2, 'ord': 1, 'name': '해솔 갈래', 'rows': [packRow(2), packRow(3)]},
        {'id': 3, 'pack': 3, 'ord': 2, 'name': '은빛 나루 갈래', 'rows': [packRow(4), packRow(5)]},
      ],
      'epochs': [],
    }),
    fetchTile: (level, x, chunk, packs) async {
      asked.add(packs);
      final tile = TileBuilder(level: level, x: x, chunk: chunk);
      if (level != 9 || x != 1 || chunk != 0) return tile.build();
      for (int r = 0; r < 6; r++) {
        if (!packs.contains(r ~/ 2 + 1)) continue;
        tile
          ..band(100 + r, r, 0, _px(1600), '띠 $r')
          ..event(10 + r, r, _px(200 + r * 40), '별여울의 기록 $r');
      }
      if (packs.contains(8) && packs.contains(3)) tile.event(80, 4, _px(900), '덧붙인 기록');
      return tile.build();
    },
    labelCompute: (input) async => placeLabels(input),
  );
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true, asked);
}

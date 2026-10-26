// 0.1.1 감독 지적 '확대할 때 나라 이름표, 위의 플래그가 뛰쳐나가는 버그'(2026-10-26 02:1x): 풀린 그릇의 열쇠표(띠 윗변 위의 작은 표 — 띠 시작이
// 화면 밖이면 그림판 왼쪽에 붙어 따라온다)는 같은 띠 위 상국 탭 · 승계선의 세로 획을 비킨다. 예전에는 탭 · 획 뒤라면 얼마든지 밀어, 확대 · 끌기 동안
// 탭(관계가 끝나는 해에 매임) · 획(그 해의 선)이 열쇠표 위를 지나면 열쇠표가 그 뒤로 90px 가까이 뛰었다가 돌아왔다(동아시아 + 감독 DLC의 옥저 '원삼국 시대' —
// 5 → 95 → 25 → 5px). 이제 열쇠표는 제자리에서 오른쪽으로 [FolderLook.keyShift](16)까지만 밀리고, 그보다 멀면 제자리에 구멍만 · 없음이다.
// 여기서는 탭 · 획을 한 장면씩 옮겨 가며(확대 · 끌기 동안 열쇠표에 대해 탭 · 획이 지나가는 것과 같은 꼴) 열쇠표의 자리를 본다.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/bands.dart';
import 'package:archive_prototype/scene/paint/links.dart';
import 'package:archive_prototype/scene/paint/scopes.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/viewport.dart' show SceneView;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

const m = 1000000.0;
const lkDown = 1 << 4, lkQFirst = 1 << 5;

Map<String, dynamic> row(int id) => {
  'id': id, 'height': 142, 'band_top': 19, 'band_h': 123, 'dyn_top': -1, 'lead_top': 23,
  'cab_top': 46, 'text_top': 66, 'text_lines': 2, 'rail_top': 108, 'organ_top': -1,
};

/// 보기 10 ~ 20(백만 분) · 1920 × 1080 · 줄 [rows]개(줄마다 142 — 띠 윗변 19).
(TimelineScene, TimelinePainter) make(Uint8List bytes, int rows) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(142.0 * rows);
  final scene = TimelineScene(
    controller: controller,
    layout: SceneLayout.fromJson({
      'packs': [{'id': 1, 'name': '별여울 기록집', 'events': 0}],
      'tracks': [{'id': 1, 'pack': 1, 'ord': 0, 'name': '해솔 갈래', 'rows': [for (int r = 0; r < rows; r++) row(r)]}],
    }),
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 0 && chunk == 0 ? bytes : TileBuilder(level: level, x: x, chunk: chunk).build(),
  );
  controller.showRange(10 * m, 20 * m);
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

Future<List<String>> notesOf(TimelineScene scene, TimelinePainter painter, String kind) async {
  for (int i = 0; i < 40; i++) {
    scene.prepare();
    await pumpEventQueue();
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(1920, 1080));
    recorder.endRecording().dispose();
  }
  return [for (final v in painter.debugSink.notes[kind] ?? const <Object>[]) '$v'];
}

List<double> nums(String text) => [for (final s in text.split(RegExp('[ ,]'))) double.tryParse(s) ?? double.nan].where((v) => !v.isNaN).toList();

/// 그린 열쇠표 — (이름(구멍만이면 빈 글), 왼쪽, 폭). 기록 '열쇠표' = '<이름> kx,ky,w'.
List<(String, double, double)> keysOf(List<String> notes) => [
  for (final n in notes) () {
    final cut = n.lastIndexOf(' ');
    final v = nums(n.substring(cut + 1));
    return (n.substring(0, cut).trim(), v[0], v[2]);
  }(),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ppm = (1920 - SceneView.gutter) / (10 * m);

  // 띠(줄 0)는 화면 왼쪽 밖(5)에서 시작해 19에서 끝난다 — 열쇠표 둘('삼한' · '원삼국 시대')은 그림판 왼쪽에 붙어 따라온다.
  // 섬김(뒤 장 · 상국 탭 '고구려')은 [5, hostEnd] — 탭은 뒤 장 끝 쪽에 서므로 hostEnd를 줄이면 탭이 오른쪽에서 열쇠표 위를 지나 왼쪽으로 간다.
  Uint8List hostTile(double? hostEnd) {
    final b = TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(1, 0, 5 * m, 19 * m, '옥저')
      ..item(ScopeMarks.secKey, 601, 0, 5 * m, 19 * m, ref: 1, name: '삼한', color: 0xa27e76, text2: 's-han')
      ..item(ScopeMarks.secKey, 602, 0, 5 * m, 19 * m, ref: 1, name: '원삼국 시대', color: 0xa27e76, text2: 's-three');
    if (hostEnd != null) b.item(BandLayer.sectionHostTab, 52, 0, 5 * m, hostEnd, ref: 1, name: '고구려', color: 0x8b6f47, a: 1, d: 99, text2: 'p/goguryeo');
    return b.build();
  }

  test('상국 탭이 열쇠표 위를 지나가도(확대 · 끌기) 열쇠표는 제자리 + 16 안에서만 — 탭과 겹치지 않고 둘째 열쇠표도 그 자리', () async {
    final (bare, barePainter) = make(hostTile(null), 1);
    addTearDown(bare.dispose);
    final home = keysOf(await notesOf(bare, barePainter, '열쇠표'));
    expect(home.map((k) => k.$1), ['삼한', '원삼국 시대'], reason: '탭이 없으면 둘 다 이름째');
    final left = bare.controller.view.xOf(10 * m);
    // 탭의 끝 쪽 자리가 그림판 오른쪽 300px에서 왼쪽 끝까지 6px씩 — 탭이 열쇠표 둘 위를 지난다.
    final seen = <String, List<double>>{'삼한': [], '원삼국 시대': []};
    var stubs = 0, gone = 0;
    for (var px = 300.0; px >= 0; px -= 6) {
      final (scene, painter) = make(hostTile(10 * m + px / ppm), 1);
      addTearDown(scene.dispose);
      final keys = keysOf(await notesOf(scene, painter, '열쇠표'));
      // 기록 '상국탭' = '<띠> <이름> x×10,w×10[ 첫글자]'.
      final tabs = [for (final n in painter.debugSink.notes['상국탭'] ?? const <Object>[]) nums('$n'.split(' ').firstWhere((p) => RegExp(r'^-?\d+,-?\d+$').hasMatch(p)))];
      // 그린 열쇠표를 제 자리(차례)에 맞춘다 — 구멍만이면 이름이 없으니 자리로 가른다.
      for (final k in keys) {
        final i = (k.$2 - home[0].$2).abs() <= (k.$2 - home[1].$2).abs() ? 0 : 1;
        final shift = k.$2 - home[i].$2;
        expect(shift, inInclusiveRange(0, FolderLook.keyShift), reason: '탭 끝 $px: ${home[i].$1} 열쇠표가 제자리 ${home[i].$2}에서 $shift 밀림(16 넘게 뛰면 안 된다)');
        if (k.$1.isEmpty) {
          stubs++;
          expect((shift, k.$3), (0.0, FolderLook.keyStub), reason: '탭 끝 $px: 구멍만은 제자리');
        } else {
          expect(k.$1, home[i].$1);
          seen[k.$1]!.add(k.$2);
        }
        for (final tab in tabs) {
          final (tl, tr) = (tab[0] / 10, (tab[0] + tab[1]) / 10);
          expect(k.$2 + k.$3 + FolderLook.keyGap <= tl || k.$2 >= tr + FolderLook.keyGap, isTrue,
              reason: '탭 끝 $px: 열쇠표 ${k.$2} ~ ${k.$2 + k.$3} · 탭 $tl ~ $tr — 4 넘게 떨어져야 한다');
        }
      }
      gone += 2 - keys.length;
      if (keys.length == 2) {
        expect(keys[1].$2, greaterThanOrEqualTo(keys[0].$2 + home[0].$3 + FolderLook.keyGap), reason: '탭 끝 $px: 둘째는 첫째의 온 폭 뒤 — 첫째가 구멍만이어도 당겨 앉지 않는다');
      }
      expect(keys.every((k) => k.$2 >= left), isTrue);
    }
    expect(stubs + gone, greaterThan(0), reason: '탭이 정말 열쇠표 위를 지났다');
    for (final e in seen.entries) {
      for (int i = 1; i < e.value.length; i++) {
        expect((e.value[i] - e.value[i - 1]).abs(), lessThanOrEqualTo(FolderLook.keyShift), reason: '${e.key}: 이웃 장면 사이에 ${e.value[i - 1]} → ${e.value[i]}');
      }
    }
  });

  // 0번 줄 앞 나라(q에서 끝남) → 2번 줄 뒤 나라의 승계선: 통로(앞 나라 끝 + 9)가 1번 줄 사이 나라(화면 왼쪽 밖에서 시작 — 열쇠표가 그림판 왼쪽에 붙음)의
  // 윗변을 지난다. q를 옮기면 그 세로 획이 열쇠표 위를 지나간다(확대 · 끌기 동안 획이 지나가는 꼴 — 감독 DLC 삼한 · 변한 줄).
  Uint8List strokeTile(double q) {
    final b = TileBuilder(level: 9, x: 0, chunk: 0)
      ..band(1, 0, q - 20 * m, q, '앞 나라')
      ..item(LinkLayer.secSquare, 101, 0, q - 20 * m, q, ref: 1, name: '앞 나라', color: 0xabb3c9)
      ..band(5, 1, 5 * m, 19 * m, '사이 나라')
      ..item(LinkLayer.secSquare, 105, 1, 5 * m, 19 * m, ref: 5, name: '사이 나라', color: 0xabb3c9)
      ..band(3, 2, q + 1 * m, q + 6 * m, '뒤 나라')
      ..item(LinkLayer.secSquare, 103, 2, q + 1 * m, q + 6 * m, ref: 3, name: '뒤 나라', color: 0xabb3c9)
      ..item(ScopeMarks.secKey, 601, 1, 5 * m, 19 * m, ref: 5, name: '원삼국 시대', color: 0xa27e76, text2: 's-three')
      ..item(LinkLayer.secLink, 201, 0, q, q + 1 * m, row2: 2, ref: 1, b: 3, color: 0xabb3c9, a: lkQFirst | lkDown);
    return b.build();
  }

  test('승계선의 세로 획이 열쇠표 위를 지나가도 열쇠표는 제자리 + 16 안에서만 — 획은 열쇠표 · 실 밑을 지나지 않는다', () async {
    final (far, farPainter) = make(strokeTile(18 * m), 3);
    addTearDown(far.dispose);
    final home = keysOf(await notesOf(far, farPainter, '열쇠표')).single;
    expect(home.$1, '원삼국 시대');
    var touched = 0;
    final named = <double>[];
    for (var px = 160.0; px >= -10; px -= 3) {
      final q = 10 * m + px / ppm;
      final (scene, painter) = make(strokeTile(q), 3);
      addTearDown(scene.dispose);
      final keys = keysOf(await notesOf(scene, painter, '열쇠표'));
      final moved = [for (final n in painter.debugSink.notes['열쇠표비킴'] ?? const <Object>[]) '$n'];
      if (moved.isNotEmpty) touched++;
      // 열쇠표 높이(1번 줄 띠 윗변 위 2 + 12)를 지나는 기둥만.
      final bandTop = scene.controller.view.yOf(142 + 19).roundToDouble();
      final cols = [for (final col in LinkColumns.of(scene)) if (col.top < bandTop && col.bottom > bandTop - FolderLook.keyRise - FolderLook.keyH) col.x];
      for (final k in keys) {
        final shift = k.$2 - home.$2;
        expect(shift, inInclusiveRange(0, FolderLook.keyShift), reason: '획 자리 $px: 열쇠표가 제자리 ${home.$2}에서 $shift 밀림 · $moved');
        if (k.$1.isEmpty) expect(shift, 0, reason: '획 자리 $px: 구멍만은 제자리');
        if (k.$1.isNotEmpty) named.add(k.$2);
        // 실은 열쇠표 왼쪽 − 3(밀렸으면 함께)에서 오르므로 그 사이와 열쇠표 몫 안으로 획이 지나면 안 된다(± 1 · 틈 4).
        for (final x in cols) {
          final crossing = x + 1 + FolderLook.keyGap > k.$2 - 3 && x - 1 < k.$2 + k.$3 + FolderLook.keyGap;
          if (crossing) fail('획 자리 $px: 획 $x가 열쇠표 ${k.$2} ~ ${k.$2 + k.$3} 밑을 지난다');
        }
      }
    }
    expect(touched, greaterThan(0), reason: '획이 정말 열쇠표 위를 지났다');
    for (int i = 1; i < named.length; i++) {
      expect((named[i] - named[i - 1]).abs(), lessThanOrEqualTo(FolderLook.keyShift), reason: '이웃 장면 사이에 ${named[i - 1]} → ${named[i]}');
    }
  });

  // 감독 고름 2026-10-26 ② '구멍만 꼴 더 작게': 띠 시작 + 35보다 좁은 띠(등불 넓게 검은물 의병 · 남강 임시정부의 '○ 등불 부흥 운동' · 룸 '○ 아홉 불씨 할거')의
  // 열쇠표가 통째로 빠져 그릇 이름 · 펼침 단추가 없어지던 것 — 제자리에 구멍만 꼴(12)이 들면 그것, 아니면 띠 시작 + 4의 더 작은 구멍만 꼴(10), 그래도 안 들면 없다.
  test('좁은 띠의 열쇠표는 빠지지 않고 띠 안에 더 작은 구멍만 꼴로 — 누르면 그릇 · 띠 밖으로 내밀지 않음 · 안 들면 없다', () async {
    final seen = <double, (String, double, double, double)?>{};
    for (final px in [200.0, 40.0, 30.0, 24.0, 18.0, 14.0]) {
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(1, 0, 12 * m, 12 * m + px / ppm, '검은물 의병')
        ..item(ScopeMarks.secKey, 601, 0, 12 * m, 12 * m + px / ppm, ref: 1, name: '등불 부흥 운동', color: 0xa27e76, text2: 's-revive');
      final (scene, painter) = make(b.build(), 1);
      addTearDown(scene.dispose);
      final notes = await notesOf(scene, painter, '열쇠표');
      final l = scene.controller.view.xOf(12 * m), r = scene.controller.view.xOf(12 * m + px / ppm);
      if (notes.isEmpty) {
        seen[px] = null;
        continue;
      }
      expect(notes.length, 1, reason: '$px: $notes');
      final cut = notes.single.lastIndexOf(' ');
      final v = nums(notes.single.substring(cut + 1));
      final k = (notes.single.substring(0, cut).trim(), v[0], v[1], v[2]);
      seen[px] = k;
      expect(k.$2, greaterThanOrEqualTo(l), reason: '$px: 띠 시작 앞으로 내밀지 않는다');
      expect(k.$2 + k.$4, lessThanOrEqualTo(r - 4 + .01), reason: '$px: 띠 끝 − 4 안');
      final h = k.$4 == FolderLook.keyMini ? FolderLook.keyMini : FolderLook.keyH;
      final hit = painter.links.hitLinks(k.$2 + k.$4 / 2, k.$3 + h / 2);
      expect((hit?.kind, hit?.scope), (LinkHitKind.scopeButton, 's-revive'), reason: '$px: 누르면 그 그릇');
    }
    expect(seen[200]!.$1, '등불 부흥 운동', reason: '넉넉한 띠는 이름째');
    expect((seen[40]!.$1, seen[40]!.$4), ('', FolderLook.keyStub), reason: '띠 시작 + 35 이상이면 제자리 구멍만(12)');
    for (final px in [30.0, 24.0, 18.0]) {
      final k = seen[px];
      expect(k, isNotNull, reason: '$px: 예전에는 통째로 빠졌다');
      expect((k!.$1, k.$4), ('', FolderLook.keyMini), reason: '$px: 더 작은 구멍만 꼴');
      expect(k.$2, closeTo(SceneView.gutter + 2 * m * ppm + FolderLook.keyMiniFrom, 1), reason: '$px: 띠 시작 + 4');
    }
    expect(seen[14], isNull, reason: '작은 꼴도 들지 않으면 없다(띠 밖 돌출 금지)');
  });

  // 0.1.1 1배 '새로 생긴 것' 1(판 3.1 동아시아 동예 · 옥저 · 부여 · 감독 자료 부여 · 북옥저의 꼴): 띠 시작이 화면 안인 띠에서 탭 · 획이 제자리를 막고
  // 제자리 구멍만까지 막으면 열쇠표가 통째로 빠졌다. 이제 띠에 매인 고정 자리(제자리 + 16 · 32 · 48 · 띠 시작 + 4)의 구멍만 꼴로 선다 —
  // 탭을 한 장면씩 옮겨도 빠지지 않고, 그 몇 자리 밖으로는 가지 않으며(탭을 따라가지 않음), 탭과 4 넘게 떨어지고 띠 안이다.
  test('띠 시작이 화면 안인 열쇠표는 탭이 제자리를 막아도 빠지지 않고 띠에 매인 고정 자리에 — 탭과 겹치지 않음 · 띠 안', () async {
    Uint8List tile(double? hostEnd) {
      final b = TileBuilder(level: 9, x: 0, chunk: 0)
        ..band(1, 0, 11 * m, 19 * m, '옥저')
        ..item(ScopeMarks.secKey, 602, 0, 11 * m, 19 * m, ref: 1, name: '원삼국 시대', color: 0xa27e76, text2: 's-three');
      if (hostEnd != null) b.item(BandLayer.sectionHostTab, 52, 0, 11 * m, hostEnd, ref: 1, name: '위만조선', color: 0x8b6f47, a: 1, d: 99, text2: 'p/wiman');
      return b.build();
    }

    final (bare, barePainter) = make(tile(null), 1);
    addTearDown(bare.dispose);
    final home = keysOf(await notesOf(bare, barePainter, '열쇠표')).single;
    final bandL = bare.controller.view.xOf(11 * m), bandR = bare.controller.view.xOf(19 * m);
    expect(home.$2, bandL + FolderLook.keyFrom + 3, reason: '제자리 = 띠 시작 + 16 + 3');
    final fixed = {home.$2, for (int k = 1; k <= 3; k++) home.$2 + k * FolderLook.keyShift, (bandL + FolderLook.keyMiniFrom).roundToDouble()};
    var aside = 0;
    for (var px = 300.0; px >= 30; px -= 4) {
      final (scene, painter) = make(tile(11 * m + px / ppm), 1);
      addTearDown(scene.dispose);
      final keys = keysOf(await notesOf(scene, painter, '열쇠표'));
      final tabs = [for (final n in painter.debugSink.notes['상국탭'] ?? const <Object>[]) nums('$n'.split(' ').firstWhere((p) => RegExp(r'^-?\d+,-?\d+$').hasMatch(p)))];
      expect(keys, hasLength(1), reason: '탭 끝 $px: 띠가 넉넉한데 열쇠표가 빠졌다 · 탭 $tabs');
      final k = keys.single;
      if (k.$1.isEmpty) {
        expect(fixed.contains(k.$2), isTrue, reason: '탭 끝 $px: 구멍만 ${k.$2}가 고정 자리 $fixed 밖(탭을 따라감)');
        if (k.$2 != home.$2) aside++;
      } else {
        expect(k.$2 - home.$2, inInclusiveRange(0, FolderLook.keyShift), reason: '탭 끝 $px: 이름째는 제자리 + 16 안');
      }
      expect(k.$2 >= bandL && k.$2 + k.$3 <= bandR - 4, isTrue, reason: '탭 끝 $px: 띠 밖');
      for (final tab in tabs) {
        final (tl, tr) = (tab[0] / 10, (tab[0] + tab[1]) / 10);
        expect(k.$2 + k.$3 + FolderLook.keyGap <= tl || k.$2 >= tr + FolderLook.keyGap, isTrue, reason: '탭 끝 $px: 열쇠표 ${k.$2} ~ ${k.$2 + k.$3} · 탭 $tl ~ $tr');
      }
    }
    expect(aside, greaterThan(0), reason: '탭이 정말 제자리 구멍만까지 막았다');
  });
}

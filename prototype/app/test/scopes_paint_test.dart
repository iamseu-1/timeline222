import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/scene/color_mix.dart' show mixOklab, over, withAlpha;
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/levels.dart';
import 'package:archive_prototype/scene/paint/bands.dart' show BandLayer, LidLook, TagLook;
import 'package:archive_prototype/scene/paint/gutter.dart' show Gut, GutLook, GutterHitKind;
import 'package:archive_prototype/scene/paint/ink.dart';
import 'package:archive_prototype/scene/paint/links.dart' show LinkLayer;
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/paint/scopes.dart';
import 'package:archive_prototype/scene/paint/small_tags.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/text_paragraph.dart' show TextLook;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';
import 'support/tile_builder.dart';

// 대범위 층(lib/scene/paint/scopes.dart)의 검사 — 상자(과제 7 걸음 2 · 아래 [boxTests]) · 선반 줄(과제 7 걸음 4 · [shelfTests])과 서고 흠 고침.
// 서고 흠 고침 — 4단계 감독 고름 G5 #8 흠 라(2026-10-25 · 차례 걸음 13 · 스위치 `flaw` ·
// 고르기 판 `.claude/research/stage4-choose/themes/g-g5-8.js`의 hangThreads · closedFolder fix · 기준 그림 out/shots/g58-ra.png):
//   ① 둘째 줄 매듭 — 펼친 그릇의 둘째 줄부터 매듭 자리에 그릇 너비의 가로대(1px · 먹 12) · 첫 줄은 그대로 · 가장 안쪽 그릇만 · 띠보다 뒤(글자 · 탭이 위).
//   ③ 접힌 폴더 몸통 — 작은 꼬리표가 몸통 안 세로 가운데 · 제 해 자리 · 끝에 '+n'(n = 구성원 수 − 놓은 꼬리표 수) · 짧은 실 없음.
// ②(고른 띠의 테가 받침 카드를 감쌈)는 띠 층의 몫이라 bands_paint_test.dart.

const m = 1000000.0;
final ppm = 32 / bucketMinutes(9);
double px(double pixels) => pixels / ppm;

/// 줄 하나(왼쪽 칸 검사와 같은 꼴). [raised]면 위로 솟는 줄(받침 카드 · 상국 탭 — 옛 셈 `fig_wide` 비트 14 · 비트 3 = 기간 막대 단 1이 실렸다는 표시).
Map<String, dynamic> row(int id, {bool raised = false}) => {
  'id': id, 'height': 80, 'band_top': 19, 'band_h': 61, 'dyn_top': -1, 'lead_top': -1,
  'cab_top': -1, 'text_top': 40, 'text_lines': 1, 'rail_top': -1, 'organ_top': -1,
  'kind': 0, 'group_start': 0, 'scope_pad': 0, 'phase': 0, 'rank': 0,
  'cats': <int>[], 'fig': 0, 'fig_wide': raised ? (1 << 3) | (1 << 14) : 0, 'dep': 0, 'zones': 0, 'hem': 0,
};

/// 그릇 변형 하나(계약 3-2절) — [rows]를 차례대로 한 가지로 모은다(사슬은 번호 차례 그대로). [depth]는 가지 나무의 깊이.
Map<String, dynamic> scopeVariant(int id, String uid, String name, List<int> rows, {int depth = 0}) => {
  'id': id, 'key': 'scope:$uid', 'kind': 2, 'track': 1, 'band': 0, 'uid': uid, 'name': name,
  'rows': [
    for (final (i, r) in rows.indexed)
      {'row': r, 'after': r - 1, 'ord': 0, 'new': 0, 'scope_pad': i == 0 ? 16 : 0, 'group_start': i == 0 ? 1 : 0},
    {'row': rows.last + 1, 'after': rows.last, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
  ],
  'groups': [
    {'key': '__scope:$uid', 'depth': depth, 'name': name, 'color': 0xd4a39b, 'kind': 2, 'rows': rows},
  ],
};

/// 줄 0 ~ 7의 트랙 하나 + 그릇 변형들. [raised]의 줄은 위로 솟는 줄.
SceneLayout layoutOf(List<Map<String, dynamic>> variants, {Set<int> raised = const {}}) => SceneLayout.fromJson({
  'packs': [{'id': 1, 'name': '등불 기록집', 'events': 0}],
  'tracks': [
    {'id': 1, 'pack': 1, 'ord': 0, 'name': '하연', 'color': 0xa0bcc5, 'rows': [for (int r = 0; r < 8; r++) row(r, raised: raised.contains(r))]},
  ],
  'epochs': [],
  'variants': variants,
})..reduceMotion = true;

/// 1920 × 1080 · 단계 9의 타일 하나(x 1)로 장면을 만든다. 보는 범위의 왼쪽 끝 = 타일 시작.
(TimelineScene, TimelinePainter) make(SceneLayout layout, Uint8List tile) {
  final controller = TimelineController()
    ..reduceMotion = true
    ..resize(1920, 1080)
    ..setExtent(-2000 * m, 2000 * m)
    ..setContentHeight(1000);
  final origin = tileOrigin(9, 1).toDouble();
  final scene = TimelineScene(
    controller: controller,
    layout: layout,
    fetchTile: (level, x, chunk, packs) async => level == 9 && x == 1 && chunk == 0 ? tile : TileBuilder(level: level, x: x, chunk: chunk).build(),
    ask: (query) async {
      if (query['op'] == 'rows_near') {
        // 모든 줄을 편다 — 선반 시험의 새 줄 8 · 9까지(없는 줄 번호는 쓰이지 않는다).
        final all = [for (int r = 0; r < 10; r++) r];
        return {'near': all, 'far': all};
      }
      return {};
    },
  );
  scene.hide.add('fade');
  scene.applyLayoutToView();
  controller.showRange(origin, origin + (1920 - scene.layout.gutterWidth) / ppm);
  return (scene, TimelinePainter(scene, text: unbudgetedText())..debug = true);
}

void paint(TimelinePainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  recorder.endRecording().dispose();
}

/// 타일 · 글자 폭이 모두 준비될 때까지 장면을 돌린다.
Future<void> settle(TimelineScene scene, TimelinePainter painter) async {
  for (int i = 0; i < 40; i++) {
    paint(painter);
    await pumpEventQueue();
    scene.tick(16);
  }
  painter.debugSink.clear();
  paint(painter);
}

Future<ByteData> render(TimelinePainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(1920, 1080));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1920, 1080);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  picture.dispose();
  image.dispose();
  return data;
}

List<String> noted(TimelinePainter painter, String key) => [for (final v in painter.debugSink.notes[key] ?? const <Object>[]) '$v'];

/// '3 343.0,201.0,1090.0' 같은 기록을 숫자로.
List<double> nums(String text) => [for (final s in text.split(RegExp('[ ,]'))) double.tryParse(s) ?? double.nan].where((v) => !v.isNaN).toList();

/// 앱 틀(archive_app `_pressScope`)이 그릇 누름 번호 [press]로 넣을 보기 상태 — [ScopeLayer.actionOf]로 가른다(켜고 끄기는 null — 이 시험들이 쓰지 않음).
ViewState? pressed(SceneLayout layout, String uid, int press, [ViewState? from]) => switch (ScopeLayer.actionOf(press)) {
  (ScopePress.fold, _) => layout.viewForScopeFold(uid, from),
  (ScopePress.state, final ScopeState state) => layout.viewForScopeState(uid, state, from),
  _ => null,
};

/// 폴더 · 상자 기록('이름 상태 왼쪽,위,너비,높이')의 네 수.
List<double> boxOf(TimelinePainter painter, String kind, String name) => nums(noted(painter, kind).firstWhere((s) => s.startsWith('$name ')).substring(name.length));

/// 그 줄의 매다는 실 매듭 자리(관계선 층 `_thread`와 같은 셈 — 구멍 높이에서 되돌린 띠 윗변 − 위 틈 + 3).
double knotYOf(TimelineScene scene, int r) {
  final layout = scene.layout, v = scene.controller.view;
  final bandTop = v.yOf(layout.rowTop(r) + layout.geo(r).bandTop + TagLook.holeY) - TagLook.holeY;
  return (bandTop - layout.tabOf(r) + FolderLook.knotDrop).roundToDouble();
}

/// 그릇 [uid](구역 23 — text2 = 'uid␟성격' · 성격은 [label])와 그 안 줄 [rows]의 띠 · 구멍 네모(구역 20)를 실은 타일. 띠 r은 x = [startOf](r)부터.
TileBuilder scopeTile(List<(String, String, int, int, double, double, int)> scopes, List<int> rows, double Function(int) startOf, {String label = '시대'}) {
  final t = TileBuilder(level: 9, x: 1, chunk: 0);
  for (final (i, (uid, name, first, last, x0, x1, count)) in scopes.indexed) {
    t.item(ScopeLayer.secScope, 1 + i, first, px(x0), px(x1), row2: last, name: name, color: 0xd4a39b, b: count, text2: '$uid\u001f$label');
  }
  for (final r in rows) {
    t.band(10 + r, r, px(startOf(r)), px(1400), '나라 $r', color: 0xacb4ca);
    t.item(LinkLayer.secSquare, 100 + r, r, px(startOf(r)), px(1400), ref: 10 + r, name: '나라 $r', color: 0xacb4ca);
  }
  return t;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(PaintPick.reset);
  group('조감의 그릇 이름표', birdLabelTests);
  group('상자', boxTests);
  group('선반 줄', shelfTests);

  group('흠 ① 둘째 줄 매듭의 가로대', () {
    /// 그릇 s2(줄 2 ~ 4 · 몸통 x 100 ~ 1500) · 줄 3은 솟는 줄이라 그 띠에 받침 카드 · 상국 탭(구역 47)이 선다.
    Future<(TimelineScene, TimelinePainter)> open() async {
      final t = scopeTile([('s2', '남곡 할거', 2, 4, 100, 1500, 3)], [2, 3, 4], (r) => 140.0 + 60 * r)
        ..item(BandLayer.sectionHostTab, 501, 3, px(320), px(1400), ref: 13, name: '하연 왕국', color: 0x8b6f47, a: 1, d: 99, text2: 'p/hayeon');
      final (scene, painter) = make(layoutOf([scopeVariant(1, 's2', '남곡 할거', [2, 3, 4])], raised: {3}), t.build());
      addTearDown(scene.dispose);
      expect(scene.layout.openScope('s2', true), isTrue);
      scene.controller.setContentHeight(scene.layout.totalHeight);
      await settle(scene, painter);
      expect(scene.layout.scopeStateOf('s2'), ScopeState.open);
      return (scene, painter);
    }

    test('둘째 줄부터 매듭 자리(띠 윗변 − 위 틈 + 3)에 몸통 안 왼 + 3 ~ 오른 − 3의 가로대 하나씩 — 첫 줄은 없다', () async {
      final (scene, painter) = await open();
      final folder = boxOf(painter, '폴더', '남곡 할거');
      final left = folder[0], right = folder[0] + folder[2];
      final rails = noted(painter, '가로대');
      expect([for (final s in rails) nums(s).first.toInt()], [3, 4], reason: '그릇의 첫 줄(2)은 몸통 윗변에 매듭 — 가로대 없음');
      for (final s in rails) {
        final v = nums(s), r = v[0].toInt();
        expect(v[2], knotYOf(scene, r), reason: '줄 $r: 매듭과 같은 자리');
        expect(v[1], left + FolderLook.railInset, reason: '줄 $r: 몸통 왼쪽 + 3');
        expect(v[1] + v[3], right - FolderLook.railInset, reason: '줄 $r: 몸통 오른쪽 − 3');
      }
      expect(scene.layout.tabOf(3), greaterThan(scene.layout.tabOf(4)), reason: '솟는 줄은 위 틈이 더 크다 — 가로대도 그만큼 위');
    });

    test('픽셀: 바뀐 곳은 가로대 줄뿐 — 매듭(실의 점)과 상국 탭은 가로대 위에 그대로 · 스위치 flaw를 끄면 예전 그림', () async {
      final (scene, painter) = await open();
      final on = await render(painter);
      final rails = {for (final s in noted(painter, '가로대')) nums(s)[2].toInt(): nums(s)};
      final squares = [for (final s in noted(painter, '네모')) if (s.startsWith('건국 ')) nums(s)];
      final tabs = [for (final s in noted(painter, '상국탭')) nums(s)];
      expect(tabs, hasLength(1), reason: '솟는 줄 3의 상국 탭');
      PaintPick.flaw = false;
      painter.debugSink.clear();
      final off = await render(painter);
      expect(noted(painter, '가로대'), isEmpty);
      int at(ByteData p, int x, int y) => p.getUint32((y * 1920 + x) * 4);
      final changedRows = <int>{};
      var changed = 0;
      for (int y = 0; y < 1080; y++) {
        for (int x = 0; x < 1920; x++) {
          if (at(on, x, y) != at(off, x, y)) {
            changedRows.add(y);
            changed++;
          }
        }
      }
      expect(changedRows, rails.keys.toSet(), reason: '가로대 줄 밖은 한 픽셀도 바뀌지 않는다');
      expect(changed, greaterThan(1000));
      for (final MapEntry(key: y, value: v) in rails.entries) {
        final xa = v[1].toInt(), xb = (v[1] + v[3]).toInt();
        expect(at(on, xa, y), isNot(at(off, xa, y)), reason: '줄 ${v[0]}: 가로대 왼쪽 끝');
        expect(at(on, xb - 1, y), isNot(at(off, xb - 1, y)), reason: '줄 ${v[0]}: 가로대 오른쪽 끝');
        expect(at(on, xa - 1, y), at(off, xa - 1, y), reason: '줄 ${v[0]}: 안쪽 겹선 밖은 그대로');
        expect(at(on, xb, y), at(off, xb, y), reason: '줄 ${v[0]}: 안쪽 겹선 밖은 그대로');
      }
      // 매듭(지름 3 — 가운데 줄 세 픽셀은 짙게 칠함)은 가로대 위에 걸린다: 그 줄의 매듭 픽셀은 켜고 끔이 같다.
      expect(squares, hasLength(3), reason: '줄마다 구멍 하나(기록: 띠 · 구멍 x · 구멍 y)');
      for (final sq in squares) {
        final r = sq[0].toInt() - 10;
        if (r < 3) continue; // 첫 줄의 매듭은 몸통 윗변 + 1(가로대 없음)
        final x = (sq[1] - .5).round(), y = knotYOf(scene, r).toInt();
        for (final dx in [-1, 0, 1]) {
          expect(at(on, x + dx, y), at(off, x + dx, y), reason: '줄 $r 매듭은 가로대 위');
        }
        expect(at(on, x + 6, y), isNot(at(off, x + 6, y)), reason: '줄 $r 매듭 옆은 가로대');
      }
      // 상국 탭(솟는 줄 3 — 탭 윗변이 가로대 줄)은 가로대보다 위: 탭 윗변(왼쪽 위 모따기 4 뒤)의 픽셀은 그대로 — 탭 테 빛깔(설계 4-6 #11 글자를 덮지 않음).
      final tab = tabs.single, y3 = knotYOf(scene, 3).toInt();
      final tx = tab[1] / 10, tw = tab[2] / 10;
      expect(y3, scene.controller.view.yOf(scene.layout.rowTop(3) + scene.layout.geo(3).bandTop) - BandLayer.sheetRise + 1 - 1 - TagLook.tabH, reason: '가로대 줄 = 탭 윗변');
      for (int x = (tx + TagLook.tabCham).ceil(); x < tx + tw - 1; x++) {
        expect(at(on, x, y3), at(off, x, y3), reason: '상국 탭 x $x');
      }
      // 탭의 모따기 귀 바깥(탭 밖)은 가로대가 보인다 — 탭이 가로대를 지운 것이 아니라 위에 얹혔다.
      expect(at(on, tx.floor(), y3), isNot(at(off, tx.floor(), y3)));
    });

    test('가로대는 그 줄을 품은 가장 안쪽 그릇만 — 상자 안의 줄은 상자 너비 · 상자 첫 줄은 뚜껑 밑선(가로대 없음) · 접힌 그릇은 없음', () async {
      // 바깥 폴더 s2(줄 2 ~ 5) 안에 상자 s3(줄 4 ~ 5 · x 400 ~ 1300).
      final t = scopeTile([('s2', '남곡 할거', 2, 5, 100, 1500, 4), ('s3', '서안 제후', 4, 5, 400, 1300, 2)], [2, 3, 4, 5], (r) => r < 4 ? 140.0 + 60 * r : 440.0 + 60 * r);
      final layout = layoutOf([scopeVariant(1, 's2', '남곡 할거', [2, 3, 4, 5]), scopeVariant(2, 's3', '서안 제후', [4, 5], depth: 1)]);
      final (scene, painter) = make(layout, t.build());
      addTearDown(scene.dispose);
      expect(layout.openScope('s2', true), isTrue);
      expect(layout.openScope('s3', true), isTrue);
      scene.controller.setContentHeight(layout.totalHeight);
      await settle(scene, painter);
      expect((layout.scopeDepthOf('s2'), layout.scopeDepthOf('s3')), (0, 1), reason: '상자는 폴더 안');
      final folder = boxOf(painter, '폴더', '남곡 할거'), box = boxOf(painter, '상자', '서안 제후');
      final rails = {for (final s in noted(painter, '가로대')) nums(s)[0].toInt(): nums(s)};
      expect(rails.keys.toList()..sort(), [3, 5], reason: '줄 2 = 폴더 첫 줄 · 줄 4 = 상자 첫 줄');
      expect(rails[3]![1], folder[0] + FolderLook.railInset, reason: '줄 3은 폴더 너비');
      // 상자는 안쪽 겹선이 없어 가로대가 테 바로 옆(1)부터 — 맞닿음(감독 결정 2026-10-25 · 꼴 off면 예전 3 · joints_paint_test.dart).
      expect(rails[5]![1], box[0] + 1, reason: '줄 5는 상자 너비(폴더 가로대는 긋지 않음)');
      expect(rails[5]![1] + rails[5]![3], box[0] + box[2] - 1);
      // 상자를 접으면 그 줄들은 상자 하나로 모여 가로대가 없다(폴더의 둘째 줄 3만).
      expect(layout.foldVariantGroup(0, '__scope:s3', true), isTrue);
      scene.controller.setContentHeight(layout.totalHeight);
      await settle(scene, painter);
      expect(layout.scopeStateOf('s3'), ScopeState.closed);
      expect([for (final s in noted(painter, '가로대')) nums(s).first.toInt()], [3]);
    });
  });

  group('흠 ③ 접힌 폴더 몸통', () {
    /// 폴더 s2(줄 2 ~ 4 · 구성원 [count]) — 접으면 줄 2 ~ 4가 줄 2로 모이고 그 띠(구역 45)가 작은 꼬리표로 선다. [bands]는 (줄 · 시작 px · 이름).
    Future<(TimelineScene, TimelinePainter)> closed(int count, List<(int, double, String)> bands, {double x1 = 1500}) async {
      final t = TileBuilder(level: 9, x: 1, chunk: 0)
        ..item(ScopeLayer.secScope, 1, 2, px(100), px(x1), row2: 4, name: '남곡 할거', color: 0xd4a39b, b: count, text2: 's2\u001f시대');
      for (final (i, (r, x0, name)) in bands.indexed) {
        t.band(10 + i, r, px(x0), px(x1 - 20), name, color: 0xacb4ca);
        t.item(45, 200 + i, r, px(x0), px(x1 - 20), ref: 10 + i, name: name, color: 0xacb4ca);
      }
      final layout = layoutOf([scopeVariant(1, 's2', '남곡 할거', [2, 3, 4])]);
      final (scene, painter) = make(layout, t.build());
      addTearDown(scene.dispose);
      expect(layout.openScope('s2', true), isTrue);
      expect(layout.foldVariantGroup(0, '__scope:s2', true), isTrue);
      scene.controller.setContentHeight(layout.totalHeight);
      await settle(scene, painter);
      expect(layout.scopeStateOf('s2'), ScopeState.closed);
      return (scene, painter);
    }

    List<DebugLabel> tags(TimelinePainter painter) => [for (final l in painter.debugLabels) if (l.kind == 'folderTag') l];

    /// 작은 꼬리표(또는 +n 칩)의 너비 — 글 폭(8.5 굵게) + 15를 반올림(SmallTags의 셈).
    double widthOf(TimelinePainter painter, String text) => (painter.text.widthOf(text, const TextLook(SmallTags.size, ui.FontWeight.w700, 0xff000000))! + 15).roundToDouble();

    /// 작은 꼬리표 글의 위(SmallTags.paint와 같은 셈 — 세로 가운데 [mid]).
    double textTop(double mid) => Gut.textTopAt(mid - SmallTags.size * Gut.lineRatio / 2, SmallTags.size * Gut.lineRatio, SmallTags.size);

    test('작은 꼬리표가 몸통(어깨 탭 아래) 안 세로 가운데 · 제 해 자리에 서고 끝에 +n(구성원 6 − 놓은 셋) — 몸통 위에는 없다', () async {
      final (scene, painter) = await closed(6, [(2, 160, '은등 상단'), (3, 420, '그믐 결사'), (4, 700, '붉은솔 군벌')]);
      final folder = boxOf(painter, '폴더', '남곡 할거');
      final body = folder[1] + G.folderTab, bottom = folder[1] + folder[3], mid = (body + bottom) / 2;
      final got = tags(painter);
      expect([for (final l in got) l.text], ['은등 상단', '그믐 결사', '붉은솔 군벌', '+3']);
      final view = scene.controller.view, origin = tileOrigin(9, 1).toDouble();
      for (final l in got) {
        expect(l.at.dy, textTop(mid), reason: '${l.text}: 몸통 세로 가운데');
        expect(l.at.dy, greaterThan(body), reason: '${l.text}: 몸통 안');
      }
      // 제 해 자리: 꼬리표 왼쪽 = 띠 시작(구멍 · 이름은 그 + 9).
      for (final (i, x0) in [160.0, 420.0, 700.0].indexed) {
        expect(got[i].at.dx, view.xOf(origin + px(x0)).roundToDouble() + 9, reason: got[i].text);
      }
      // +n은 마지막 꼬리표 오른쪽 + 4(칩 글은 칩 왼쪽 + 5 · 꼬리표 글은 + 9).
      final last = got[2], chip = got[3];
      expect(chip.at.dx - 5, last.at.dx - 9 + widthOf(painter, last.text) + SmallTags.gap);
      expect(noted(painter, '폴더').single, contains('closed'));
      // 몸통 위(어깨 탭 오른쪽)의 짧은 실이 없다: 몸통 윗변 위 픽셀이 스위치를 끈 그림과 달리 꼬리표 · 실 없이 비었는지는 아래 '스위치' 검사가 본다.
    });

    test('앞 꼬리표에 묻힌 띠는 건너뛰어 끝의 +n이 세고 · 오른쪽 끝(몸통 오른쪽 − 28 — ▸ 자리 비킴)을 넘는 것도 +n에 든다', () async {
      // 둘째 띠는 첫 꼬리표 밑에서 시작 → 묻힘. 폴더가 좁아(x 100 ~ 470 — 꼬리표 끝 690) 넷째(붉은솔 군벌 · 660에서 시작)는 못 든다. 구성원 다섯 가운데 하나는 보는 때 밖.
      final (_, painter) = await closed(5, [(2, 160, '은등 상단'), (3, 170, '모래늑대 무리'), (4, 300, '그믐 결사'), (2, 420, '붉은솔 군벌')], x1: 470);
      final folder = boxOf(painter, '폴더', '남곡 할거');
      final got = tags(painter);
      expect([for (final l in got) l.text], ['은등 상단', '그믐 결사', '+3'], reason: '묻힌 하나 · 못 든 하나 · 보는 때 밖 하나 = 사이 칩 없이 끝에 +3');
      final right = folder[0] + folder[2] - FolderLook.closedArrow;
      expect(got.last.at.dx - 5 + widthOf(painter, got.last.text), lessThanOrEqualTo(right), reason: '끝 칩까지 ▸ 자리 앞');
      final x660 = 240 + 420.0;
      expect(x660 + widthOf(painter, '붉은솔 군벌'), greaterThan(right), reason: '넷째는 오른쪽 끝을 넘어 +n으로');
    });

    test('구성원을 다 놓으면 +n이 없다 · 스위치 flaw를 끄면 예전 — 탭 오른쪽 몸통 위 + 사이 칩', () async {
      final (_, painter) = await closed(2, [(2, 160, '은등 상단'), (3, 420, '그믐 결사')]);
      expect([for (final l in tags(painter)) l.text], ['은등 상단', '그믐 결사']);
      PaintPick.flaw = false;
      final (_, old) = await closed(2, [(2, 160, '은등 상단'), (3, 420, '그믐 결사')]);
      final folder = boxOf(old, '폴더', '남곡 할거');
      final body = folder[1] + G.folderTab;
      expect(noted(old, '접힌꼬리표'), isEmpty);
      for (final l in tags(old)) {
        expect(l.at.dy, lessThan(body), reason: '${l.text}: 예전에는 몸통 윗변 위');
      }
    });
  });
}

// 조감의 그릇 이름표(2026-10-25 조감 글자 겹침): 칩이 조감 머리(12) 안에서 아래 1px을 남긴다 — 예전(위 .5 · 높이 11)은 첫 띠 윗테와 0.5px만 띄었다.
void birdLabelTests() {
  test('조감: 칩(높이 10)은 대범위 윗테 밑 1px에서 시작해 첫 띠 윗테와 1px 띈다 — 글의 자리는 예전과 같다', () async {
    final t = scopeTile([('s2', '남곡 할거', 2, 4, 100, 1500, 3)], [2, 3, 4], (r) => 140.0 + 60 * r);
    final (scene, painter) = make(layoutOf([scopeVariant(1, 's2', '남곡 할거', [2, 3, 4])]), t.build());
    addTearDown(scene.dispose);
    expect(scene.layout.openScope('s2', true), isTrue);
    scene.layout.setConditions(scene.layout.conditions.copyWith(density: 2));
    scene.controller.setContentHeight(scene.layout.totalHeight);
    await settle(scene, painter);
    expect(noted(painter, '폴더'), isEmpty, reason: '조감은 폴더가 아니라 옛 둥근 테두리');
    final box = nums(noted(painter, '대범위').single), chip = nums(noted(painter, '대범위이름표').single);
    final band = painter.debugBands.firstWhere((b) => b.id == 12).rect;
    expect(band.top - box[1], scene.layout.metrics.scopeHead, reason: '조감 머리 12');
    expect(chip[1] - box[1], 1, reason: '윗테(1px) 바로 밑');
    expect(band.top - (chip[1] + ScopeLook.birdLabelHeight), 1, reason: '첫 띠 윗테와 1px 빈다');
    final name = painter.debugLabels.firstWhere((l) => l.kind == 'scope' && l.text == '남곡 할거');
    expect(name.at.dy, closeTo(box[1] + .6, 1e-9), reason: '9px 글줄(10.8)은 예전 그대로 위 + .6');
  });
}

// 상자(과제 7 걸음 2 — 안쪽 그릇 · 깊이 1 이상): 펼친 상자는 뚜껑 22(칠 먹 4% · 밑선 먹 12) 안의 흰 라벨 16 · 모따기 6 · 테 먹 25,
// 접힌 상자는 합쳐진 줄의 띠 자리(24)에 모따기 상자 한 줄(칠 먹 6 → 4 · 테 먹 30 → 25 · 위 + 6 밑선 먹 12 · 이름 · 수 · 작은 꼬리표 셋까지 + '+n' · ▸).
// 깊이 0 폴더는 그대로(합쳐진 줄 30 · 어깨 탭 20 · 라벨 종이 15 · 작은 꼬리표는 셋에서 멈추지 않음).
void boxTests() {
  /// 종이 위 고른 색(0xAARRGGBB) → 그린 그림의 RGBA(ByteData.getUint32 꼴).
  int rgba(int argb) => ((argb & 0xffffff) << 8) | (argb >>> 24);
  int at(ByteData p, num x, num y) => p.getUint32((y.toInt() * 1920 + x.toInt()) * 4);

  /// 줄 [y]의 [x0] ~ [x1](미포함)에서 색이 [argb]인 픽셀의 몫(날짜 눈금 · 글자가 지나는 칸을 견디게 몫으로 본다).
  double share(ByteData p, num y, num x0, num x1, int argb) {
    var n = 0, all = 0;
    for (var x = x0.toInt(); x < x1; x++, all++) {
      if (at(p, x, y) == rgba(argb)) n++;
    }
    return n / all;
  }

  /// 바깥 폴더 s2(줄 2 ~ 5 · 구성원 4) 안에 상자 s3(줄 4 ~ 5 · x 400 ~ 1300 · 구성원 5). 줄 4 · 5에 띠 넷(구역 45 — 접으면 작은 꼬리표).
  Future<(TimelineScene, TimelinePainter, SceneLayout)> nested({bool closed = false}) async {
    final t = scopeTile([('s2', '남곡 할거', 2, 5, 100, 1500, 4), ('s3', '서안 제후', 4, 5, 400, 1300, 5)], [2, 3, 4, 5], (r) => r < 4 ? 140.0 + 60 * r : 440.0 + 60 * r);
    for (final (i, (r, x0, name)) in [(4, 470.0, '은등 상단'), (5, 640.0, '그믐 결사'), (4, 820.0, '붉은솔 군벌'), (5, 1000.0, '모래늑대 무리')].indexed) {
      t.item(45, 300 + i, r, px(x0), px(x0 + 100), ref: 50 + i, name: name, color: 0xacb4ca);
    }
    final layout = layoutOf([scopeVariant(1, 's2', '남곡 할거', [2, 3, 4, 5]), scopeVariant(2, 's3', '서안 제후', [4, 5], depth: 1)]);
    final (scene, painter) = make(layout, t.build());
    addTearDown(scene.dispose);
    expect(layout.openScope('s2', true), isTrue);
    expect(layout.openScope('s3', true), isTrue);
    if (closed) expect(layout.foldVariantGroup(0, '__scope:s3', true), isTrue);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    expect((layout.scopeDepthOf('s2'), layout.scopeDepthOf('s3')), (0, 1));
    expect(layout.scopeStateOf('s3'), closed ? ScopeState.closed : ScopeState.open);
    return (scene, painter, layout);
  }

  test('펼친 상자: 뚜껑 22(칠 먹 4% · 밑선 먹 12 — 테 먹 25가 아님) · 안의 흰 라벨 16(위 + 3) · 모따기 6 귀', () async {
    final (_, painter, _) = await nested();
    final p = await render(painter);
    final b = boxOf(painter, '상자', '서안 제후');
    final left = b[0], top = b[1], right = b[0] + b[2], bottom = b[1] + b[3];
    expect(G.boxLid, 22);
    expect(G.boxHead, 24);
    // 뚜껑: 위 + 1 ~ 21은 칠 먹 4% · 위 + 22는 밑선 먹 12 · 그 아래는 뚜껑 밖(바깥 폴더의 칠). 라벨 오른쪽(+ 140 ~)에서 본다.
    for (final y in [top + 1, top + 11, top + 21]) {
      expect(share(p, y, left + 140, right - 20, CanvasInk.k4), greaterThan(.9), reason: '뚜껑 칠 줄 $y');
    }
    expect(share(p, top + G.boxLid, left + 1, right - 1, CanvasInk.k12), greaterThan(.9), reason: '뚜껑 밑선은 먹 12');
    expect(share(p, top + G.boxLid, left + 1, right - 1, CanvasInk.k25), lessThan(.1), reason: '예전의 테 먹 25가 아님');
    expect(share(p, top + G.boxLid + 1, left + 140, right - 20, CanvasInk.k4), lessThan(.1), reason: '밑선 아래는 뚜껑이 아님');
    expect(share(p, top, left + 6, right - 6, CanvasInk.k25), greaterThan(.9), reason: '윗변 테 먹 25');
    expect(share(p, bottom - 1, left + 6, right - 6, CanvasInk.k25), greaterThan(.9), reason: '아랫변 테 먹 25');
    // 모따기 6 귀(왼쪽 위 · 왼쪽 아래): 빗변 픽셀은 테 · 그 바깥은 비고 · 안쪽은 칠.
    expect(at(p, left + 5, top), rgba(CanvasInk.k25));
    expect(at(p, left + 4, top + 1), rgba(CanvasInk.k25));
    expect(at(p, left, top + 5), rgba(CanvasInk.k25));
    expect(at(p, left, top + 6), rgba(CanvasInk.k25), reason: '세로 변');
    expect(at(p, left + 5, top + 1), rgba(CanvasInk.k4), reason: '빗변 안쪽은 뚜껑 칠');
    for (final (x, y) in [(left, top), (left + 3, top + 1), (left, bottom - 1)]) {
      expect(at(p, x, y), isNot(anyOf(rgba(CanvasInk.k25), rgba(CanvasInk.k4))), reason: '귀 바깥 $x,$y');
    }
    expect(at(p, left + 5, bottom - 1), rgba(CanvasInk.k25));
    expect(at(p, left, bottom - 6), rgba(CanvasInk.k25));
    // 흰 라벨 16: 뚜껑 22 안 세로 가운데(위 + 3) · 테 먹 45 · 속 종이.
    final label = nums(noted(painter, '상자라벨').single.substring('서안 제후'.length));
    final (lx, ly, lw, lh) = (label[0], label[1], label[2], label[3]);
    expect([ly - top, lh], [3, ScopeLook.boxLabelH]);
    expect(ScopeLook.boxLabelH, 16);
    final x = lx + lw - 3;
    expect([at(p, x, ly), at(p, x, ly + lh - 1)], [rgba(CanvasInk.k45), rgba(CanvasInk.k45)], reason: '라벨 위아래 테');
    expect([at(p, x, ly + 1), at(p, x, ly + lh - 2)], [rgba(Look.paper), rgba(Look.paper)], reason: '라벨 속 종이');
    expect([at(p, x, ly - 1), at(p, x, ly + lh)], [rgba(CanvasInk.k4), rgba(CanvasInk.k4)], reason: '라벨 밖은 뚜껑');
    final name = painter.debugLabels.firstWhere((l) => l.kind == 'folder' && l.text == '서안 제후');
    expect(name.at.dy, closeTo(ly + (lh - FolderLook.nameSize * 1.2) / 2, 1e-9), reason: '이름 11은 라벨 세로 가운데');
    expect(painter.scopes.hitFolder(lx + 3, ly + 3), ('s3', 2), reason: '라벨을 누르면 접음');
    expect(noted(painter, '접힌상자'), isEmpty);
  });

  test('접힌 상자: 합쳐진 줄 24의 띠 자리에 모따기 상자 한 줄 — 칠 · 테 · 위 + 6 밑선 · 이름 · 수 · 꼬리표 셋 + "+2" · ▸ · 누름 자리', () async {
    final (scene, painter, layout) = await nested(closed: true);
    final p = await render(painter);
    expect(layout.closedBoxRowOf('s3'), 4, reason: '줄 4 · 5가 줄 4로 모인다');
    expect(layout.geo(4).bandHeight, G.boxClosed);
    final b = boxOf(painter, '상자', '서안 제후');
    final left = b[0], top = b[1], right = b[0] + b[2], bottom = b[1] + b[3];
    final view = scene.controller.view;
    expect(top, view.yOf(layout.rowTop(4) + layout.geo(4).bandTop).roundToDouble(), reason: '틀 = 합쳐진 줄의 띠 자리');
    expect(b[3], 24);
    expect(noted(painter, '상자').single, contains('closed'));
    // 칠(먹 6 → 단계 4) · 테(먹 30 → 단계 25) · 위 + 6 밑선 먹 12. 글 · 꼬리표가 없는 줄(위 + 1 ~ 5 · 위 + 22)에서 본다.
    expect(CanvasInk.gray(ScopeLook.closedFill), CanvasInk.k4);
    expect(CanvasInk.gray(ScopeLook.closedEdge), CanvasInk.k25);
    for (final y in [top + 1, top + 5, top + 22]) {
      expect(share(p, y, left + 20, right - 20, CanvasInk.k4), greaterThan(.9), reason: '칠 줄 $y');
    }
    expect(share(p, top + 6, left + 1, right - 1, CanvasInk.k12), greaterThan(.9), reason: '밑선');
    expect(share(p, top, left + 6, right - 6, CanvasInk.k25), greaterThan(.9), reason: '윗변');
    expect(share(p, bottom - 1, left + 6, right - 6, CanvasInk.k25), greaterThan(.9), reason: '아랫변');
    expect([at(p, left + 5, top), at(p, left, top + 5), at(p, left, top + 12), at(p, left, bottom - 6), at(p, left + 5, bottom - 1), at(p, right - 1, top + 12)],
        everyElement(rgba(CanvasInk.k25)), reason: '모따기 빗변 · 세로 변');
    expect([at(p, left + 5, top + 1), at(p, left + 5, bottom - 2)], everyElement(rgba(CanvasInk.k4)), reason: '빗변 안쪽은 칠');
    for (final (x, y) in [(left, top), (left + 3, top + 1), (left, bottom - 1), (right - 1, top)]) {
      expect(at(p, x, y), isNot(anyOf(rgba(CanvasInk.k25), rgba(CanvasInk.k4))), reason: '귀 바깥 $x,$y');
    }
    // 이름 10 굵게(상자 왼쪽 + 8) · 수 10(이름 뒤 5) — 세로 가운데 위 + 14.5.
    final textTop = top + ScopeLook.closedMid - ScopeLook.closedText * 1.2 / 2;
    final name = painter.debugLabels.firstWhere((l) => l.kind == 'boxName');
    final count = painter.debugLabels.firstWhere((l) => l.kind == 'boxCount');
    expect([name.text, count.text], ['서안 제후', '5']);
    expect(name.at, Offset(left + ScopeLook.closedTextX, textTop));
    final nw = painter.text.widthOf('서안 제후', TextLook(ScopeLook.closedText, ui.FontWeight.w700, CanvasInk.k85))!;
    final cw = painter.text.widthOf('5', TextLook(ScopeLook.closedText, ui.FontWeight.w400, CanvasInk.k45))!;
    expect(count.at, Offset(left + ScopeLook.closedTextX + nw + ScopeLook.closedCountGap, textTop));
    // 작은 꼬리표: 셋까지 · 넷째(모래늑대 무리)는 끝의 +2(구성원 5 − 놓은 셋)가 센다 · 수 뒤 + 14부터 · 세로 가운데 위 + 14.5.
    final tags = [for (final l in painter.debugLabels) if (l.kind == 'boxTag') l];
    expect([for (final l in tags) l.text], ['은등 상단', '그믐 결사', '붉은솔 군벌', '+2']);
    final from = (count.at.dx + cw + ScopeLook.closedTagGap).roundToDouble();
    final origin = tileOrigin(9, 1).toDouble();
    expect(tags.first.at.dx - 9, math.max(from, view.xOf(origin + px(470)).roundToDouble()), reason: '첫 꼬리표는 수 뒤 14 · 제 해 자리 가운데 큰 쪽');
    for (final l in tags) {
      expect(l.at.dy, Gut.textTopAt(top + ScopeLook.closedMid - SmallTags.size * Gut.lineRatio / 2, SmallTags.size * Gut.lineRatio, SmallTags.size), reason: l.text);
    }
    // ▸: 오른쪽 − 22의 14 칸 가운데 · 세로 7 가로 4의 계단 삼각형 · 먹 50(단계 45).
    final arrowL = (right - ScopeLook.closedArrowX).roundToDouble(), ax = arrowL + 5, ay = top + 14;
    expect([at(p, ax, ay - 3), at(p, ax, ay), at(p, ax, ay + 3), at(p, ax + 3, ay)], everyElement(rgba(CanvasInk.k45)));
    expect([at(p, ax, ay - 4), at(p, ax, ay + 4), at(p, ax + 3, ay - 1), at(p, ax + 4, ay)], everyElement(rgba(CanvasInk.k4)), reason: '삼각형 밖은 칠');
    final chipW = (painter.text.widthOf('+2', const TextLook(SmallTags.size, ui.FontWeight.w700, 0xff000000))! + 15).roundToDouble();
    expect(tags.last.at.dx - 5 + chipW, lessThanOrEqualTo(right - ScopeLook.closedTagEnd), reason: '+n 칩은 오른쪽 − 26(▸ 자리) 앞');
    // 누름: 이름 · ▸는 펼침(상태 1) · 꼬리표 자리는 아무것도(오른쪽 클릭 차림표는 상자 안 어디서나 이 상자).
    final scopes = painter.scopes;
    expect(scopes.hitFolder(left + ScopeLook.closedTextX + 3, top + 14), ('s3', 1));
    expect(scopes.hitFolder(arrowL + 7, top + 14), ('s3', 1));
    expect(scopes.hitFolder(tags[1].at.dx + 5, top + 14), isNull);
    expect(scopes.scopeAt(tags[1].at.dx + 5, top + 14), ('s3', '서안 제후', ScopeState.closed), reason: '바깥 폴더보다 안쪽 상자');
    // 왼쪽 칸의 상자 이름은 상자 한 줄의 가운데(위 + 14)에 — 그림판 이름과 1.5px 안.
    final gut = painter.debugLabels.firstWhere((l) => l.kind == 'gutFolder' && l.text == '서안 제후');
    expect((gut.at.dy + GutLook.rowSize * 1.2 / 2) - (name.at.dy + ScopeLook.closedText * 1.2 / 2), inInclusiveRange(-1.5, 1.5));
    // 예전의 뚜껑 뒤 작은 꼬리표 · 흰 라벨은 없다.
    expect([for (final l in painter.debugLabels) if (l.kind == 'folderTag' || (l.kind == 'folder' && l.text == '서안 제후')) l.text], isEmpty);
    expect(noted(painter, '상자라벨'), isEmpty);
  });

  test('접힌 상자의 이름이 ▸ 앞에 들지 못하면 이름 · 수를 적지 않는다 · 꼬리표는 이름 자리부터', () async {
    // 상자 s3(x 400 ~ 450 — 상자 66px)는 이름 + ▸가 들지 못한다.
    final t = scopeTile([('s2', '남곡 할거', 2, 5, 100, 1500, 4), ('s3', '서안 제후', 4, 5, 400, 450, 2)], [2, 3, 4, 5], (r) => r < 4 ? 140.0 + 60 * r : 400.0);
    final layout = layoutOf([scopeVariant(1, 's2', '남곡 할거', [2, 3, 4, 5]), scopeVariant(2, 's3', '서안 제후', [4, 5], depth: 1)]);
    final (scene, painter) = make(layout, t.build());
    addTearDown(scene.dispose);
    layout.openScope('s2', true);
    layout.openScope('s3', true);
    layout.foldVariantGroup(0, '__scope:s3', true);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    expect(noted(painter, '상자').single, contains('closed'));
    expect([for (final l in painter.debugLabels) if (l.kind == 'boxName' || l.kind == 'boxCount') l.text], isEmpty);
    expect(noted(painter, '접힌상자').single, contains('이름 -'));
  });

  test('깊이 0 폴더는 그대로 — 접힌 폴더의 합쳐진 줄 30 · 머리 21 · 상자 기록 없음 · 작은 꼬리표는 셋에서 멈추지 않음 · 라벨 종이 15', () async {
    final t = TileBuilder(level: 9, x: 1, chunk: 0)
      ..item(ScopeLayer.secScope, 1, 2, px(100), px(1700), row2: 4, name: '남곡 할거', color: 0xd4a39b, b: 5, text2: 's2\u001f시대');
    for (final (i, (r, x0, name)) in [(2, 160.0, '은등 상단'), (3, 420.0, '그믐 결사'), (4, 700.0, '붉은솔 군벌'), (2, 980.0, '모래늑대 무리'), (3, 1260.0, '잿빛 결사')].indexed) {
      t.band(10 + i, r, px(x0), px(x0 + 200), name, color: 0xacb4ca);
      t.item(45, 200 + i, r, px(x0), px(x0 + 200), ref: 10 + i, name: name, color: 0xacb4ca);
    }
    final layout = layoutOf([scopeVariant(1, 's2', '남곡 할거', [2, 3, 4])]);
    final (scene, painter) = make(layout, t.build());
    addTearDown(scene.dispose);
    layout.openScope('s2', true);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    // 펼친 폴더: 어깨 탭 20 · 라벨 종이 15(몸통 윗변 위 2).
    final p = await render(painter);
    final folder = boxOf(painter, '폴더', '남곡 할거');
    final tab = nums(noted(painter, '폴더탭').single.split('라벨').last);
    expect(tab[1], folder[1] + G.folderTab - 2 - FolderLook.labelH, reason: '라벨 종이 15 · 몸통 윗변 위 2');
    final x = tab[0] + tab[2] - 3;
    expect([at(p, x, tab[1]), at(p, x, tab[1] + FolderLook.labelH - 1)], [rgba(CanvasInk.k45), rgba(CanvasInk.k45)]);
    expect(at(p, x, tab[1] + 1), rgba(Look.paper));
    // 접으면 합쳐진 줄 30(상자의 24가 아님) · 접힌상자 기록 없음 · 꼬리표 다섯 모두(셋에서 멈추지 않음).
    layout.foldVariantGroup(0, '__scope:s2', true);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    expect(layout.closedBoxRowOf('s2'), -1);
    expect(layout.geo(2).bandHeight, G.foldedGroup);
    expect(layout.geo(2).bandTop, 3 + 14 + 0 + G.folderHead, reason: '틈 3 + 민족 경계 14 + 탭 0 + 폴더 머리 21');
    expect(noted(painter, '상자'), isEmpty);
    expect(noted(painter, '접힌상자'), isEmpty);
    expect([for (final l in painter.debugLabels) if (l.kind == 'folderTag') l.text], ['은등 상단', '그믐 결사', '붉은솔 군벌', '모래늑대 무리', '잿빛 결사']);
  });
}

// 선반 줄(과제 7 걸음 4 · 메이커 서고 미리보기 css `.tl-shelf`): 선반 변형(kind 6 · `shelf:<uid>`)을 켠 그릇의 발에 더한 19 자리 —
// 그릇 아래 − 20의 1px 금(먹 12 · 왼쪽 + 6 ~ 오른쪽 − 6 · 화면에 잘린 쪽은 그림판 끝) · 그 밑 3의 작은 꼬리표 13(구역 59의 숨은 띠 · 시작 차례) · 끝 '+n'
// (n = 숨은 수 전체 − 놓은 수 — 보는 때 밖 · 묻힌 띠도 셈) · 줄을 누르면 펼침(상태 1) · 탭 라벨의 수 = 남은 수(구역 23 b) + 숨은 수.
// 손으로 만든 배치(variants_layout_test의 선반 시험 꼴): 그릇 s2의 그릇 변형은 줄 2 ~ 4 · 선반 변형은 그 셋을 빠지는 줄로 두고 새 줄 8 · 9를 가지로 쌓는다.
void shelfTests() {
  int at(ByteData p, num x, num y) => p.getUint32((y.toInt() * 1920 + x.toInt()) * 4);

  /// 줄 [y]의 [x0] ~ [x1](미포함)에서 [same]이 참인 픽셀의 몫(날짜 눈금이 지나는 칸을 견디게 몫으로 본다).
  double share(num x0, num x1, bool Function(int x) same) {
    var n = 0, all = 0;
    for (var x = x0.toInt(); x < x1; x++, all++) {
      if (same(x)) n++;
    }
    return n / all;
  }

  /// 숨긴 구성원 넷(그릇 안 차례 5 ~ 8) — 넷째(먼바다 상단)는 타일에 없다(보는 때 밖).
  const members = [('h/a', '검은물 의병'), ('h/b', '남강 임시정부'), ('h/c', '잿빛 결사'), ('h/d', '먼바다 상단')];

  /// 선반 변형 하나(계약 2-4절 · variants_layout_test `shelfSkeleton`의 꼴): 그릇 변형이 모으던 [gone]을 빠지는 줄(after −2 · ord −1)로 두고
  /// 다시 지은 새 줄 [rows]를 줄 [after] 뒤 가지로 쌓는다 · 가지 다음 줄은 [next](발 6) · 숨긴 구성원 [hidden](uid · 이름 — 답의 `shelf`).
  Map<String, dynamic> shelfVariant(int id, String uid, String name, List<int> gone, List<int> rows, int after, int next, List<(String, String)> hidden) => {
    'id': id, 'key': 'shelf:$uid', 'kind': 6, 'track': 1, 'band': 0, 'uid': uid, 'name': name,
    'rows': [
      for (final g in gone) {'row': g, 'after': -2, 'ord': -1, 'new': 0, 'scope_pad': 0, 'group_start': 0},
      for (final (i, r) in rows.indexed)
        {'row': r, 'after': i == 0 ? after : rows[i - 1], 'ord': 0, 'new': 1, 'scope_pad': i == 0 ? 16 : 0, 'group_start': i == 0 ? 1 : 0},
      {'row': next, 'after': rows.last, 'ord': 0, 'new': 0, 'scope_pad': 6, 'group_start': 0},
    ],
    'groups': [
      {'key': '__scope:$uid', 'depth': 0, 'name': name, 'color': 0xd4a39b, 'kind': 2, 'rows': rows},
    ],
    'shelf': [
      for (final (i, (u, n)) in hidden.indexed) {'uid': u, 'name': n, 'color': 0x8a9a7b, 'start': 0, 'end': 0, 'ord': 5 + i},
    ],
  };

  /// 줄 0 ~ 7 + 선반 변형의 새 줄 8 · 9(변형 2의 줄). [shelf]가 거짓이면 선반 변형도 새 줄도 없다(구성원 다섯 이하 — ✓만 선반).
  SceneLayout shelfLayout({bool shelf = true, List<(String, String)> hidden = members}) => SceneLayout.fromJson({
    'packs': [{'id': 1, 'name': '등불 기록집', 'events': 0}],
    'tracks': [
      {
        'id': 1, 'pack': 1, 'ord': 0, 'name': '하연', 'color': 0xa0bcc5,
        'rows': [for (int r = 0; r < 8; r++) row(r), if (shelf) for (final r in [8, 9]) {...row(r), 'variant': 2}],
      },
    ],
    'epochs': [],
    'variants': [
      scopeVariant(1, 's2', '남곡 할거', [2, 3, 4]),
      if (shelf) shelfVariant(2, 's2', '남곡 할거', [2, 3, 4], [8, 9], 1, 5, hidden),
    ],
  })..reduceMotion = true;

  /// 선반 변형을 켠 타일: 그릇(구역 23 — 가지 줄 8 ~ 9 · x [x0] ~ [x1] · b = 남은 수 3)과 남은 띠 둘 · 구역 59(가지 끝 줄 9 · a = 그릇 안 차례 · b = 숨은 수 4 ·
  /// text2 = 띠 uid)의 [tags](uid · 이름 · 시작 · 끝 px). 기본은 잿빛 결사가 타일에 두 조각으로 잘려 온 꼴(바깥 끝을 모아 900 → 1300 — 남강 임시정부의 1000보다 멀다).
  /// [label]은 그릇의 성격(구역 23 text2 — '동군연합'이면 폴더가 먹 · 과제 8).
  TileBuilder shelfTile({double x0 = 100, double x1 = 1500, List<(String, String, double, double)>? tags, String label = '시대'}) {
    final t = scopeTile([('s2', '남곡 할거', 8, 9, x0, x1, 3)], [8, 9], (r) => 140.0 + 60 * (r - 6), label: label);
    final list = tags ?? [('h/a', '검은물 의병', 300, 500), ('h/b', '남강 임시정부', 600, 1000), ('h/c', '잿빛 결사', 600, 900), ('h/c', '잿빛 결사', 900, 1300)];
    for (final (i, (uid, name, s, e)) in list.indexed) {
      final ord = 5 + members.indexWhere((m) => m.$1 == uid);
      t.item(ScopeLayer.secShelf, 400 + i, 9, px(s), px(e), ref: 60 + ord, name: name, color: 0x8a9a7b, a: ord, b: members.length, text2: uid);
    }
    return t;
  }

  /// 그릇 s2를 [state]로 둔 장면.
  Future<(TimelineScene, TimelinePainter, SceneLayout)> shelved({SceneLayout? layout, TileBuilder? tile, ScopeState state = ScopeState.shelf}) async {
    final l = layout ?? shelfLayout();
    final (scene, painter) = make(l, (tile ?? shelfTile()).build());
    addTearDown(scene.dispose);
    expect(l.setViewState(l.viewForScopeState('s2', state)), isTrue);
    scene.controller.setContentHeight(l.totalHeight);
    await settle(scene, painter);
    expect(l.scopeStateOf('s2'), state);
    return (scene, painter, l);
  }

  /// 선반줄 기록('이름 왼쪽,위,너비 숨음 n 꼬리표 …')의 (왼쪽 · 위 · 오른쪽 · 숨은 수).
  (double, double, double, int) shelfRowOf(TimelinePainter painter) {
    final v = nums(noted(painter, '선반줄').single.substring('남곡 할거'.length));
    return (v[0], v[1], v[0] + v[2], v[3].toInt());
  }

  List<DebugLabel> tags(TimelinePainter painter) => [for (final l in painter.debugLabels) if (l.kind == 'shelfTag') l];

  /// 작은 꼬리표(또는 +n 칩)의 너비 — 글 폭(8.5 굵게) + 15를 반올림(SmallTags의 셈).
  double widthOf(TimelinePainter painter, String text) => (painter.text.widthOf(text, const TextLook(SmallTags.size, ui.FontWeight.w700, 0xff000000))! + 15).roundToDouble();

  /// 금 [y] 밑 꼬리표의 세로 가운데(금 1 + 틈 3 + 꼬리표 13의 절반)와 그 글의 위(SmallTags.paint와 같은 셈).
  double midOf(double y) => y + 1 + FolderLook.shelfPad + SmallTags.height / 2;
  double textTop(double mid) => Gut.textTopAt(mid - SmallTags.size * Gut.lineRatio / 2, SmallTags.size * Gut.lineRatio, SmallTags.size);

  test('금: 그릇 아래(가지 끝 줄 + 발 7 + 19) − 20 · 왼쪽 + 6 ~ 오른쪽 − 6 · 1px 먹 12(안쪽 겹선과 같은 먹) — 위아래는 몸통 칠', () async {
    final (scene, painter, layout) = await shelved();
    expect([layout.isShelfOn('s2'), layout.variantKeys], [true, ['shelf:s2']]);
    expect(FolderLook.shelfRise, 20);
    expect([FolderLook.shelfInset, FolderLook.shelfPad, CanvasInk.step(FolderLook.shelfInk)], [6, 3, CanvasInk.a12], reason: '먹 12는 그림판 먹 단계에 있다');
    final p = await render(painter);
    final f = boxOf(painter, '폴더', '남곡 할거');
    final left = f[0], right = f[0] + f[2], bottom = f[1] + f[3];
    final v = scene.controller.view;
    expect(bottom, v.yOf(layout.rowTop(9) + layout.geo(9).height + G.folderFoot + G.shelfH).roundToDouble(), reason: '그릇 아래 = 가지 끝 줄 + 발 7 + 선반 19');
    final (xa, y, xb, hidden) = shelfRowOf(painter);
    expect([xa, y, xb, hidden], [left + 6, bottom - 20, right - 6, 4]);
    // 금 줄은 안쪽 겹선의 아랫변(아래 − 3 · 같은 먹 알파 · 같은 몸통 칠 위)과 같은 빛깔 · 금 위아래 줄은 몸통 칠이라 서로 같고 금과 다르다.
    final inner = bottom - 1 - FolderLook.inset;
    expect(share(left + 12, right - 12, (x) => at(p, x, y) == at(p, x, inner)), greaterThan(.9), reason: '금 = 먹 12');
    expect(share(left + 12, right - 12, (x) => at(p, x, y - 1) == at(p, x, y + 1) && at(p, x, y) != at(p, x, y + 1)), greaterThan(.9), reason: '금 위아래는 몸통 칠');
    // 금의 끝: 왼쪽 + 6 · 오른쪽 − 6 바깥은 몸통 칠(금 위 줄과 같음).
    expect([at(p, xa, y), at(p, xb - 1, y)], everyElement(isNot(at(p, xa, y - 1))), reason: '금의 양 끝 픽셀');
    expect(at(p, xa - 1, y), at(p, xa - 1, y - 1), reason: '금 왼쪽 밖');
    expect(at(p, xb, y), at(p, xb, y - 1), reason: '금 오른쪽 밖');
  });

  test('꼬리표: 금 밑 3 · 높이 13(아래 − 3) · 시작 차례(같으면 끝이 먼 것 먼저 — 타일에 잘려 온 조각은 바깥 끝을 모음) · 묻힌 띠 · 보는 때 밖도 끝 +n이 셈', () async {
    final (scene, painter, _) = await shelved();
    final f = boxOf(painter, '폴더', '남곡 할거');
    final bottom = f[1] + f[3];
    final (_, y, _, _) = shelfRowOf(painter);
    final got = tags(painter);
    // 잿빛 결사(600 ~ 1300)가 남강 임시정부(600 ~ 1000)보다 먼저 · 남강은 잿빛 결사 밑에 시작해 묻히고 · 먼바다 상단은 타일에 없다 → +2(숨은 4 − 놓은 2).
    expect([for (final l in got) l.text], ['검은물 의병', '잿빛 결사', '+2']);
    final mid = midOf(y);
    expect((mid - SmallTags.height / 2, mid + SmallTags.height / 2), (y + 4, bottom - 3), reason: '꼬리표 13은 금 밑 3 ~ 그릇 아래 − 3');
    for (final l in got) {
      expect(l.at.dy, textTop(mid), reason: '${l.text}: 세로 가운데');
    }
    // 제 해 자리: 꼬리표 왼쪽 = 띠 시작(색 꼬리표 글은 + 9 · 칩 글은 + 5).
    final view = scene.controller.view, origin = tileOrigin(9, 1).toDouble();
    expect(got[0].at.dx, view.xOf(origin + px(300)).roundToDouble() + 9);
    expect(got[1].at.dx, view.xOf(origin + px(600)).roundToDouble() + 9);
    expect(got[2].at.dx - 5, got[1].at.dx - 9 + widthOf(painter, '잿빛 결사') + SmallTags.gap, reason: '+n은 마지막 꼬리표 오른쪽 + 4');
    expect(noted(painter, '선반줄').single, contains('꼬리표 검은물 의병@'));
  });

  test('누름: 줄 전체(꼬리표 · +n · 빈 자리)는 펼침(상태 1) · 금 위 · 금 바깥은 아님 · 탭 라벨은 가지 접기 뒤집기(5 — 선반 기억에 듦) · 라벨 수 = 남은 3 + 숨은 4 · 펼침을 넣으면 선반 기억이 빠진다', () async {
    final (scene, painter, layout) = await shelved();
    final f = boxOf(painter, '폴더', '남곡 할거');
    final left = f[0], right = f[0] + f[2], bottom = f[1] + f[3];
    final (xa, y, xb, _) = shelfRowOf(painter);
    final got = tags(painter), mid = midOf(y), scopes = painter.scopes;
    expect(scopes.hitFolder(got[0].at.dx, mid), ('s2', 1), reason: '꼬리표');
    expect(scopes.hitFolder(got[2].at.dx, mid), ('s2', 1), reason: '+n');
    expect(scopes.hitFolder(right - 20, mid), ('s2', 1), reason: '줄의 빈 자리');
    expect(scopes.hitFolder(xa, y), ('s2', 1), reason: '금 자리부터');
    expect(scopes.hitFolder(xb - 1, bottom - FolderLook.shelfPad - 1), ('s2', 1), reason: '꼬리표 아래 끝까지');
    expect(scopes.hitFolder(xa + 40, y - 1), isNull, reason: '금 위는 띠 쪽');
    expect(scopes.hitFolder(left + 3, mid), isNull, reason: '금 왼쪽 밖');
    expect(scopes.hitFolder(xb + 1, mid), isNull, reason: '금 오른쪽 밖');
    expect(scopes.hitFolder(xa + 40, bottom - 2), isNull, reason: '그릇 아랫변 쪽');
    // 탭 라벨: 이름 · 수(남은 3 + 숨은 4) · 누르면 가지 접기 뒤집기(선반 기억에 든 그릇 — 과제 7 걸음 5 · 선반 기억을 남김).
    expect([for (final l in painter.debugLabels) if (l.kind == 'folder') l.text], ['남곡 할거', '7']);
    final tab = nums(noted(painter, '폴더탭').single.split('라벨').last);
    expect(scopes.hitFolder(tab[0] + 3, tab[1] + 3), ('s2', ScopeLayer.pressFold));
    // 왼쪽 칸의 폴더 이름은 펼친 폴더처럼 수 없이.
    expect([for (final l in painter.debugLabels) if (l.kind == 'gutFolder') l.text], ['남곡 할거']);
    expect([for (final l in painter.debugLabels) if (l.kind == 'gutFolderCount') l.text], isEmpty);
    // 줄을 누른 길(archive_app `_setScopeState` → viewForScopeState): 선반 기억이 빠지고 그릇 변형으로 · 줄 · 발 19가 없어진다.
    final (uid, to) = scopes.hitFolder(got[0].at.dx, mid)!;
    expect(layout.setViewState(layout.viewForScopeState(uid, ScopeState.values[to - 1])), isTrue);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    expect([layout.scopeStateOf('s2'), layout.viewState.shelvedScopes, layout.variantKeys], [ScopeState.open, <String>{}, ['scope:s2']]);
    expect(noted(painter, '선반줄'), isEmpty);
    expect(tags(painter), isEmpty);
  });

  test('누름 번호 → 앱 틀이 할 일(ScopeLayer.actionOf — 과제 7 검토 고침): 5는 상태 범위보다 먼저 가지 접기 · 1 ~ 4는 그 상태 · 그 밖은 켜고 끄기', () {
    expect(ScopeLayer.pressFold, greaterThan(ScopeState.values.length), reason: '5가 상태 번호(1 ~ 4)와 겹치지 않는다');
    expect(ScopeLayer.actionOf(ScopeLayer.pressFold), (ScopePress.fold, null));
    for (final s in ScopeState.values) {
      expect(ScopeLayer.actionOf(s.index + 1), (ScopePress.state, s), reason: '${s.name} = 차례 + 1');
    }
    expect(ScopeLayer.actionOf(4), (ScopePress.state, ScopeState.shelf), reason: '4 = 선반(차림표 · 오른쪽 클릭 — 선반 기억에 넣음)');
    for (final other in [0, -1, ScopeLayer.pressFold + 1]) {
      expect(ScopeLayer.actionOf(other), (ScopePress.toggle, null), reason: '$other: 본국 띠의 모아 보기 단추(0) · 모르는 번호는 켜고 끄기');
    }
  });

  test('라벨 누름 5(과제 7 걸음 5 — 메이커 서고 미리보기의 라벨 누름과 같음): 선반 → 접힘(선반 기억은 남고 선반 변형은 꺼짐) → 접힌 폴더의 라벨 · 왼쪽 칸 폴더도 5 → 다시 누르면 선반', () async {
    // 선반: 탭 라벨 · 왼쪽 칸 폴더가 5.
    final (scene, painter, layout) = await shelved();
    final tab = nums(noted(painter, '폴더탭').single.split('라벨').last);
    final (uid, press) = painter.scopes.hitFolder(tab[0] + 3, tab[1] + 3)!;
    expect((uid, press), ('s2', ScopeLayer.pressFold));
    final gut = painter.debugLabels.firstWhere((l) => l.kind == 'gutFolder');
    final g = painter.gutter.hitTest(gut.at.dx + 2, gut.at.dy + 6);
    expect([g?.kind, g?.uid, g?.row], [GutterHitKind.folder, 's2', ScopeLayer.pressFold]);
    // 누른 길(archive_app `_pressScope` → [ScopeLayer.actionOf] 5 → `_toggleScopeFold` → viewForScopeFold): 가지만 접힌다 — 접힘이 선반 기억을 이겨
    // 그릇 변형으로 접고, 선반 기억은 남는다. 왼쪽 칸 폴더의 누름도 같은 길이다.
    expect(pressed(layout, g!.uid, g.row), layout.viewForScopeFold('s2'));
    final folded = pressed(layout, uid, press)!;
    expect(layout.setViewState(folded), isTrue);
    scene.controller.setContentHeight(layout.totalHeight);
    await settle(scene, painter);
    expect([layout.scopeStateOf('s2'), layout.viewState.shelvedScopes, layout.variantKeys, layout.isShelfOn('s2')], [ScopeState.closed, {'s2'}, ['scope:s2'], false]);
    expect(noted(painter, '선반줄'), isEmpty);

    // 접힌 폴더(그릇 변형의 가지 줄 2 ~ 4가 줄 2 하나로): 라벨 · 왼쪽 칸 폴더가 5(선반 기억에 듦 — 아니면 1 펼침).
    final t = TileBuilder(level: 9, x: 1, chunk: 0)
      ..item(ScopeLayer.secScope, 1, 2, px(100), px(1500), row2: 4, name: '남곡 할거', color: 0xd4a39b, b: 7, text2: 's2\u001f시대');
    final again = shelfLayout();
    final (closedScene, closedPainter) = make(again, t.build());
    addTearDown(closedScene.dispose);
    expect(again.setViewState(folded), isTrue);
    closedScene.controller.setContentHeight(again.totalHeight);
    await settle(closedScene, closedPainter);
    expect(again.scopeStateOf('s2'), ScopeState.closed);
    final closedTab = nums(noted(closedPainter, '폴더탭').single.split('라벨').last);
    final closedHit = closedPainter.scopes.hitFolder(closedTab[0] + 3, closedTab[1] + 3)!;
    expect(closedHit, ('s2', ScopeLayer.pressFold));
    final closedGut = closedPainter.debugLabels.firstWhere((l) => l.kind == 'gutFolder');
    expect(closedPainter.gutter.hitTest(closedGut.at.dx + 2, closedGut.at.dy + 6)?.row, ScopeLayer.pressFold);
    // 다시 누르면 가지를 펴 선반으로(선반 기억이 남아 있어 엔진의 선반 변형을 다시 켠다).
    expect(again.setViewState(pressed(again, closedHit.$1, closedHit.$2)!), isTrue);
    expect([again.scopeStateOf('s2'), again.viewState.shelvedScopes, again.variantKeys], [ScopeState.shelf, {'s2'}, ['shelf:s2']]);
    // 선반 기억을 빼면(차림표 '접음') 같은 접힌 폴더의 라벨은 예전처럼 1(펼침).
    expect(again.setViewState(again.viewForScopeState('s2', ScopeState.closed)), isTrue);
    closedScene.controller.setContentHeight(again.totalHeight);
    await settle(closedScene, closedPainter);
    expect([again.scopeStateOf('s2'), again.viewState.shelvedScopes], [ScopeState.closed, <String>{}]);
    final plain = nums(noted(closedPainter, '폴더탭').single.split('라벨').last);
    expect(closedPainter.scopes.hitFolder(plain[0] + 3, plain[1] + 3), ('s2', 1));
    expect(pressed(again, 's2', 1), again.viewForScopeState('s2', ScopeState.open), reason: '1은 상태 바꾸기(펼침 — 선반 기억을 맞춤)');
    // 풀린 그릇을 5로 누르면(열쇠표 — 선반 기억에 든 그릇) 켜서 펴고, 선반 기억이 있으면 선반으로(미리보기의 열쇠표 toggleScope와 같음).
    final loose = again.viewForScopeState('s2', ScopeState.loose).withScopeShelved('s2', true);
    final reopened = again.viewForScopeFold('s2', loose);
    expect([reopened.openScopes, reopened.shelvedScopes], [{'s2'}, {'s2'}]);
  });

  test('화면에 잘린 그릇: 잘린 쪽의 금은 그림판 끝까지 · 꼬리표는 그림판 왼쪽 + 6부터(화면 밖에서 시작한 띠도) · 보는 때 밖의 띠는 +n', () async {
    // 그릇 x −200 ~ 1800(양쪽 잘림) · 검은물 의병은 화면 밖 −150에서 시작해 200에 끝남 · 남강 임시정부는 오른쪽 끝(− 6) 밖에서 시작.
    final (scene, painter, _) = await shelved(tile: shelfTile(x0: -200, x1: 1800, tags: [('h/a', '검은물 의병', -150, 200), ('h/b', '남강 임시정부', 1700, 1900)]));
    final p = await render(painter);
    expect(noted(painter, '폴더').single, allOf(contains('왼쪽잘림'), contains('오른쪽잘림')));
    final gutter = scene.layout.gutterWidth;
    final (xa, y, xb, _) = shelfRowOf(painter);
    expect([xa, xb], [gutter - 1, 1920 + 1], reason: '잘린 쪽은 그림판 끝(폴더 몸통 끝 = 그림판 끝 ± 1)까지');
    final f = boxOf(painter, '폴더', '남곡 할거');
    final inner = f[1] + f[3] - 1 - FolderLook.inset;
    for (final x in [gutter + 1, 1919.0]) {
      expect(at(p, x, y), at(p, x, inner), reason: '$x: 금(안쪽 겹선과 같은 먹)');
      expect(at(p, x, y), isNot(at(p, x, y + 1)), reason: '$x: 금 아래는 칠');
    }
    final got = tags(painter);
    expect([for (final l in got) l.text], ['검은물 의병', '+3']);
    expect(got.first.at.dx - 9, (gutter + FolderLook.shelfInset).roundToDouble(), reason: '그림판 왼쪽 + 6');
  });

  test('보는 때 안에 숨은 띠가 없어도(구역 59 없음) 금과 +n(숨은 수 전체)은 선다 — 빈 19 자리로 남지 않게', () async {
    final (_, painter, _) = await shelved(tile: shelfTile(tags: const []));
    final f = boxOf(painter, '폴더', '남곡 할거');
    final (xa, y, _, hidden) = shelfRowOf(painter);
    expect([xa, y, hidden], [f[0] + 6, f[1] + f[3] - 20, 4]);
    final got = tags(painter);
    expect([for (final l in got) l.text], ['+4']);
    expect(got.single.at.dx - 5, xa.roundToDouble(), reason: '칩은 꼬리표 자리의 처음(왼쪽 + 6)');
  });

  test('선반 변형이 없는 그릇(✓만 선반)은 줄 · 발 19 · 라벨 수 더함이 없고 그림이 펼침과 픽셀까지 같다', () async {
    final t = scopeTile([('s2', '남곡 할거', 2, 4, 100, 1500, 3)], [2, 3, 4], (r) => 140.0 + 60 * r);
    final (_, open, _) = await shelved(layout: shelfLayout(shelf: false), tile: t, state: ScopeState.open);
    final before = await render(open);
    final (_, painter, layout) = await shelved(layout: shelfLayout(shelf: false), tile: t);
    expect([layout.isShelfOn('s2'), layout.variantKeys], [false, ['scope:s2']]);
    expect(noted(painter, '선반줄'), isEmpty);
    expect(tags(painter), isEmpty);
    expect([for (final l in painter.debugLabels) if (l.kind == 'folder') l.text], ['남곡 할거', '3']);
    final after = await render(painter);
    expect(after.lengthInBytes, before.lengthInBytes);
    expect(after.buffer.asUint8List(), before.buffer.asUint8List(), reason: '✓만 선반 — 그림은 펼침 그대로');
  });

  test('선반이 아닌 그릇(펼침 · 접음) · 숨은 구성원이 없는 선반 변형 · 조감에는 줄이 없다', () async {
    // 펼침 · 접음: 그릇 변형(선반 변형은 꺼짐).
    for (final state in [ScopeState.open, ScopeState.closed]) {
      final (_, painter, layout) = await shelved(state: state);
      expect(layout.isShelfOn('s2'), isFalse, reason: state.name);
      expect(noted(painter, '선반줄'), isEmpty, reason: state.name);
      expect(tags(painter), isEmpty, reason: state.name);
    }
    // 숨은 구성원이 없는 선반 변형(답의 shelf가 빈 목록): 발 19도 줄도 없다 · 라벨 수는 b 그대로.
    final (scene, painter, layout) = await shelved(layout: shelfLayout(hidden: const []), tile: shelfTile(tags: const []));
    expect([layout.isShelfOn('s2'), layout.scopeOnOf('s2')!.shelf], [true, isEmpty]);
    final f = boxOf(painter, '폴더', '남곡 할거');
    expect(f[1] + f[3], scene.controller.view.yOf(layout.rowTop(9) + layout.geo(9).height + G.folderFoot).roundToDouble(), reason: '발 7뿐');
    expect(noted(painter, '선반줄'), isEmpty);
    expect([for (final l in painter.debugLabels) if (l.kind == 'folder') l.text], ['남곡 할거', '3']);
    // 조감: 옛 테두리라 줄이 없다(선반 변형은 그대로 켜 있다).
    final (bird, birdPainter, birdLayout) = await shelved();
    birdLayout.setConditions(birdLayout.conditions.copyWith(density: 2));
    bird.controller.setContentHeight(birdLayout.totalHeight);
    await settle(bird, birdPainter);
    expect(birdLayout.variantKeys, ['shelf:s2']);
    expect(noted(birdPainter, '폴더'), isEmpty);
    expect(noted(birdPainter, '선반줄'), isEmpty);
    expect(tags(birdPainter), isEmpty);
  });

  // 과제 8 걸음 4 검토 ②(성격이 동군연합인 그릇 폴더는 먹 — host_folder_paint_test는 펼침만) × 과제 7(선반) — 두 갈래가 한 그릇에 함께 걸리는 꼴
  // (remake-4-int 검토 고침 — 합친 판에서 처음 만나는 조합): 먹은 몸통 칠 · 테만 바꾸고 선반 줄 · 라벨 수 · 자리는 시대 그릇과 같다.
  test('성격이 동군연합인 그릇을 선반에 두어도 폴더는 먹(칠 먹 3.5 · 테 25) — 선반 줄(금 · 꼬리표 · +n) · 라벨 수(남은 3 + 숨은 4) · 자리는 시대 그릇과 같고 · 스위치 lid를 끄면 그릇 색', () async {
    /// 그린 그림(RGBA)의 한 점을 ARGB로.
    int argb(ByteData p, num x, num y) {
      final v = at(p, x, y);
      return (v & 0xff) << 24 | v >>> 8;
    }

    /// 두 빛깔이 채널마다 1 안인가(먹 알파 칠은 그림판 바탕 위에 섞여 반올림이 갈린다).
    bool near(int a, int b) => [16, 8, 0].every((s) => (((a >> s) & 0xff) - ((b >> s) & 0xff)).abs() <= 1);

    /// 폴더 왼쪽 테 · 안쪽 겹선 안쪽에서 첫 띠 앞까지(몸통 위 + 4 ~ 선반 금 위 − 2) — 가장 흔한 빛깔.
    int fillAt(ByteData p, List<double> f) {
      final count = <int, int>{};
      for (int y = (f[1] + G.folderTab + 4).toInt(); y < (f[1] + f[3] - FolderLook.shelfRise - 2).toInt(); y++) {
        for (int x = f[0].toInt() + 6; x < f[0].toInt() + 24; x++) {
          final c = argb(p, x, y);
          count[c] = (count[c] ?? 0) + 1;
        }
      }
      return (count.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    }

    final (_, era, _) = await shelved();
    final (_, union, layout) = await shelved(tile: shelfTile(label: '동군연합'));
    expect([layout.isShelfOn('s2'), layout.variantKeys], [true, ['shelf:s2']]);
    final f = boxOf(union, '폴더', '남곡 할거');
    expect(f, boxOf(era, '폴더', '남곡 할거'), reason: '폴더 자리 · 발 19는 그대로');
    expect(noted(union, '선반줄'), noted(era, '선반줄'), reason: '선반 줄 자리 · 숨은 수 · 꼬리표는 그대로');
    expect([for (final l in tags(union)) l.text], ['검은물 의병', '잿빛 결사', '+2']);
    expect([for (final l in union.debugLabels) if (l.kind == 'folder') l.text], ['남곡 할거', '7'], reason: '라벨 수 = 남은 3 + 숨은 4');

    final p = await render(union);
    final left = f[0], right = f[0] + f[2], body = f[1] + G.folderTab, bottom = f[1] + f[3];
    final (_, y, _, _) = shelfRowOf(union);
    // 먹: 몸통 왼쪽 테 = 먹 20 → 그림판 먹 단계 25(불투명 회색) · 칠 = 먹 3.5 알파.
    for (final ty in [body + 12, ((body + y) / 2).roundToDouble()]) {
      expect(argb(p, left, ty), CanvasInk.gray(LidLook.folderEdge), reason: '몸통 왼쪽 테 y $ty');
    }
    final fill = fillAt(p, f);
    expect(near(fill, over(CanvasInk.alpha(LidLook.folderFill), Look.ground)), isTrue, reason: '몸통 칠 ${fill.toRadixString(16)}');
    // 선반 금은 먹 몸통 위에서도 안쪽 겹선과 같은 먹 12 · 그 위아래는 몸통 칠.
    final inner = bottom - 1 - FolderLook.inset;
    expect(share(left + 12, right - 12, (x) => at(p, x, y) == at(p, x, inner)), greaterThan(.9), reason: '금 = 먹 12');
    expect(share(left + 12, right - 12, (x) => at(p, x, y - 1) == at(p, x, y + 1) && at(p, x, y) != at(p, x, y + 1)), greaterThan(.9), reason: '금 위아래는 몸통 칠');

    // 시대 그릇(같은 선반)은 그릇 색 — 9% 칠 · 55% 테.
    final eraEdge = mixOklab(0xffd4a39b, Look.paper, FolderLook.edgePct);
    final eraFill = over(withAlpha(0xffd4a39b, FolderLook.fillPct), Look.ground);
    final e = await render(era);
    expect(argb(e, left, body + 12), eraEdge);
    expect(near(fillAt(e, f), eraFill), isTrue);
    // 스위치 lid를 끄면(그릴 때 읽음) 동군연합 그릇도 그릇 색 — 선반 줄은 그대로.
    PaintPick.lid = false;
    final off = await render(union);
    expect(argb(off, left, body + 12), eraEdge);
    expect(near(fillAt(off, f), eraFill), isTrue, reason: '몸통 칠 ${fillAt(off, f).toRadixString(16)}');
    expect(noted(union, '선반줄'), noted(era, '선반줄'));
  });
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/links.dart';
import 'package:archive_prototype/scene/paint/scopes.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:archive_prototype/scene/text_paragraph.dart';
import 'package:flutter_test/flutter_test.dart';

import 'load_app_fonts.dart';
import 'support/scene_text.dart';

// 0.1.0 1배 지적 둘의 안전망(감독 1배 장면 2026-10-25 밤 — 마지막 고침 가지 fix-010-last): 진짜 처리부(DLL)와 찍기 저장소(prototype/results/remake4-shots/stores —
// git 밖 · `node prototype/scripts/remake4-shots.mjs --stores`로 짓는다)로 그 장면을 그려 본다. 저장소나 DLL이 없으면 건너뛴다.
//  ① 글자 겹침: 등불 넓게 · 판 3 등불 — 갈대 공국 띠 위에서 열쇠표 '아홉 불씨 할거'가 상국 탭 '아랫물국'의 '아'를 덮었다(4단계 상국 탭). 그린 글줄 상자
//     (TextProbe — 찍기의 --capture-text · scripts/text-overlap.mjs와 같은 잉크 상자)끼리 겹침 0이고, 열쇠표는 같은 띠의 상국 탭과 4 넘게 떨어진다.
//     1380 ~ 1660(시트 장면 group-tree의 범위)의 빛나루 자유시 위 '아홉 불씨 할거' ↔ 대립 파선 탭 '산호 해상 동맹'도 같은 겹침이다 — 두 글의 잉크 상자는
//     1px 넘게 겹치지 않아, 열쇠표 틀이 '산'을 덮는 것은 탭과의 거리 검사가 잡는다(고침 전 열쇠표 코드로 돌리면 이 장면에서 실패함을 확인).
//  ② 띠 밖 돌출: 짝 꼬리표 장면(150년 보기)의 1459년 자리 — 진행 중 조약 둘의 막대가 다음 타일로 이어진 조각(왼쪽 잘림)이 점이 되어, 끝난 띠 뒤 바탕에
//     마름모 셋과 '2' 알약이 떴다. 그 장면의 점 · 개수 알약은 모두 그린 띠 안이다.

/// 켠 변형을 함께 실어야 하는 조회 명령(line_audit_real_test와 같다).
const _variantOps = {'rows_near', 'row_labels', 'list', 'events_in', 'echo'};

/// 지금 연표의 해 좌표 → 1970년 기준 분(찍기 대본의 minute와 같은 투영).
double _minute(double y) {
  final year = y.floor();
  final a = DateTime.utc(year < 0 ? year + 1 : year), b = DateTime.utc(year == -1 ? 1 : (year < 0 ? year + 2 : year + 1));
  return ((a.millisecondsSinceEpoch + (b.millisecondsSinceEpoch - a.millisecondsSinceEpoch) * (y - year)) / 60000).roundToDouble();
}

/// 글줄 상자(높이 = 글 크기 × 1.2)에서 위아래로 글 크기의 0.12씩 덜어 낸 잉크 상자 · 자르기와 겹친 몫 — scripts/text-overlap.mjs와 같은 셈.
List<(String, ui.Rect)> _inkBoxes(List<List<Object>> frame) {
  final out = <(String, ui.Rect)>[];
  for (final b in frame) {
    final s = '${b[0]}', size = (b[9] as num).toDouble(), alpha = (b[10] as num).toDouble();
    if (alpha < .15 || s.trim().isEmpty) continue;
    final pad = size * .12;
    double f(int i) => (b[i] as num).toDouble();
    final l = f(1) > f(5) ? f(1) : f(5), r = f(3) < f(7) ? f(3) : f(7);
    final t = f(2) + pad > f(6) ? f(2) + pad : f(6), bt = f(4) - pad < f(8) ? f(4) - pad : f(8);
    if (r - l < 1 || bt - t < 1) continue;
    out.add((s, ui.Rect.fromLTRB(l, t, r, bt)));
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dll = File('../engine/target/release/archive_engine.dll');
  File db(String store) => File('../results/remake4-shots/stores/$store/archive.db');
  final ready = dll.existsSync() && ['lantern', 'v3-lantern'].every((s) => db(s).existsSync());

  /// 저장소 [store]의 장면(문화권 모두 폄 — 찍기의 기억 사본과 같다)을 가라앉을 때까지 그린 뒤 [look]을 부른다.
  Future<void> scene(String store, double from, double to, double scroll, Future<void> Function(TimelineScene, TimelinePainter, TimelineController) look) async {
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    try {
      final info = await engine.start(db(store).absolute.path);
      final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
      final shape = await engine.call({'op': 'layout'});
      final layout = SceneLayout.fromJson(Map<String, dynamic>.from(shape['data'] as Map));
      layout
        ..setViewState(layout.viewState.copyWith(foldedSpheres: <String>{}))
        ..finishFlow();
      final controller = TimelineController()
        ..reduceMotion = true
        ..resize(1920, 1020)
        ..setExtent(double.parse(meta['min'] as String), double.parse(meta['max'] as String))
        ..setContentHeight(layout.totalHeight);
      final scene = TimelineScene(
        controller: controller, layout: layout,
        fetchTile: (level, x, chunk, packs) => engine.tile(level, x, chunk, packs, variants: layout.variantKeys),
        ask: (query) async {
          final keys = layout.variantKeys;
          final asked = keys.isNotEmpty && _variantOps.contains(query['op']) && query['variants'] == null ? {...query, 'variants': keys} : query;
          return Map<String, dynamic>.from((await engine.call(asked))['data'] as Map);
        },
      );
      final marks = SceneMarks.of(scene)
        ..expanded = {...layout.viewState.expandedHosts}
        ..scopesOn = {...layout.viewState.openScopes};
      marks.version++;
      scene.applyLayoutToView();
      controller.showRange(_minute(from), _minute(to));
      controller.scrollTo(scroll);
      final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
      var calm = 0;
      for (int i = 0; i < 300 && calm < 3; i++) {
        painter.debugSink.notes.clear();
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), const ui.Size(1920, 1020));
        recorder.endRecording().dispose();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        scene.tick(10);
        final s = scene.stats;
        calm = s.blanks == 0 && s.covers == 0 && !scene.fading && scene.settled ? calm + 1 : 0;
      }
      expect(calm, 3, reason: '$store $from ~ $to: 장면이 가라앉지 않았습니다');
      await look(scene, painter, controller);
      scene.dispose();
    } finally {
      engine.close();
    }
  }

  tearDown(() => SceneText.probe = null);

  // 장면: 저장소 · 보는 해 범위. 셋 모두 열쇠표 '아홉 불씨 할거'가 탭에 막혀 구멍만 남는다. 1380 ~ 1660은 시트 장면 group-tree(단체 계보 창 — 아래 서랍이라 연표 폭은 그대로)의
  // 범위로, 빛나루 자유시 띠 위 열쇠표 '아홉 불씨 할거'가 대립 파선 상국 탭 '산호 해상 동맹'의 '산'을 덮던 다섯째 자리다(고침 검토 지적 — 1배 목록의 넷 밖).
  const scenes = [
    ('lantern', -700.0, 1750.0),
    ('v3-lantern', -700.0, 1750.0),
    ('lantern', 1380.0, 1660.0),
  ];

  test('① 등불 넓게 · 판 3 등불 · 1380 ~ 1660: 그린 글줄 상자 겹침 0 · 열쇠표는 상국 탭을 비킨다', () async {
    await loadAppFonts();
    for (final (store, from, to) in scenes) {
      await scene(store, from, to, 0, (scene, painter, _) async {
        final probe = SceneText.probe = TextProbe();
        painter.debugSink.notes.clear();
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), const ui.Size(1920, 1020));
        recorder.endRecording().dispose();
        final boxes = _inkBoxes(probe.frames[painter.text] ?? const []);
        expect(boxes.length, greaterThan(100), reason: '$store $from ~ $to: 글이 실렸는가');
        final pairs = <String>[];
        for (int a = 0; a < boxes.length; a++) {
          for (int b = a + 1; b < boxes.length; b++) {
            final x = boxes[a].$2.intersect(boxes[b].$2);
            if (x.width > 1 && x.height > 1) pairs.add('"${boxes[a].$1}" ${boxes[a].$2} ↔ "${boxes[b].$1}" ${boxes[b].$2}');
          }
        }
        expect(pairs, isEmpty, reason: '$store $from ~ $to: 글줄 상자 겹침');
        // 상국 탭(띠 윗변 위 4 ~ 17)과 열쇠표(띠 윗변 위 2 ~ 14)는 같은 띠면 세로로 늘 겹친다 — 그런 짝은 가로로 4 넘게 떨어진다(구멍만 남긴 작은 꼴이라도).
        // 탭의 가로 자리는 검사 기록 '상국탭'(10배 정수 · 왼쪽 · 폭), 세로는 그 탭 글(글 왼쪽 = 탭 왼쪽 + 7)의 윗변.
        final tabs = <(double, double, double)>[];
        for (final n in painter.debugSink.notes['상국탭'] ?? const <Object>[]) {
          final v = [for (final s in '$n'.split(' ').last.split(',')) double.parse(s) / 10];
          final text = painter.debugLabels.where((l) => l.kind == 'hostTab' && (l.at.dx - (v[0] + 7)).abs() < .6);
          if (text.isNotEmpty) tabs.add((v[0], v[0] + v[1], text.first.at.dy));
        }
        expect(tabs, isNotEmpty, reason: '$store $from ~ $to: 상국 탭이 섰다');
        for (final key in [for (final n in painter.debugSink.notes['열쇠표'] ?? const <Object>[]) '$n']) {
          final k = [for (final s in key.split(' ').last.split(',')) double.parse(s)];
          for (final (tl, tr, ty) in tabs) {
            final across = k[0] + k[2] + FolderLook.keyGap > tl && k[0] < tr + FolderLook.keyGap;
            expect(across && (k[1] - ty).abs() < 12, isFalse, reason: '$store $from ~ $to: 열쇠표 $key 가 상국 탭 $tl ~ $tr(글 위 $ty)에 닿는다');
          }
        }
        expect([for (final n in painter.debugSink.notes['열쇠표비킴'] ?? const <Object>[]) '$n'], contains(startsWith('아홉 불씨 할거 구멍만')),
            reason: '$store $from ~ $to: 탭과 다투던 열쇠표는 구멍만');
      });
    }
  }, timeout: const Timeout(Duration(minutes: 6)), skip: ready ? false : '찍기 저장소(results/remake4-shots/stores)와 DLL을 먼저 짓는다');

  test('② 짝 꼬리표 장면(150년 보기): 점 · 개수 알약은 모두 그린 띠 안 — 타일 경계(1459년 자리)에 떠 있던 진행 중 조약의 조각이 없다', () async {
    for (final scroll in [1900.0, 0.0]) {
      await scene('lantern', 1330, 1480, scroll, (scene, painter, controller) async {
        final v = controller.view, out = scene.labelOutput!, input = scene.labelBatch!.input;
        final bands = [for (final b in painter.debugBands) b.rect];
        bool inside(double x, double y) => bands.any((r) => x >= r.left - 1 && x <= r.right + 1 && y >= r.top && y <= r.bottom);
        expect(painter.debugDots, isNotEmpty, reason: '굴림 $scroll: 점이 실렸는가');
        // 화면 안(그림판 왼쪽 ~ 오른쪽)의 것만 본다 — 앞뒤 반 화면의 후보는 그리지 않는 자리다.
        bool shown(double x) => x >= v.left && x <= 1920;
        for (final d in painter.debugDots.where((d) => shown(d.at.dx))) {
          expect(inside(d.at.dx, d.at.dy), isTrue, reason: '굴림 $scroll: 사건 ${d.eventId}의 점 ${d.at}이 띠 밖 바탕에 떴다');
        }
        for (int i = 0; i < out.clusters; i++) {
          final x = v.xOf(out.clusterAt[i]);
          if (!shown(x)) continue;
          expect(bands.any((r) => x >= r.left - 1 && x <= r.right + 1), isTrue, reason: '굴림 $scroll: 개수 알약 ${out.clusterCount[i]}@$x이 띠 밖');
        }
        // 후보는 (줄, 사건)마다 하나 — 다음 타일로 이어진 막대 조각이 같은 사건을 한 번 더 세우지 않는다.
        final seen = <(int, int)>{};
        for (int i = 0; i < input.at.length; i++) {
          expect(seen.add((input.row[i], input.eventId[i])), isTrue, reason: '굴림 $scroll: 사건 ${input.eventId[i]}(줄 ${input.row[i]})이 두 번 후보가 되었다');
        }
      });
    }
  }, timeout: const Timeout(Duration(minutes: 4)), skip: ready ? false : '찍기 저장소(results/remake4-shots/stores)와 DLL을 먼저 짓는다');

  // ③ 0.1.1 1배 '새로 생긴 것' 1: 판 3.1 동아시아(-300 ~ 1950)의 동예 · 옥저 · 부여 '○ 원삼국 시대' · 위만조선 '○ 고조선' · 마한 둘째 · 신라 '○ 남북국 시대'는
  // 고조선 · 부여 승계선 가닥(5px 사이 셋 · 넷)이 띠 시작 언저리를 함께 지나 제자리 + 16 · 제자리 구멍만이 모두 막혀 통째로 빠졌다(③ 고침 9f8fbe6 뒤).
  // 이제 띠에 매인 고정 자리에 구멍만 꼴로 서고, 그 자리는 획 · 열쇠표 실 밑을 지나지 않는다.
  test('③ 판 3.1 동아시아: 탭 · 획에 막힌 그릇 열쇠표가 빠지지 않는다 — 비킨 고정 자리 · 획과 4 넘게 떨어짐', () async {
    await loadAppFonts();
    await scene('v3-east-asia', -300, 1950, 0, (scene, painter, _) async {
      final notes = [for (final n in painter.debugSink.notes['열쇠표비킴'] ?? const <Object>[]) '$n'];
      // 막혀서 빠지는 것은 좁고 붐비는 띠뿐(위만조선 '고조선' — 띠 64 안에 플래그 · 획 둘: 구멍만 꼴 10도 4 틈을 둘 자리가 없다).
      for (final n in notes.where((n) => n.contains(' 자리 없음') && !n.contains('좁은 띠'))) {
        expect(double.parse(n.split(' ').last), lessThan(80), reason: '넓은 띠에서 막혀 빠진 열쇠표: $n · $notes');
      }
      final keys = [for (final n in painter.debugSink.notes['열쇠표'] ?? const <Object>[]) '$n'];
      expect(keys.length, greaterThanOrEqualTo(13), reason: '0.1.1 a74564c는 8 — $keys');
      for (final k in keys) {
        final v = k.substring(k.lastIndexOf(' ') + 1).split(',').map(double.parse).toList();
        final (kx, ky, w) = (v[0], v[1], v[2]);
        final mini = w == FolderLook.keyMini;
        final bandTop = ky + (mini ? FolderLook.keyMini : FolderLook.keyH) + FolderLook.keyRise, thread = kx - (mini ? 2 : 3);
        for (final col in LinkColumns.of(scene)) {
          if (col.top >= bandTop || col.bottom <= ky) continue;
          expect(col.x + 1 + FolderLook.keyGap <= thread || col.x - 1 >= kx + w + FolderLook.keyGap, isTrue, reason: '열쇠표 $k 밑(실 포함)을 획 ${col.x}가 지난다');
        }
      }
    });
  }, timeout: const Timeout(Duration(minutes: 4)), skip: ready && db('v3-east-asia').existsSync() ? false : '찍기 저장소(results/remake4-shots/stores)와 DLL을 먼저 짓는다');
}

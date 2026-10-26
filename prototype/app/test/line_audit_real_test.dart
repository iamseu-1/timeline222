import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive_prototype/controller.dart';
import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/marks.dart';
import 'package:archive_prototype/scene/paint/links.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:archive_prototype/scene/painter.dart';
import 'package:archive_prototype/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scene_text.dart';

// 끊김 0 안전망의 단언(이어 주는 선 걸음 5 — 명세 04 8-6 '0.1.0 전 목표' · 판 3 장면은 2026-10-25 저녁): 진짜 처리부(DLL)와 찍기 저장소(prototype/results/remake4-shots/stores —
// git 밖 · `node prototype/scripts/remake4-shots.mjs --stores`로 짓는다)로 등불 · 동아시아 · f4 장면을 그려, 선 감사(LinkLayer · LineAudit)가
// '문 표시 없이 숨은 px 0 · 빠진 선 0'인지 본다. 장면의 범위 · 굴림은 실제 앱 찍기의 장면 표(prototype/results/lines/scenes.json)와 같다 —
// 문화권은 모두 펴고(찍기의 기억 사본과 같게) 연방은 펼친 장면이 하나다.
// 스위치 route를 끄면(그 전 길) 숨은 px이 남아야 한다 — 이 단언이 실제로 무엇을 잡는지 함께 본다.
// 저장소나 DLL이 없으면 건너뛴다.

/// (장면, 저장소, 시작 해, 끝 해, 굴림 px, 펼칠 상국 uid).
const _scenes = <(String, String, double, double, double, String?)>[
  ('lantern-wide', 'lantern', -700, 1750, 0, null),
  ('lantern-scope', 'lantern', 380, 820, 0, null),
  ('lantern-down', 'lantern', 900, 1200, 1500, null),
  ('lantern-ember-down', 'lantern', 1100, 1450, 300, null),
  ('east-asia', 'east-asia', -300, 1950, 0, null),
  ('east-asia-down', 'east-asia', 1300, 1950, 900, null),
  ('east-asia-korea', 'east-asia', 300, 1400, 0, null),
  ('f4-federation-open', 'f4-federation', 1140, 1660, 0, 'f4-federation/o-fed'),
  // 소속 폴더를 끈 연방 펼침(스위치 folder 끔 — 0.1.1 결함 18 · 45 '폴더 밖'): 폴더가 소속선을 걷지 않아 구성원 열둘의 소속선이 사이 구성원 띠 뒤로 지난다 —
  // 굴 문의 몫. 폴더를 켠 장면(위)은 4단계 마지막 합치기부터 폴더 안 소속선을 긋지 않아(HostFolders.holdsPart) 선이 없다.
  ('f4-federation-open-folder-off', 'f4-federation', 1140, 1660, 0, 'f4-federation/o-fed'),
  ('f4-federation', 'f4-federation', 1140, 1660, 0, null),
  ('f4-liege', 'f4-liege', 990, 1420, 0, null),
  ('f4-crowns', 'f4-crowns', 1280, 1660, 0, null),
  // 판 3 옛 저장소(배포본 0.0.4 — 2026-10-25 저녁 검증 지적: 걸음 6의 곧은 획이 판 3.1 동아시아에서 사이 띠 뒤로 새로 숨었다).
  ('v3-lantern', 'v3-lantern', -700, 1750, 0, null),
  ('v3-east-asia', 'v3-east-asia', -300, 1950, 0, null),
];

/// 켠 변형을 함께 실어야 하는 조회 명령.
const _variantOps = {'rows_near', 'row_labels', 'list', 'events_in', 'echo'};

/// 지금 연표의 해 좌표(정수 N = N년 1월 1일 · 기원전 1년 = −1) → 1970년 기준 분(내보내기 · 찍기 대본의 minute와 같은 투영).
double _minute(double y) {
  final year = y.floor();
  final a = DateTime.utc(year < 0 ? year + 1 : year), b = DateTime.utc(year == -1 ? 1 : (year < 0 ? year + 2 : year + 1));
  return ((a.millisecondsSinceEpoch + (b.millisecondsSinceEpoch - a.millisecondsSinceEpoch) * (y - year)) / 60000).roundToDouble();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dll = File('../engine/target/release/archive_engine.dll');
  File db(String store) => File('../results/remake4-shots/stores/$store/archive.db');
  final ready = dll.existsSync() && _scenes.every((s) => db(s.$2).existsSync());

  // 0.1.1 다-1(감독 고름 2026-10-26): 선 길 route는 기본 끔 — 이 파일은 새 길(켬)과 옛 길(끔)을 견주므로 켠 쪽을 먼저 잰다(다른 시험의 setUp과 같다).
  setUp(() => PaintPick.route = true);
  tearDown(() {
    PaintPick.reset();
    LineAudit.capture = false;
    LineAudit.last = null;
  });

  test('등불 · 동아시아 · f4 장면: 문 표시 없이 숨은 px 0 · 빠진 선 0(굴 문 · 이음매 눈금 · (가-0)) — route를 끄면 숨은 px이 남는다', () async {
    final results = <String, (LineAudit, LineAudit)>{};
    for (final store in {for (final s in _scenes) s.$2}) {
      final engine = ArchiveEngine(libraryPath: dll.absolute.path);
      try {
        final info = await engine.start(db(store).absolute.path);
        final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
        for (final (id, _, from, to, scroll, host) in _scenes.where((s) => s.$2 == store)) {
          PaintPick.folder = !id.endsWith('-folder-off'); // 줄 쌓기(소속 폴더 덩이)도 이 스위치를 보므로 배치를 짓기 전에
          final shape = await engine.call({'op': 'layout'});
          final layout = SceneLayout.fromJson(Map<String, dynamic>.from(shape['data'] as Map));
          var state = layout.viewState.copyWith(foldedSpheres: <String>{});
          if (host != null) {
            final band = (Map<String, dynamic>.from((await engine.call({'op': 'id_of', 'uid': host}))['data'] as Map))['band'];
            expect(band, isA<num>(), reason: '$id: 펼칠 상국 $host');
            state = state.withHostExpanded((band as num).toInt(), true);
          }
          layout
            ..setViewState(state)
            ..finishFlow();
          final controller = TimelineController()
            ..reduceMotion = true
            ..resize(1920, 1020)
            ..setExtent(double.parse(meta['min'] as String), double.parse(meta['max'] as String))
            ..setContentHeight(layout.totalHeight);
          final scene = TimelineScene(
            controller: controller, layout: layout,
            fetchTile: (level, x, chunk, packs) => engine.tile(level, x, chunk, packs, variants: layout.variantKeys),
            // 켠 변형은 줄을 아는 조회에도 함께 실어야 엔진이 줄 번호를 바꿔 싣는다(앱 틀의 _filtered · render_scene_test와 같다 — 없으면 펼친 구성국 줄이 비어 보인다).
            ask: (query) async {
              final keys = layout.variantKeys;
              final asked = keys.isNotEmpty && _variantOps.contains(query['op']) && query['variants'] == null ? {...query, 'variants': keys} : query;
              return Map<String, dynamic>.from((await engine.call(asked))['data'] as Map);
            },
          );
          // 단추의 ▸/▾ · 소속선을 그리는 층의 밭도 앱 틀처럼 함께(render_scene_test의 EXPAND와 같다).
          final marks = SceneMarks.of(scene)
            ..expanded = {...layout.viewState.expandedHosts}
            ..scopesOn = {...layout.viewState.openScopes};
          marks.version++;
          scene.applyLayoutToView();
          controller.showRange(_minute(from), _minute(to));
          controller.scrollTo(scroll);
          final painter = TimelinePainter(scene, text: unbudgetedText());
          LineAudit.capture = true;
          Future<LineAudit> audit() async {
            var calm = 0;
            for (int i = 0; i < 300 && calm < 3; i++) {
              final recorder = ui.PictureRecorder();
              painter.paint(ui.Canvas(recorder), const ui.Size(1920, 1020));
              recorder.endRecording().dispose();
              await Future<void>.delayed(const Duration(milliseconds: 10));
              scene.tick(10);
              final s = scene.stats;
              calm = s.blanks == 0 && s.covers == 0 && !scene.fading && scene.settled ? calm + 1 : 0;
            }
            expect(calm, 3, reason: '$id: 장면이 가라앉지 않았습니다');
            return LineAudit.last!;
          }

          final on = await audit();
          PaintPick.route = false;
          final off = await audit();
          PaintPick.route = true;
          results[id] = (on, off);
          scene.dispose();
        }
      } finally {
        engine.close();
      }
    }
    final report = [
      for (final e in results.entries)
        '${e.key}: 켬 ${e.value.$1.summary} | 끔 숨은 ${e.value.$2.hiddenPx.round()}px 안 보임 ${e.value.$2.invisible}',
    ].join('\n');
    for (final e in results.entries) {
      final on = e.value.$1;
      expect(on.hiddenPx, lessThan(.5), reason: '${e.key}: 문 표시 없이 숨은 px\n${on.detail.join('\n')}\n$report');
      expect(on.missing, 0, reason: '${e.key}: 빠진 선 ${on.missed}\n$report');
    }
    // 이 단언이 실제로 무엇을 잡는지: 그 전 길(route 끔)은 등불 · 동아시아 · 폴더를 끈 연방 펼침에서 숨은 px이 있다. 폴더를 켠 연방 펼침(f4-federation-open)은
    // 4단계 마지막 합치기에서 과제 8의 폴더(소속 펼치기를 폴더로 — 소속선 걷기)가 들어와 선이 0이라 뺐다(켬 · 끔 모두 선 0 — 위의 '숨은 0 · 빠짐 0'은 그대로 본다).
    for (final id in ['lantern-wide', 'east-asia', 'east-asia-down', 'east-asia-korea', 'f4-federation-open-folder-off']) {
      expect(results[id]!.$2.hiddenPx, greaterThan(20), reason: '$id: route를 끄면 숨은 px이 남아야 한다\n$report');
    }
    final fed = results['f4-federation-open-folder-off']!.$1;
    expect(fed.kinds[LineAuditKind.part]?.$1 ?? 0, greaterThan(5), reason: '폴더를 끈 연방 펼침: 구성원의 소속선이 실렸는가\n$report');
    expect(fed.markedPx, greaterThan(20), reason: '폴더를 끈 연방 펼침: 사이 구성원 띠의 굴 문 표시\n$report');
    expect(results.values.fold(0, (n, r) => n + r.$1.lines), greaterThan(100), reason: '선이 실렸는가\n$report');
    // 사이 줄 비킴(명세 04 3-6 (나) 끝): 걸음 6이 판 3.1 동아시아에서 꼬리 내림 · 합류 내림줄을 사이 띠 뒤로 보내 굴 문 표시가 2,114px로 늘었다(걸음 5 1,990).
    // 사이 줄이 막는 세로 획을 고르지 않으면 2,008px — 다시 늘면 사이 띠 뒤로 숨는 길이 돌아온 것이다.
    final v3 = results['v3-east-asia']!.$1;
    expect(v3.markedPx, lessThan(2060), reason: 'v3-east-asia: 굴 문 표시 px\n$report');
    // 후대 줄의 틈으로 들기(0.1.1 · 조사 결함 4 · 8 · 42): 고조선 → 조선이 후고구려 · 고려 뒤 가로(굴 문 표시) 대신 고려 줄 위 틈으로 가고,
    // 응우옌 → 남베트남이 프랑스 식민 지배 안에서 끝나지 않는다. 고치기 전 동아시아 583 · 한반도 936 · 내려 봄 27px — 다시 늘면 띠 뒤 가로가 돌아온 것이다.
    expect(results['east-asia']!.$1.markedPx, lessThan(300), reason: 'east-asia: 굴 문 표시 px\n$report');
    expect(results['east-asia-korea']!.$1.markedPx, lessThan(300), reason: 'east-asia-korea: 굴 문 표시 px\n$report');
    expect(results['east-asia-down']!.$1.markedPx, lessThan(10), reason: 'east-asia-down: 굴 문 표시 px\n$report');
    // ignore: avoid_print
    print(report);
  }, timeout: const Timeout(Duration(minutes: 8)), skip: ready ? false : '찍기 저장소(results/remake4-shots/stores)와 DLL을 먼저 짓는다');

  // 그릇을 펼친 장면(4단계 마지막 합치기 검토 지적 — 찍기 장면 shelf-chain-open): 변형은 선 항목의 두 끝 줄을 옮긴 뒤 row ≤ row2로 다시 고르면서
  // down 비트(기본 줄 차례)는 그대로 두어, 갈대 공국 → 아랫물국의 선대 · 후대 줄이 뒤바뀌었다. 그래서 띠 위 판 조각(관문)이 꼬리 마름모에서 다른 줄의
  // 띠 아랫변까지 450px 길게 그어져 빛나루 자유시 · 등불 왕국의 몸통과 글자 위로 지났다(감사는 그것을 표시로 세어 못 잡았다). route는 네모의 줄로 바로잡는다.
  // 0.1.1: 바로잡음은 선 길이 아니라 mend 뒤다 — 기본 꼴(route 끔)에서도 지키는지 두 꼴을 다 본다.
  for (final route in const [true, false]) {
  test('그릇을 펼친 장면(shelf-chain-open · route ${route ? '켬' : '끔'}): 띠 위 조각이 줄을 건너 길게 서지 않는다 — 선대 · 후대 줄은 네모의 줄', () async {
    PaintPick.route = route;
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    try {
      final info = await engine.start(db('shelf-chain').absolute.path);
      final meta = Map<String, dynamic>.from(info['data']['meta'] as Map);
      final shape = await engine.call({'op': 'layout'});
      final layout = SceneLayout.fromJson(Map<String, dynamic>.from(shape['data'] as Map));
      layout
        ..setViewState(layout.viewState.copyWith(foldedSpheres: <String>{}))
        ..finishFlow();
      layout
        ..setViewState(layout.viewForScopeState('shelf-chain/shelf-chain', ScopeState.open))
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
      addTearDown(scene.dispose);
      final marks = SceneMarks.of(scene)
        ..expanded = {...layout.viewState.expandedHosts}
        ..scopesOn = {...layout.viewState.openScopes};
      marks.version++;
      scene.applyLayoutToView();
      controller.showRange(_minute(200), _minute(1700));
      controller.scrollTo(0);
      final painter = TimelinePainter(scene, text: unbudgetedText())..debug = true;
      var calm = 0;
      for (int i = 0; i < 300 && calm < 3; i++) {
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), const ui.Size(1920, 1020));
        recorder.endRecording().dispose();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        scene.tick(10);
        final s = scene.stats;
        calm = s.blanks == 0 && s.covers == 0 && !scene.fading && scene.settled ? calm + 1 : 0;
      }
      expect(calm, 3, reason: '장면이 가라앉지 않았습니다');
      // 세로 띠 위 조각(점선이면 박자마다 한 기록)을 x마다 이어 붙여(틈 5px 안) 한 줄기의 길이를 잰다 — 관문 · 굴 문 토막은 한 띠의 몸통 언저리다(이 장면의 가장 큰 몸통 102px + 사슬 — 150px 밑 · 고치기 전에는 450px).
      final runs = <double, List<(double, double)>>{};
      for (final o in painter.debugSink.notes['조각'] ?? const <Object>[]) {
        final n = [for (final s in '$o'.split(RegExp('[ ,]'))) double.tryParse(s)].whereType<double>().toList();
        if ((n[0] - n[2]).abs() > .01) continue;
        (runs[(n[0] * 10).roundToDouble()] ??= []).add((n[1] < n[3] ? n[1] : n[3], n[1] < n[3] ? n[3] : n[1]));
      }
      if (!route) {
        // 옛 길(기본 · 띠 위 조각 없음): 바로잡지 않으면 갈대 공국 → 아랫물국이 위로 가는 줄 알고 선대 줄 위 틈(310)으로 올라 왼쪽으로 231px 간 뒤
        // 443px 내려왔다(683,339 → 699,310 → 468,310 → 468,753). 바로잡으면 곧장 내려간다 — 출발 높이 위아래로 함께 오가는 선이 없다.
        final lines = [for (final o in painter.debugSink.notes['선'] ?? const <Object>[]) '$o'];
        expect(lines, isNotEmpty);
        for (final l in lines) {
          final n = [for (final s in l.split(RegExp('[ ,]'))) double.tryParse(s)].whereType<double>().toList();
          final ys = [for (int i = 1; i < n.length - 1; i += 2) n[i]];
          final up = ys.any((y) => y < ys.first - 5), down = ys.any((y) => y > ys.first + 5);
          expect(up && down, isFalse, reason: '선대 줄 위로 올랐다가 아래로 내려가는 선: $l');
        }
        return;
      }
      expect(runs, isNotEmpty);
      for (final MapEntry(key: x, value: list) in runs.entries) {
        list.sort((a, b) => a.$1.compareTo(b.$1));
        var (lo, hi) = list.first;
        for (final (a, b) in list.skip(1)) {
          if (a - hi > 5) {
            expect(hi - lo, lessThan(150), reason: 'x ${x / 10}: 띠 위 조각 줄기 $lo ~ $hi');
            (lo, hi) = (a, b);
          } else if (b > hi) {
            hi = b;
          }
        }
        expect(hi - lo, lessThan(150), reason: 'x ${x / 10}: 띠 위 조각 줄기 $lo ~ $hi');
      }
    } finally {
      engine.close();
    }
  }, timeout: const Timeout(Duration(minutes: 4)), skip: dll.existsSync() && db('shelf-chain').existsSync() ? false : '찍기 저장소(shelf-chain)와 DLL을 먼저 짓는다');
  }
}

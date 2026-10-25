import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:archive_prototype/scene/paint/paint_pick.dart';
import 'package:flutter_test/flutter_test.dart';

// 한 벌 P3-18 — 앱이 엔진 답을 받아 다시 가르던 **정적인 셈**이 엔진의 `{"op":"layout"}` 답으로 옮겨 갔다(계획 P3 과제 18 · 설계 한 장의 길 가).
// 진짜 자료 처리부(DLL)와 `archive-tool build`로 지은 저장소에서, **옛 길**(앱의 옛 셈 — `RowFlags.legacy` · `ScopeSplit.legacy` · 켠 그릇끼리 `containsAll` ·
// 문화권 `indexWhere`)과 **새 길**(엔진 답의 칸 — `rail` … · `scope_head` … · `within` · `sphere_at`)이 모든 줄 · 변형 줄 · 그릇 · 트랙에서 같고,
// 새 칸을 지운 답으로 쌓은 줄(옛 길)과 그대로 쌓은 줄(새 길)의 자리 · 높이가 1px도 다르지 않음을 굳힌다. 자료는 정답지 자료(가상 이름)와 등불 연대기 견본.
// DLL · 도구가 없으면 건너뛴다(`dev.ps1 engine-build`).
// 칸 그림 갈래(remake-4-cells) 걸음 1에 더함: 배치 갈래가 `fig_wide`에 더한 줄 값 셋(비트 21 ~ 25 직위 줄 더 수 · 26 ~ 27 지도자 층 단 수 − 1 · 28 ~ 30 줄어드는 층 수 —
// 엔진은 칸으로 풀지 않고 원래 정수를 나르기만 함)도 옛 길(`legacy`)과 새 길(`fromAnswer` — 답의 `fig_wide`)이 같음 · 그 값이 있는 시험 자료(f4-legit · f4-office4)를 더함 ·
// 옛 저장소 꼴(비트 3 ~ 5가 0)이면 0 · 한 단 · 0임을 손으로 짠 값으로도 본다(DLL 없이).
// 걸음 5에 더함: 줄어드는 층(비트 28 ~ 30)이 선 줄마다 기본 보기에서 앱이 실제로 줄이는 층 수를 묶는다. 합칠 때 고침(remake-4-final — 배치 판 8 검토 고침
// 3168dfc와 짝): 왕조 · 지위는 줄어드는 층의 셈에 없으므로 사슬(스위치 chain) 켬 · 끔 모두 저장된 값 그대로 읽는다(layout.dart `_bandOf` — 예전의 '사슬로
// 옮긴 왕조 · 지위만큼 덜 읽음'을 걷음 · 사슬이 선 줄의 사슬 묶음만 덜 줄일 수 있음).

/// 엔진 답에서 P3-18이 더한 칸만 지운 사본 — 옛 길(앱의 옛 셈)로 읽히게.
Map<String, dynamic> stripped(Map<String, dynamic> answer) {
  final copy = jsonDecode(jsonEncode(answer)) as Map<String, dynamic>;
  const rowKeys = ['fig_wide_levels', 'rail', 'organ', 'power', 'real', 'hang', 'raised', 'contained', 'cell_rows', 'dynasty', 'leader', 'cabinet', 'events', 'scope_head', 'scope_foot', 'scope_hung'];
  for (final t in copy['tracks'] as List) {
    (t as Map).remove('sphere_at');
    for (final r in t['rows'] as List) {
      for (final k in rowKeys) {
        (r as Map).remove(k);
      }
    }
  }
  for (final v in (copy['variants'] as List? ?? const [])) {
    (v as Map).remove('within');
    for (final r in (v['rows'] as List? ?? const [])) {
      for (final k in ['scope_head', 'scope_foot', 'scope_hung']) {
        (r as Map).remove(k);
      }
    }
  }
  return copy;
}

List<Object?> flagsOf(RowFlags f) => [f.figWide, f.rail, f.organ, f.power, f.real, f.hang, f.raised, f.contained, f.cellRows, f.dynasty, f.leader, f.cabinet, f.events,
      f.officeMore, f.leaderLanes, f.shrink];
List<int>? splitOf(ScopeSplit? s) => s == null ? null : [s.head, s.foot, s.hung];

void main() {
  final dll = File('../engine/target/release/archive_engine.dll'), tool = File('../engine/target/release/archive-tool.exe');
  final ready = Platform.isWindows && dll.existsSync() && tool.existsSync();
  final calendar = File('../engine/tests/fixtures/lay/calendar-slice.json').absolute.path;
  // 저장소 뿌리(`samples/`가 있는 곳) — 연결 폴더(`%TEMP%\ht-…\app` · dev.ps1)에서 돌면 `../..`가 진짜 뿌리가 아니라 연결을 풀어 찾는다.
  String root() {
    try {
      return Directory(Directory('..').resolveSymbolicLinksSync()).parent.path;
    } catch (_) {
      return Directory('../..').absolute.path;
    }
  }

  /// 저장소 하나를 짓고 layout 답을 받는다.
  Future<(String, Map<String, dynamic>)> build(Directory dir, String name, List<String> packs) async {
    final db = '${dir.path}${Platform.pathSeparator}$name.db';
    final built = await Process.run(tool.absolute.path, ['build', db, ...packs, '--now=2026-10-22T09:00:00+09:00', '--calendar=$calendar', '--calendar-narrow'], stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(built.exitCode, 0, reason: '$name: ${built.stderr}');
    final engine = ArchiveEngine(libraryPath: dll.absolute.path);
    await engine.start(db);
    try {
      return (name, Map<String, dynamic>.from((await engine.call({'op': 'layout'}))['data'] as Map));
    } finally {
      try {
        await engine.call({'op': 'close'});
      } catch (_) {}
      engine.close();
    }
  }

  group('한 벌 P3-18 — 정적인 다시 잇기는 엔진 답으로(옛 길 = 새 길)', () {
    late Directory dir;
    late List<(String, Map<String, dynamic>)> stores;
    setUpAll(() async {
      if (!ready) return;
      dir = Directory.systemTemp.createTempSync('ht-layout-static-');
      stores = [
        await build(dir, 'east-asia-nest-sphere', [
          File('../fixtures/oracle/east-asia.json').absolute.path,
          File('../fixtures/oracle/nest-scene.htpack').absolute.path,
          File('../fixtures/oracle/sphere-test.htpack').absolute.path,
        ]),
        await build(dir, 'lantern', ['${root()}${Platform.pathSeparator}samples${Platform.pathSeparator}sample-lantern.json']),
        // 배치 갈래의 줄 값 셋이 있는 시험 자료(형식 4 — 지도자 두 단 · 줄어드는 층 · 직위 줄 더).
        await build(dir, 'f4-legit', [File('../fixtures/oracle/f4-legit.json').absolute.path]),
        await build(dir, 'f4-office4', [File('../fixtures/oracle/f4-office4.json').absolute.path]),
      ];
    });
    tearDownAll(() {
      if (!ready) return;
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('줄 깃발 · 그릇 여백의 가름 · 그릇의 포개짐 · 문화권 자리가 모든 줄 · 변형 · 트랙에서 옛 셈과 같다', () async {
      if (!ready) return markTestSkipped('자료 처리부 빌드가 없습니다(dev.ps1 engine-build)');
      var rows = 0, carried = 0, splits = 0, unsplit = 0, variantRows = 0, scopes = 0, nested = 0, tracks = 0, office = 0, lanes = 0, shrink = 0;
      for (final (name, answer) in stores) {
        final spheres = [for (final x in (answer['spheres'] as List? ?? const [])) '${x['id'] ?? ''}'];
        for (final t in answer['tracks'] as List) {
          final sphere = '${t['sphere'] ?? ''}';
          expect(t['sphere_at'], sphere.isEmpty ? -1 : spheres.indexOf(sphere), reason: '$name · 트랙 ${t['key']}의 문화권 자리');
          tracks++;
          for (final r in t['rows'] as List) {
            final row = Map<String, dynamic>.from(r as Map);
            expect(RowFlags.carried(row) && ScopeSplit.carried(row), isTrue, reason: '$name · 줄 ${row['id']}: 새 칸이 없습니다');
            final packed = (row['fig_wide'] ?? 0) as int, zones = (row['zones'] ?? 0) as int;
            expect(flagsOf(RowFlags.fromAnswer(row)), flagsOf(RowFlags.legacy(packed, zones)), reason: '$name · 줄 ${row['id']}의 줄 깃발(fig_wide $packed · zones $zones)');
            final stored = ((row['scope_pad'] ?? 0) as num).toDouble();
            final split = ScopeSplit.fromAnswer(row);
            expect(splitOf(split), splitOf(ScopeSplit.legacy(stored)), reason: '$name · 줄 ${row['id']}의 그릇 여백 $stored');
            // 배치 갈래의 줄 값 셋: 새 길은 답의 `fig_wide`(엔진이 나르기만) — 옛 저장소 꼴(비트 3 ~ 5가 0)이면 0 · 한 단 · 0.
            final f = RowFlags.fromAnswer(row);
            if (((packed >> 3) & 7) == 0) expect((f.officeMore, f.leaderLanes, f.shrink), (0, 1, 0), reason: '$name · 줄 ${row['id']}: 옛 꼴 줄');
            if (f.officeMore > 0) office++;
            if (f.leaderLanes > 1) lanes++;
            if (f.shrink > 0) shrink++;
            rows++;
            if (((packed >> 3) & 7) != 0) carried++;
            if (stored != 0) split == null ? unsplit++ : splits++;
          }
        }
        final variants = [for (final v in (answer['variants'] as List? ?? const [])) Map<String, dynamic>.from(v as Map)];
        Set<int> rowsOf(Map<String, dynamic> v) => {for (final g in (v['groups'] as List? ?? const [])) for (final row in (g['rows'] as List? ?? const [])) row as int};
        for (final v in variants) {
          for (final r in (v['rows'] as List? ?? const [])) {
            final row = Map<String, dynamic>.from(r as Map);
            expect(ScopeSplit.carried(row), isTrue, reason: '$name · 변형 ${v['key']}의 줄 ${row['row']}: 새 칸이 없습니다');
            expect(splitOf(ScopeSplit.fromAnswer(row)), splitOf(ScopeSplit.legacy(((row['scope_pad'] ?? 0) as num).toDouble())), reason: '$name · 변형 ${v['key']}의 줄 ${row['row']}');
            variantRows++;
          }
          if (v['kind'] != VariantInfo.kindScope) {
            expect(v.containsKey('within'), isFalse, reason: '$name · 그릇이 아닌 변형 ${v['key']}에 within');
            continue;
          }
          final mine = rowsOf(v);
          final legacy = [
            for (final o in variants)
              if (o['kind'] == VariantInfo.kindScope && o['id'] != v['id'] && o['track'] == v['track'] && rowsOf(o).length > mine.length && rowsOf(o).containsAll(mine)) o['id'] as int,
          ]..sort();
          final within = [for (final id in v['within'] as List) id as int]..sort();
          expect(within, legacy, reason: '$name · 그릇 ${v['key']}의 포개짐');
          scopes++;
          if (within.isNotEmpty) nested++;
        }
      }
      // 견준 것이 충분히 많고 갈래마다 하나는 있다 — 옛 저장소 꼴(실리지 않은 줄 값)도 든다.
      expect(rows, greaterThan(100));
      expect(carried, greaterThan(50), reason: '줄 단위 트랙 값이 실린 줄');
      expect(splits, greaterThan(0), reason: '갈라지는 그릇 여백');
      expect(variantRows, greaterThan(0));
      expect(scopes, greaterThan(0), reason: '그릇 변형');
      expect(nested, greaterThan(0), reason: '포개진 그릇(nest-scene)');
      expect(tracks, greaterThan(5));
      // 배치 갈래의 줄 값 셋이 실제로 든 줄(f4-legit — 두 단 · 줄어드는 층 · 직위 줄 더 / f4-office4 — 직위 줄 더 / 등불 — 줄어드는 층).
      expect(office, greaterThan(0), reason: '직위 줄 더 수가 선 줄');
      expect(lanes, greaterThan(0), reason: '지도자 두 단 이상인 줄');
      expect(shrink, greaterThan(0), reason: '줄어드는 층이 선 줄');
      // ignore: avoid_print
      print('P3-18 견줌: 줄 $rows(실린 값 $carried · 갈라진 여백 $splits · 안 갈라진 $unsplit) · 변형 줄 $variantRows · 그릇 $scopes(포개짐 $nested) · 트랙 $tracks'
          ' · 배치 갈래 줄 값(직위 줄 더 $office · 두 단 $lanes · 줄어드는 층 $shrink)');
    });

    test('줄어드는 층이 선 줄 — 기본 보기에서 실제로 줄이는 줄 · 사슬 켬 · 끔 모두 저장된 값(칸 그림 갈래 걸음 5 · 합칠 때 고침)', () async {
      if (!ready) return markTestSkipped('자료 처리부 빌드가 없습니다(dev.ps1 engine-build)');
      // 줄마다 (저장된 값, 사슬 켬 — 기본 보기, 사슬 끔) · 같은 자료의 줄은 한 번만(lantern은 등불 하나 — lantern-sphere 장면의 두 줄과 같은 줄).
      final found = <String, (int, int, int)>{};
      for (final (name, answer) in stores) {
        final on = SceneLayout.fromJson(answer);
        PaintPick.chain = false;
        final off = SceneLayout.fromJson(answer);
        PaintPick.reset();
        for (int r = 0; r < on.rowCount; r++) {
          final spec = on.spec(r);
          if (spec == null || spec.shrink == 0) continue;
          // 접힌 문화권 · 묶음 안이면 그 줄을 편다(가려는 곳 펴기 — 앱의 찾아가기와 같은 길).
          for (final l in [on, off]) {
            l.setViewState(l.revealFor(r));
            l.finishFlow();
          }
          expect([on.isVisible(r), off.isVisible(r)], [true, true], reason: '$name · 줄 $r');
          final g = on.geo(r), o = off.geo(r);
          expect(g.shrunk, lessThanOrEqualTo(o.shrunk), reason: '$name · 줄 $r: 사슬 켬은 덜 줄거나 같음');
          expect(g.stackEnd - g.floorEnd, g.shrunk * G.floor);
          found['$name · 줄 $r'] = (spec.shrink, g.shrunk, o.shrunk);
        }
      }
      // ignore: avoid_print
      print('줄어드는 층 줄(저장 · 사슬 켬 · 사슬 끔): $found');
      // 새 내보내기(배치 판 8 검토 고침 — 왕조 · 지위를 세지 않음)의 줄 다섯: 등불 하연(줄 0 — hayeon#0 · 1) / f4-legit 몸통 트랙 넷(1 · 1 · 2 · 7 —
      // 산호 2층 · 벼랑은 8층을 7에서 자름이 든다 · 계약 1-1 덧붙임). 옛 셈에서 지위 층 몫이던 줄(등불 백사만 따위)은 이제 0이라 빠진다.
      expect(found.length, 5, reason: '줄어드는 층 줄 다섯(등불 하나 · f4-legit 넷)');
      expect(found.values.every((v) => v.$2 == v.$1 && v.$3 == v.$1), isTrue, reason: '사슬 켬 · 끔 모두 저장된 값 그대로(왕조 · 지위는 셈에 없음)');
      expect([for (final e in found.entries) if (e.key.startsWith('lantern')) e.value], [(1, 1, 1)], reason: '등불은 하연 줄 0 하나');
      expect([for (final e in found.entries) if (e.key.startsWith('f4-legit')) e.value.$1], [1, 1, 2, 7], reason: 'f4-legit 넷 — 벼랑은 7에서 자름');
    });

    test('새 칸을 지운 답(옛 길)과 그대로의 답(새 길)으로 쌓은 줄의 자리 · 높이 · 그릇 깊이가 같다', () async {
      if (!ready) return markTestSkipped('자료 처리부 빌드가 없습니다(dev.ps1 engine-build)');
      for (final (name, answer) in stores) {
        final fresh = SceneLayout.fromJson(answer), old = SceneLayout.fromJson(stripped(answer));
        final scopeUids = [for (final v in fresh.variants) if (v.kind == VariantInfo.kindScope) v.uid];
        void same(String when) {
          final total = fresh.tracks.fold<int>(0, (n, t) => n + t.rowCount);
          for (int r = 0; r < total; r++) {
            expect(fresh.isVisible(r), old.isVisible(r), reason: '$name · $when · 줄 $r 보임');
            if (!fresh.isVisible(r)) continue;
            expect(fresh.rowTop(r), old.rowTop(r), reason: '$name · $when · 줄 $r 자리');
            expect(fresh.geo(r).height, old.geo(r).height, reason: '$name · $when · 줄 $r 높이');
            expect(fresh.geo(r).bandTop, old.geo(r).bandTop, reason: '$name · $when · 줄 $r 띠 위');
          }
          for (final uid in scopeUids) {
            expect(fresh.scopeDepthOf(uid), old.scopeDepthOf(uid), reason: '$name · $when · 그릇 $uid 깊이');
          }
        }
        same('처음');
        for (final uid in scopeUids) {
          expect(fresh.openScope(uid, true), old.openScope(uid, true), reason: '$name · 그릇 $uid 켜기');
          same('그릇 $uid 켬');
        }
        same('그릇 모두 켬');
        for (final uid in scopeUids) {
          fresh.openScope(uid, false);
          old.openScope(uid, false);
        }
        same('그릇 모두 끔');
      }
    });
  });

  group('배치 갈래의 줄 값 셋(fig_wide 21 ~ 30) — 옛 길 = 새 길 · 옛 꼴이면 0(DLL 없이)', () {
    /// 비트 3 ~ 5(기간 막대 단 수 + 1 — 줄 단위 트랙 값이 실렸다는 표시)를 세운 값.
    const carried = 1 << 3;
    ({int officeMore, int leaderLanes, int shrink}) layOf(RowFlags f) => (officeMore: f.officeMore, leaderLanes: f.leaderLanes, shrink: f.shrink);

    test('새 칸이 legacy와 fromAnswer(답에 남은 fig_wide)에서 같다', () {
      final cases = <int>[
        0,
        carried,
        carried | 1 << 17 | 1 << 19,
        carried | 1 << 17 | 1 << 19 | 3 << 21 | 1 << 26 | 2 << 28, // 직위 줄 더 셋 · 두 단 · 두 층 줄어듦
        carried | 1 << 17 | 31 << 21 | 3 << 26 | 7 << 28, // 모두 가득
        carried | 3 << 26, // 지도자 칸 없는 줄의 단 비트는 읽지 않음
        1 << 17 | 3 << 21 | 1 << 26 | 2 << 28, // 옛 꼴(비트 3 ~ 5 = 0) — 위 비트가 서도 0
        7 << 3 | 1 << 17 | 1 << 21 | 1 << 28,
      ];
      for (final packed in cases) {
        final old = RowFlags.legacy(packed, 3);
        // 엔진 답 꼴(이름 붙은 칸 + 원래 정수 fig_wide) — add_row_flags와 같은 칸을 legacy에서 옮겨 적는다.
        final answer = <String, dynamic>{
          'fig_wide': packed, 'fig_wide_levels': old.figWide, 'rail': old.rail, 'organ': old.organ ? 1 : 0, 'power': old.power ? 1 : 0,
          'real': old.real ? 1 : 0, 'hang': old.hang, 'raised': old.raised ? 1 : 0, 'contained': old.contained ? 1 : 0,
          'cell_rows': old.cellRows ? 1 : 0, 'dynasty': old.dynasty ? 1 : 0, 'leader': old.leader ? 1 : 0, 'cabinet': old.cabinet ? 1 : 0,
          'events': old.events ? 1 : 0,
        };
        final fresh = RowFlags.fromAnswer(answer);
        expect(flagsOf(fresh), flagsOf(old), reason: 'fig_wide $packed');
        expect(layOf(fresh), RowFlags.layOf(packed), reason: 'fig_wide $packed');
      }
      expect(RowFlags.layOf(carried | 1 << 17 | 3 << 21 | 1 << 26 | 2 << 28), (officeMore: 3, leaderLanes: 2, shrink: 2));
      expect(RowFlags.layOf(carried | 1 << 17 | 31 << 21 | 3 << 26 | 7 << 28), (officeMore: 31, leaderLanes: 4, shrink: 7));
      expect(RowFlags.layOf(carried | 3 << 26), (officeMore: 0, leaderLanes: 1, shrink: 0), reason: '비트 17(지도자 칸)이 없으면 한 단');
    });

    test('옛 저장소(비트 3 ~ 5 = 0)이면 0 · 한 단 · 0 — 위 비트가 서 있어도', () {
      for (final high in [0, 31 << 21, 3 << 26, 7 << 28, 1 << 17 | 31 << 21 | 3 << 26 | 7 << 28]) {
        final packed = high | 1 << 17 | 5; // 인물 단 수(0 ~ 2)가 서도
        expect(layOf(RowFlags.legacy(packed, 0)), (officeMore: 0, leaderLanes: 1, shrink: 0), reason: 'fig_wide $packed');
        expect(layOf(RowFlags.fromAnswer({'rail': -1, 'fig_wide': packed})), (officeMore: 0, leaderLanes: 1, shrink: 0), reason: 'fig_wide $packed');
      }
      // fig_wide가 없는 손 답 · 기본 RowSpec도 같은 값.
      expect(layOf(RowFlags.fromAnswer({'rail': 0})), (officeMore: 0, leaderLanes: 1, shrink: 0));
      const spec = RowSpec();
      expect((spec.officeMore, spec.leaderLanes, spec.shrink), (0, 1, 0));
    });

    test('RowSpec.withFlags가 셋을 그대로 나른다', () {
      final spec = RowSpec.withFlags(RowFlags.legacy(carried | 1 << 17 | 1 << 19 | 2 << 21 | 1 << 26 | 3 << 28, 0));
      expect((spec.officeMore, spec.leaderLanes, spec.shrink), (2, 2, 3));
      expect((spec.leader, spec.cellRows, spec.rail), (true, true, 0), reason: '이웃 비트도 그대로');
    });
  });
}

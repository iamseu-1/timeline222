import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/engine.dart';
import 'package:archive_prototype/scene/layout.dart';
import 'package:flutter_test/flutter_test.dart';

// 한 벌 P3-18 — 앱이 엔진 답을 받아 다시 가르던 **정적인 셈**이 엔진의 `{"op":"layout"}` 답으로 옮겨 갔다(계획 P3 과제 18 · 설계 한 장의 길 가).
// 진짜 자료 처리부(DLL)와 `archive-tool build`로 지은 저장소에서, **옛 길**(앱의 옛 셈 — `RowFlags.legacy` · `ScopeSplit.legacy` · 켠 그릇끼리 `containsAll` ·
// 문화권 `indexWhere`)과 **새 길**(엔진 답의 칸 — `rail` … · `scope_head` … · `within` · `sphere_at`)이 모든 줄 · 변형 줄 · 그릇 · 트랙에서 같고,
// 새 칸을 지운 답으로 쌓은 줄(옛 길)과 그대로 쌓은 줄(새 길)의 자리 · 높이가 1px도 다르지 않음을 굳힌다. 자료는 정답지 자료(가상 이름)와 등불 연대기 견본.
// DLL · 도구가 없으면 건너뛴다(`dev.ps1 engine-build`).

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

List<Object?> flagsOf(RowFlags f) => [f.figWide, f.rail, f.organ, f.power, f.real, f.hang, f.raised, f.contained, f.cellRows, f.dynasty, f.leader, f.cabinet, f.events];
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
      var rows = 0, carried = 0, splits = 0, unsplit = 0, variantRows = 0, scopes = 0, nested = 0, tracks = 0;
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
      // ignore: avoid_print
      print('P3-18 견줌: 줄 $rows(실린 값 $carried · 갈라진 여백 $splits · 안 갈라진 $unsplit) · 변형 줄 $variantRows · 그릇 $scopes(포개짐 $nested) · 트랙 $tracks');
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
}

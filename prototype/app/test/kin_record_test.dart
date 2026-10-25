import 'dart:convert';
import 'dart:io';

import 'package:archive_prototype/ui/kin/kin_layout.dart';
import 'package:archive_prototype/ui/kin/kin_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kin_layout_test.dart' show kinSynth, sampleOn;

// D1-N1 — 계보 뼈대 기록(열 꼴 JSON · 설계 8-1 · 이음새 기록 D1-E ② ③)의 풀기 · 덩어리 합치기 검사.
//
// ① 손 고정 자료(설계 2-6의 7명)를 풀고 되돌린 기록이 한 글자도 같음 · 꼴이 어긋난 기록은 FormatException.
// ② 작업자 isolate 풀기 = 이 isolate에서 푼 것 · `lib/ui/kin/`에서 JSON 풀기는 `_kinWork` 하나뿐(소스를 훑음).
// ③ 덩어리: D1-E ③의 나누기 규칙을 옮긴 대역([splitRecords] — 검사 전용)으로 나눈 기록을 어떤 차례로 합쳐도 한 벌과 바이트까지 같음,
//    한 벌 번호 찾기(locate) · 덩어리를 차례로 받기(kinReveal).
// ④ D1-E의 덩어리 고정 자료(`test/fixtures/kin-chunks-*.json`)가 있으면 그것도 합쳐 한 벌과 견줌 — 없으면 건너뜀(결합 때 붙임).
// ⑤ 합성 5만 명 기록의 크기 · 풀기 시간(기록).
// 이름은 모두 가상이다.

/// 색 · 파 · 칸 · 덧선 · 두 나라까지 갖춘 합성 한 벌(앞 차례). 칸 표는 번호 차례, 덧선은 `(to, from, 갈래, gen)` 차례(D1-E ②).
KinSkeleton richSkeleton(int n, {int seed = 13}) {
  final base = kinSynth(n, seed: seed, roots: 3, uid: 'kin:h-rich');
  var s = seed * 7 + 1;
  int rand(int m) {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return (s >> 8) % m;
  }

  final bits = base.bits.toList();
  final branches = <Map<String, Object>>[
    {'uid': 'house:h-rich', 'name': '물빛 온씨', 'color': '#d9c3a0', 'at': 0, 'up': -1},
  ];
  final branchOf = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final p = base.par[i];
    branchOf[i] = p >= 0 ? branchOf[p] : 0;
    if (bits[i] & kKinFounder != 0) {
      branches.add({'uid': 'house:h-rich-b$i', 'name': '갈래 $i파', 'color': '#b7cfa4', 'at': i, 'up': branchOf[i]});
      branchOf[i] = branches.length - 1;
    }
  }
  // 파조를 못 푼 파 하나(at −1).
  branches.add({'uid': 'house:h-rich-lost', 'name': '잃은 파', 'color': '#c9b3d6', 'at': -1, 'up': 0});
  final color = List<int>.filled(n, 0), color2 = List<int>.filled(n, 0);
  final cells = <String, int>{};
  var two = false;
  for (var i = 0; i < n; i++) {
    if (bits[i] & kKinLeader == 0) continue;
    color[i] = 1 + rand(3);
    cells['test/garam|leader:$i'] = i;
    if (rand(4) == 0) {
      bits[i] |= kKinTwoPolities;
      color2[i] = 1 + rand(3);
      cells['test/nuri|leader:$i'] = i;
      two = true;
    }
  }
  final lines = <List<int>>[];
  for (var i = 1; i < n; i++) {
    if (bits[i] & kKinSide != 0) lines.add([rand(n), i, kKinEdgeAdopted, 1]);
    if (rand(150) == 0) lines.add([rand(n), i, kKinEdgeSkip, 2 + rand(3)]);
  }
  lines.removeWhere((l) => l[0] == l[1]);
  lines.sort((a, b) {
    for (final k in const [1, 0, 2, 3]) {
      final c = a[k].compareTo(b[k]);
      if (c != 0) return c;
    }
    return 0;
  });
  return kinFromMap({
    'v': 1,
    'uid': 'kin:h-rich',
    'n': n,
    'gens': base.gens,
    'par': base.par.toList(),
    'size': base.size.toList(),
    'gen': base.gen.toList(),
    'bits': bits,
    'edge': base.edge.toList(),
    'branch': branchOf,
    'color': color,
    'color2': two ? color2 : <int>[],
    'name': [for (var i = 0; i < n; i++) '온 사람$i'],
    'sub': [for (var i = 0; i < n; i++) i.isEven ? '${1400 + i % 300}~${1450 + i % 300}' : ''],
    'key': base.keys,
    'extra': [for (final l in lines) ...l],
    'colors': ['', '#a0bcc5', '#e3b5a4', '#9fc2d8'],
    'branches': branches,
    'cells': cells,
    'stubs': <String, Object>{},
    'warnings': ['고리 1건을 끊었습니다(가상)'],
  });
}

/// D1-E ③의 나누기 규칙을 옮긴 대역(검사 전용 — 앱은 나누지 않음). 기록 목록(뿌리 기록이 맨 앞).
/// 뗄 마디: 기록의 마디 수가 [limit]을 넘는 동안, 그 기록의 뿌리가 아닌 마디 가운데 그 기록 안 하위 수가 2 이상 · 기록 마디 수 미만인
/// 파조 중 가장 큰 것(같으면 앞 차례) — 파조가 없으면 아무 마디. 숲(뿌리 기록)의 나무 뿌리도 기록 전체를 품지 않으면 뗄 수 있다.
List<Map<String, Object?>> splitRecords(KinSkeleton f, int limit) {
  final cut = <int>{};
  List<int> membersOf(int r) {
    final out = <int>[];
    final a = r < 0 ? 0 : r, b = r < 0 ? f.n : r + f.size[r];
    for (var i = a; i < b;) {
      out.add(i);
      i += cut.contains(i) && i != r ? f.size[i] : 1;
    }
    return out;
  }

  int localSize(int j) {
    var c = 0;
    final end = j + f.size[j];
    for (var i = j; i < end;) {
      c++;
      i += cut.contains(i) && i != j ? f.size[i] : 1;
    }
    return c;
  }

  void splitFrom(int r) {
    final mine = <int>[];
    while (true) {
      final m = membersOf(r);
      if (m.length <= limit) break;
      var best = -1, bestSize = 1, bestFounder = false;
      for (final j in m) {
        if (j == r || cut.contains(j)) continue;
        final ls = localSize(j);
        if (ls < 2 || ls >= m.length) continue;
        final fo = f.bits[j] & kKinFounder != 0;
        if ((fo && !bestFounder) || (fo == bestFounder && ls > bestSize)) {
          best = j;
          bestSize = ls;
          bestFounder = fo;
        }
      }
      if (best < 0) break;
      cut.add(best);
      mine.add(best);
    }
    for (final j in mine) {
      splitFrom(j);
    }
  }

  splitFrom(-1);

  String uidOf(int j) {
    if (f.bits[j] & kKinFounder != 0) {
      for (final b in f.branches) {
        if (b.at == j) return 'kin:${b.uid.substring('house:'.length)}';
      }
    }
    return '${f.key}#${f.keys[j]}';
  }

  final where = <int, (String, int)>{};
  Map<String, Object?> build(int r) {
    final m = membersOf(r);
    final local = <int, int>{for (var k = 0; k < m.length; k++) m[k]: k};
    final uid = r < 0 ? f.key : uidOf(r);
    final isStub = [for (final i in m) cut.contains(i) && i != r];
    final real = <int>{
      for (var k = 0; k < m.length; k++)
        if (!isStub[k]) m[k],
    };
    final par = [for (final i in m) i == r ? -1 : (f.par[i] < 0 ? -1 : local[f.par[i]]!)];
    final size = List<int>.filled(m.length, 1);
    for (var k = m.length - 1; k >= 0; k--) {
      if (par[k] >= 0) size[par[k]] += size[k];
    }
    final stubs = <String, Object>{};
    for (var k = 0; k < m.length; k++) {
      if (!isStub[k]) continue;
      stubs['$k'] = {'key': uidOf(m[k]), 'n': f.size[m[k]]};
      where[m[k]] = (uid, k);
    }
    final lines = <List<int>>[];
    final far = <Map<String, Object>>[];
    for (var e = 0; e < f.extra.length; e += 4) {
      final from = f.extra[e], to = f.extra[e + 1];
      if (!real.contains(to)) continue;
      if (real.contains(from)) {
        lines.add([local[from]!, local[to]!, f.extra[e + 2], f.extra[e + 3]]);
      } else {
        far.add({'from': f.keys[from], 'fromAt': from, 'to': local[to]!, 'kind': f.extra[e + 2], 'gen': f.extra[e + 3]});
      }
    }
    lines.sort((a, b) {
      for (final k in const [1, 0, 2, 3]) {
        final c = a[k].compareTo(b[k]);
        if (c != 0) return c;
      }
      return 0;
    });
    var gens = 0, two = false;
    for (final i in m) {
      if (f.gen[i] + 1 > gens) gens = f.gen[i] + 1;
      if (f.bits[i] & kKinTwoPolities != 0) two = true;
    }
    return {
      'v': 1,
      'uid': uid,
      'n': m.length,
      'gens': gens,
      'par': par,
      'size': size,
      'gen': [for (final i in m) f.gen[i]],
      'bits': [for (var k = 0; k < m.length; k++) f.bits[m[k]] | (isStub[k] ? kKinStub : 0)],
      'edge': [for (final i in m) f.edge[i]],
      'branch': [for (final i in m) f.branch[i]],
      'color': [for (final i in m) f.color[i]],
      'color2': two ? [for (final i in m) f.color2[i]] : <int>[],
      'name': [for (final i in m) f.name[i]],
      'sub': [for (final i in m) f.sub[i]],
      'key': [for (final i in m) f.keys[i]],
      'extra': [for (final l in lines) ...l],
      'colors': f.colors,
      'branches': [for (final b in f.branches) b.toJson()],
      'cells': {
        for (final e in f.cells.entries)
          if (real.contains(e.value)) e.key: local[e.value]!,
      },
      'stubs': stubs,
      'warnings': r < 0 ? f.warnings : <String>[],
      if (r >= 0) 'root': {'uid': f.key, 'at': r, 'up': where[r]!.$1, 'upAt': where[r]!.$2},
      if (far.isNotEmpty) 'extraFar': far,
    };
  }

  return [build(-1), for (final j in cut.toList()..sort()) build(j)];
}

/// 기록들을 뿌리 기록부터 꼬투리를 따라 모두 합친다 — [last]면 늘 마지막 꼬투리부터.
KinSkeleton joinAll(List<Map<String, Object?>> records, String rootUid, {bool last = false}) {
  final byUid = {for (final r in records) r['uid'] as String: kinFromMap(jsonDecode(jsonEncode(r)) as Map<String, dynamic>)};
  var s = byUid[rootUid]!;
  while (s.stubs.isNotEmpty) {
    final keys = (s.stubs.keys.toList()..sort()).map((k) => s.stubs[k]!.key).toList();
    final next = byUid[last ? keys.last : keys.first];
    expect(next, isNotNull);
    final merged = mergeKin(s, next!);
    expect(identical(merged, s), isFalse);
    s = merged;
  }
  return s;
}

void main() {
  group('풀기', () {
    test('손 고정 자료(설계 2-6의 7명) — 열 · 표 · 되돌린 기록이 같은 글', () {
      final s = kinFromMap(sampleOn);
      expect(s.key, 'kin:h-on');
      expect(s.n, 7);
      expect(s.gens, 5);
      expect(s.keys[1], 'f:kin-example/f-baram');
      expect(s.indexOfKey('f:kin-example/f-na'), 5);
      expect(s.indexOfKey('없음'), -1);
      expect(s.branches[2], const KinBranch(uid: 'house:h-on-sol', name: '솔군파', color: '#c9b3d6', at: 2, up: 1));
      expect(s.cells['kin-example/garam|leader:1'], 6);
      expect(s.color2, List<int>.filled(7, 0));
      expect(s.children(0).toList(), [1, 6]);
      expect(s.children(3).toList(), [4, 5]);
      expect(s.roots().toList(), [0]);
      expect(s.bits[3] & kKinUnknown, kKinUnknown);
      expect(s.root, isNull);
      expect(s.fullIndexOf(6), 6);
      expect(s.locate(4), (at: 4, stub: -1));
      expect(s.locate(7), (at: -1, stub: -1));
      expect(jsonEncode(s.toRecord()), jsonEncode(sampleOn));
      expect(kinEdgeKind(kKinEdgeSkip | kKinEdgeFaint), kKinEdgeSkip);
      expect(kinEdgeIsFaint(kKinEdgeAdopted | kKinEdgeFaint), isTrue);
      expect(kinEdgeIsFaint(kKinEdgeAdopted), isFalse);
    });

    test('8-1 초안 꼴(머리 key 글 · 열 keys)과 조회 uid도 받음', () {
      final m = Map<String, dynamic>.of(sampleOn)
        ..remove('uid')
        ..remove('key');
      m['keys'] = sampleOn['key'];
      expect(kinFromMap(m, uid: 'kin:h-on').key, 'kin:h-on');
      expect(kinFromMap(m).keys, sampleOn['key']);
      expect(kinFromMap({...m, 'key': 'kin:h-other'}).key, 'kin:h-other');
      expect(kinFromMap({'kin': sampleOn}).n, 7);
    });

    test('꼴이 어긋난 기록은 FormatException', () {
      Map<String, dynamic> bad(String k, Object? v) => Map<String, dynamic>.of(sampleOn)..[k] = v;
      for (final (why, m) in [
        ('판', bad('v', 2)),
        ('열 길이', bad('gen', [0, 1, 2])),
        ('정수 아님', bad('bits', [33, 81, 81, 67, 65, 65, '33'])),
        ('앞 차례 아님', bad('par', [-1, 0, 1, 2, 3, 3, 1])),
        ('하위 수', bad('size', [7, 5, 4, 3, 1, 2, 1])),
        ('세대가 부모 이하', bad('gen', [0, 1, 2, 3, 3, 4, 1])),
        ('세대 줄 수', bad('gens', 3)),
        ('꼬투리에 하위', bad('bits', [33, 81 | kKinStub, 81, 67, 65, 65, 33])),
        ('덧선 범위', bad('extra', [0, 9, 1, 1])),
        ('덧선 넷씩', bad('extra', [0, 1, 1])),
        ('n', bad('n', -1)),
      ]) {
        expect(() => kinFromMap(m), throwsFormatException, reason: why);
      }
    });

    test('작업자 isolate 풀기 = 이 isolate에서 푼 것', () async {
      final s = richSkeleton(1500);
      final text = jsonEncode(s.toRecord());
      final got = await decodeKin(text);
      expect(jsonEncode(got.toRecord()), text);
      expect(got.par, isA<List<int>>());
      // 기록에 uid가 없으면 조회 uid로.
      final noUid = jsonEncode(Map<String, dynamic>.of(sampleOn)..remove('uid'));
      expect((await decodeKin(noUid, uid: 'kin:h-on')).key, 'kin:h-on');
      await expectLater(decodeKin('[1, 2]'), throwsFormatException);
      await expectLater(decodeKin(jsonEncode(Map<String, dynamic>.of(sampleOn)..['v'] = 9)), throwsFormatException);
    });

    test('lib/ui/kin/ 안에서 JSON 풀기는 작업자 일 _kinWork 하나뿐', () {
      final dir = Directory('lib/ui/kin');
      expect(dir.existsSync(), isTrue);
      final decode = RegExp(r'jsonDecode\s*\(|json\.decode\s*\(|JsonDecoder\s*\(');
      var seen = 0;
      for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        // Windows 러너의 체크아웃은 줄끝을 CRLF로 바꾼다(core.autocrlf) — 아래 '\n}\n'(함수 끝) 찾기가 줄끝에 매이지 않게 LF로 맞춘다.
        final text = f.readAsStringSync().replaceAll('\r\n', '\n');
        final hits = decode.allMatches(text).toList();
        if (f.path.endsWith('kin_record.dart')) {
          expect(hits.length, 1, reason: 'kin_record.dart의 JSON 풀기는 하나');
          final start = text.indexOf('_KinWire _kinWork(');
          final end = text.indexOf('\n}\n', start);
          expect(start, greaterThan(0));
          expect(hits.single.start, inInclusiveRange(start, end), reason: 'JSON 풀기는 _kinWork 안');
          // _kinWork는 decodeKin의 Isolate.run 안에서만 부른다.
          final calls = RegExp(r'_kinWork\(').allMatches(text).map((m) => m.start).toList();
          expect(calls.length, 2);
          final run = text.indexOf('Isolate.run(() => _kinWork(');
          expect(run, greaterThan(0));
          expect(calls.first, run + 'Isolate.run(() => '.length);
          seen++;
        } else {
          expect(hits, isEmpty, reason: '${f.path}이 UI isolate에서 JSON을 풂');
        }
      }
      expect(seen, 1);
    });
  });

  group('덩어리 합치기', () {
    for (final (n, limit) in [(400, 120), (1500, 300), (1500, 40)]) {
      test('합성 $n명 · 상한 $limit — 어떤 차례로 합쳐도 한 벌과 바이트까지 같음', () {
        final full = richSkeleton(n, seed: n + limit);
        final whole = jsonEncode(full.toRecord());
        final recs = splitRecords(full, limit);
        expect(recs.length, greaterThan(1), reason: '나뉘어야 함');
        final total = recs.fold<int>(0, (a, r) => a + (r['n'] as int));
        // 꼬투리 하나마다 그 사람이 두 기록에 있음.
        expect(total, n + recs.length - 1);
        for (final r in recs) {
          final s = kinFromMap(jsonDecode(jsonEncode(r)) as Map<String, dynamic>);
          // 덩어리 안 번호 → 한 벌 번호 → 같은 사람.
          for (var i = 0; i < s.n; i++) {
            expect(s.keys[i], full.keys[s.fullIndexOf(i)]);
          }
        }
        expect(jsonEncode(joinAll(recs, full.key).toRecord()), whole);
        expect(jsonEncode(joinAll(recs, full.key, last: true).toRecord()), whole);
        // 합친 뼈대의 자리 셈 = 한 벌의 자리 셈.
        final joined = joinAll(recs, full.key);
        expect(kinLayout(joined, kinDefaultOpen(joined)).x, kinLayout(full, kinDefaultOpen(full)).x);
      });
    }

    test('한 벌 번호 찾기 · 덩어리를 차례로 받기(kinReveal)', () async {
      final full = richSkeleton(1500, seed: 77);
      final recs = splitRecords(full, 60);
      final byUid = {for (final r in recs) r['uid'] as String: jsonEncode(r)};
      final root = kinFromMap(jsonDecode(byUid[full.key]!) as Map<String, dynamic>);
      var hidden = 0;
      for (var g = 0; g < full.n; g++) {
        final spot = root.locate(g);
        if (spot.at >= 0) {
          expect(root.keys[spot.at], full.keys[g]);
        } else {
          hidden++;
          expect(spot.stub, greaterThanOrEqualTo(0));
          final from = root.fullIndexOf(spot.stub);
          expect(g, inExclusiveRange(from, from + root.stubs[spot.stub]!.n));
        }
      }
      expect(hidden, greaterThan(0));
      expect(root.locate(full.n), (at: -1, stub: -1));
      // 가장 깊이 숨은 사람을 드러냄.
      var deepest = 0, depth = -1;
      for (var g = 0; g < full.n; g++) {
        if (full.gen[g] > depth) {
          deepest = g;
          depth = full.gen[g];
        }
      }
      final asked = <String>[];
      final got = await kinReveal(root, deepest, (uid) async {
        asked.add(uid);
        return byUid[uid];
      });
      expect(got.at, greaterThanOrEqualTo(0));
      expect(got.skel.keys[got.at], full.keys[deepest]);
      expect(asked.toSet().length, asked.length, reason: '같은 덩어리를 두 번 받지 않음');
      // 없는 덩어리면 −1로 끝남.
      final missing = await kinReveal(root, deepest, (uid) async => null);
      expect(missing.at, root.locate(deepest).at);
    });

    test('꼬투리를 못 찾으면 그대로', () {
      final s = kinFromMap(sampleOn);
      final other = kinFromMap(sampleOn);
      expect(identical(mergeKin(s, other), s), isTrue);
    });

    test('kinRefOf — x_lineage kinAt · x_kin', () {
      expect(kinRefOf(['kin:h-on', 6]), (key: 'kin:h-on', at: 6));
      expect(kinRefOf({'key': 'kin:h-on', 'at': 1, 'n': 5}), (key: 'kin:h-on', at: 1));
      expect(kinRefOf({'key': 'kin:h-on'}), (key: 'kin:h-on', at: -1));
      expect(kinRefOf('kin:h-on'), isNull);
      expect(kinRefOf(null), isNull);
    });
  });

  test('웹 대조용 한 벌 기록 내보내기(KIN_DUMP=<폴더>일 때만)', () {
    final out = Platform.environment['KIN_DUMP'];
    if (out == null || out.isEmpty) return;
    for (final (n, seed) in [(400, 520), (1500, 1800), (3000, 31)]) {
      final s = richSkeleton(n, seed: seed);
      File('$out/kin-rich$n.json').writeAsStringSync(jsonEncode([
        {'uid': s.key, 'kind': 'kin', 'json': jsonEncode(s.toRecord())},
      ]));
    }
  });

  group('D1-E 고정 자료(있으면)', () {
    // KIN_FIXTURES=<폴더>면 그 폴더(저장소 밖에서 export/kin.mjs splitKin으로 나눈 기록)를 본다.
    final dir = Directory(Platform.environment['KIN_FIXTURES'] ?? 'test/fixtures');
    final chunks = dir.existsSync()
        ? (dir.listSync().whereType<File>().where((f) => RegExp(r'kin-chunks-.*\.json$').hasMatch(f.path)).toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];
    test('덩어리 고정 자료 ${chunks.length}개 — 합친 것 = 한 벌 기록', () {
      if (chunks.isEmpty) {
        markTestSkipped('D1-E의 kin-chunks-*.json이 아직 없음 — 결합 때 붙임');
        return;
      }
      for (final f in chunks) {
        final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final recs = [for (final r in doc['records'] as List) _recordOf(r)];
        final name = f.uri.pathSegments.last.replaceFirst('kin-chunks-', '');
        final whole = File('${dir.path}/kin-$name');
        expect(whole.existsSync(), isTrue, reason: '한 벌 기록 kin-$name');
        final wholeRecs = [for (final r in jsonDecode(whole.readAsStringSync()) as List) r as Map<String, dynamic>];
        for (final w in wholeRecs.where((r) => r['kind'] == 'kin')) {
          final text = w['json'] as String;
          final one = jsonDecode(text) as Map<String, dynamic>;
          final uid = one['uid'] as String;
          if (!recs.any((r) => r['uid'] == uid)) continue;
          final joined = joinAll(recs, uid);
          // 덩어리 번호 → 한 벌 번호(root.at · 꼬투리 n) → 같은 사람.
          final oneKeys = (one['key'] as List).cast<String>();
          for (final r in recs) {
            final s = kinFromMap(r);
            for (var i = 0; i < s.n; i++) {
              expect(s.keys[i], oneKeys[s.fullIndexOf(i)], reason: '${f.path} ${s.key} $i');
            }
          }
          expect(jsonEncode(joined.toRecord()), jsonEncode(kinFromMap(one).toRecord()), reason: '${f.path} $uid');
          expect(jsonEncode(joined.toRecord()), text, reason: '${f.path} $uid 바이트');
        }
      }
    });
  });

  test('합성 5만 명 기록 — 크기 · 작업자 isolate 풀기 시간(기록)', () async {
    final s = richSkeleton(50000, seed: 5);
    final text = jsonEncode(s.toRecord());
    await decodeKin(text); // 데우기
    final times = <int>[];
    for (var k = 0; k < 5; k++) {
      final w = Stopwatch()..start();
      final got = await decodeKin(text);
      times.add(w.elapsedMicroseconds);
      expect(got.n, 50000);
    }
    times.sort();
    final local = Stopwatch()..start();
    kinFromMap(jsonDecode(text) as Map<String, dynamic>);
    final localMs = local.elapsedMicroseconds / 1000;
    // ignore: avoid_print
    print('kin 5만 기록: ${(utf8.encode(text).length / 1024 / 1024).toStringAsFixed(2)}MB · '
        '작업자 풀기(받기까지) 가운데 ${(times[2] / 1000).toStringAsFixed(1)}ms (최소 ${(times.first / 1000).toStringAsFixed(1)} · 최대 ${(times.last / 1000).toStringAsFixed(1)}) · '
        '같은 isolate 풀기 ${localMs.toStringAsFixed(1)}ms');
    expect(times[2], lessThan(5000000));
  });
}

Map<String, dynamic> _recordOf(Object? r) {
  if (r is Map && r['json'] is String) return jsonDecode(r['json'] as String) as Map<String, dynamic>;
  return (r as Map).cast<String, dynamic>();
}

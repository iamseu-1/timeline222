import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive_prototype/ui/kin/kin_layout.dart';
import 'package:archive_prototype/ui/kin/kin_record.dart';
import 'package:archive_prototype/ui/kin/kin_rows.dart';
import 'package:flutter_test/flutter_test.dart';

// D1-N1 — 세계표 정수 칸 셈(설계 `docs/설계-10건/1-2-계승과-가문-확정.md` 4-4)과 승계표 줄 규칙(3-4)의 Dart 옮김 검사.
//
// ① 손셈 견본: 설계 2-6 · 8-1의 가상 견본(물빛 온씨 7명)과 옆구리 덧선 · 뿌리 둘 · 건너뛴 세대가 있는 11명 견본의 자리를 손으로 셈한 값.
// ② 접힘 32가지: 4-4 식을 그대로 옮긴 재귀 대역(이 파일의 [refLayout])과 정수까지 같은지 — 합성 견본 둘.
// ③ 승계표 줄: 손셈(건너뛰기 · 복위 · 수준 넷) + 성질(한 사람 한 번 · 줄 수 ≤ 사람 + 지도자).
// ④ 정답 자리(D1-E의 `test/fixtures/kin-golden-*.json`)가 있으면 그것과 정수 대조 — 없으면 건너뜀(결합 때 붙임).
// 이름은 모두 가상이다.

/// 손 고정 자료 — 설계 2-6을 줄인 8-1 예시(D1-E ② 꼴: 머리 `uid` · 열 `key`).
const sampleOn = {
  'v': 1,
  'uid': 'kin:h-on',
  'n': 7,
  'gens': 5,
  'par': [-1, 0, 1, 2, 3, 3, 0],
  'size': [7, 5, 4, 3, 1, 1, 1],
  'gen': [0, 1, 2, 3, 4, 4, 1],
  'bits': [33, 81, 81, 67, 65, 65, 33],
  'edge': [0, 0, 0, 0, 0, 0, 0],
  'branch': [0, 1, 2, 2, 2, 2, 0],
  'color': [1, 0, 0, 0, 0, 0, 1],
  'color2': <int>[],
  'name': ['첫 임금', '바람대군', '솔군', '미상', '온 가람', '온 나래', '둘째 임금'],
  'sub': ['가람 나라 1대 · 1400~1418', '1402~', '', '', '', '', '가람 나라 2대 · 1418~1450'],
  'key': [
    'c:kin-example/garam|leader:0',
    'f:kin-example/f-baram',
    'f:kin-example/f-sol',
    'f:kin-example/f-sol-x',
    'f:kin-example/f-ga',
    'f:kin-example/f-na',
    'c:kin-example/garam|leader:1',
  ],
  'extra': <int>[],
  'colors': ['', '#a0bcc5'],
  'branches': [
    {'uid': 'house:h-on', 'name': '물빛 온씨', 'color': '#d9c3a0', 'at': 0, 'up': -1},
    {'uid': 'house:h-on-baram', 'name': '바람대군파', 'color': '#b7cfa4', 'at': 1, 'up': 0},
    {'uid': 'house:h-on-sol', 'name': '솔군파', 'color': '#c9b3d6', 'at': 2, 'up': 1},
  ],
  'cells': {'kin-example/garam|leader:0': 0, 'kin-example/garam|leader:1': 6},
  'stubs': <String, Object>{},
  'warnings': <String>[],
};

/// 열쇠 차례 고정 기록을 JSON 글로(엔진 `entity` 답의 `json`과 같은 꼴).
String recordText(Map<String, Object?> m) => jsonEncode(m);

/// 앞 차례 부모 줄 · 세대 · 비트로 뼈대를 짓는다(크기 · 이름 · 열쇠는 셈해 채움). 검사 · 합성 견본 공용.
KinSkeleton kinFromNodes(
  List<int> par,
  List<int> gen,
  List<int> bits, {
  String uid = 'kin:test',
  List<int>? edge,
  List<int>? branch,
  List<String>? names,
  List<int> extra = const [],
  Map<int, KinStub> stubs = const {},
  List<Map<String, Object>> branches = const [],
  Map<String, int> cells = const {},
}) {
  final n = par.length;
  final size = List<int>.filled(n, 1);
  for (var i = n - 1; i >= 0; i--) {
    if (par[i] >= 0) size[par[i]] += size[i];
  }
  var gens = 0;
  for (final g in gen) {
    if (g + 1 > gens) gens = g + 1;
  }
  return kinFromMap({
    'v': 1,
    'uid': uid,
    'n': n,
    'gens': gens,
    'par': par,
    'size': size,
    'gen': gen,
    'bits': bits,
    'edge': edge ?? List<int>.filled(n, 0),
    'branch': branch ?? List<int>.filled(n, 0),
    'color': List<int>.filled(n, 0),
    'color2': <int>[],
    'name': names ?? [for (var i = 0; i < n; i++) '사람 $i'],
    'sub': List<String>.filled(n, ''),
    'key': [for (var i = 0; i < n; i++) 'f:test/p$i'],
    'extra': extra,
    'colors': [''],
    'branches': branches,
    'cells': cells,
    'stubs': {
      for (final e in stubs.entries) '${e.key}': {'key': e.value.key, 'n': e.value.n},
    },
    'warnings': <String>[],
  });
}

/// 정해진 씨앗의 합성 계보(앞 차례). 깊이 40 안 · 옆구리 덧선 · 건너뛴 세대 · 파조 · 지도자 · (원하면) 꼬투리 잎.
KinSkeleton kinSynth(int n, {int seed = 7, int roots = 3, bool stubs = false, String uid = 'kin:synth'}) {
  var s = seed;
  int rand(int m) {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return (s >> 8) % m;
  }

  final par = List<int>.filled(n, -1), gen = List<int>.filled(n, 0), bits = List<int>.filled(n, 1), edge = List<int>.filled(n, 0);
  final stack = <int>[0];
  var rootsLeft = roots - 1;
  for (var i = 1; i < n; i++) {
    while (stack.length > 1 && (rand(100) < 52 || stack.length > 40)) {
      stack.removeLast();
    }
    if (rootsLeft > 0 && rand(n ~/ roots + 1) == 0) {
      rootsLeft--;
      stack
        ..clear()
        ..add(i);
      continue;
    }
    if (stack.isEmpty) {
      stack.add(i);
      continue;
    }
    final p = stack.last;
    par[i] = p;
    final jump = rand(20) == 0 ? 2 + rand(3) : 1;
    gen[i] = gen[p] + jump;
    if (jump > 1) edge[i] = kKinEdgeSkip;
    if (rand(8) == 0) {
      bits[i] |= kKinSide;
      if (jump == 1) edge[i] = kKinEdgeAdopted;
    }
    if (rand(40) == 0) bits[i] |= kKinLeader;
    if (rand(97) == 0) bits[i] |= kKinUnknown;
    if (rand(9) == 0) edge[i] |= kKinEdgeFaint;
    stack.add(i);
  }
  final size = List<int>.filled(n, 1);
  for (var i = n - 1; i >= 0; i--) {
    if (par[i] >= 0) size[par[i]] += size[i];
  }
  for (var i = 1; i < n; i++) {
    if (size[i] >= 3 && rand(25) == 0) bits[i] |= kKinFounder;
  }
  final stubMap = <int, KinStub>{};
  if (stubs) {
    for (var i = 1; i < n; i++) {
      if (size[i] == 1 && rand(30) == 0) {
        bits[i] |= kKinStub;
        stubMap[i] = KinStub(key: '$uid#p$i', n: 2 + rand(50));
      }
    }
  }
  return kinFromNodes(par, gen, bits, uid: uid, edge: edge, stubs: stubMap);
}

/// 4-4 식을 그대로 옮긴 재귀 대역(검사 전용 — 빠른 구현과 견줌).
({Int32List x, Int32List w, int width, List<List<int>> rows}) refLayout(KinSkeleton s, Uint8List open) {
  final x = Int32List(s.n)..fillRange(0, s.n, -1), w = Int32List(s.n);
  List<int> kids(int i) => open[i] != 0 && s.bits[i] & kKinStub == 0 ? s.children(i).toList() : const [];
  int side(int i) => s.bits[i] & kKinSide != 0 ? 1 : 0;
  int measure(int i) {
    final k = kids(i);
    var sum = 0;
    for (final c in k) {
      sum += measure(c);
    }
    return w[i] = k.isEmpty ? 4 + side(i) : side(i) + sum;
  }

  final rows = List<List<int>>.generate(s.gens, (_) => <int>[]);
  void place(int i, int left) {
    rows[s.gen[i]].add(i);
    final k = kids(i);
    if (k.isEmpty) {
      x[i] = left + side(i) + 2;
      return;
    }
    var l = left + side(i);
    for (final c in k) {
      place(c, l);
      l += w[c];
    }
    x[i] = (x[k.first] + x[k.last]) ~/ 2;
  }

  var width = 0;
  for (final r in s.roots()) {
    measure(r);
    place(r, width);
    width += w[r];
  }
  return (x: x, w: w, width: width, rows: rows);
}

/// 접힘 32가지(정해진 씨앗) — 0번은 모두 펼침, 1번은 모두 접음, 나머지는 마디마다 섞음.
List<Uint8List> foldStates(KinSkeleton s) {
  final out = <Uint8List>[kinOpenAll(s), kinOpenNone(s)];
  var seed = 99;
  for (var k = 2; k < 32; k++) {
    final o = Uint8List(s.n);
    final rate = 40 + (k * 7) % 60; // 펼침 비율(%) 40~99
    for (var i = 0; i < s.n; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      o[i] = (seed >> 8) % 100 < rate ? 1 : 0;
    }
    out.add(o);
  }
  return out;
}

List<List<int>> rowsOf(KinLayout l) => [for (final r in l.rows) r.toList()];

/// 같은 세대에서 카드가 겹치지 않음(왼 → 오른으로 4u 이상 떨어짐) · 카드가 판 안 · 부모 카드가 제 자식 블록 위.
void expectNoOverlap(KinSkeleton s, KinLayout l) {
  for (final r in l.rows) {
    for (var k = 1; k < r.length; k++) {
      expect(l.x[r[k]] - l.x[r[k - 1]], greaterThanOrEqualTo(4), reason: '세대의 ${r[k - 1]} · ${r[k]}번 카드가 겹침');
    }
    for (final i in r) {
      expect(l.cardLeft(i), greaterThanOrEqualTo(0));
      expect(l.cardLeft(i) + kKinCardWidth, lessThanOrEqualTo(l.widthPx));
    }
  }
}

void main() {
  group('정수 칸 셈 — 손셈 견본', () {
    test('물빛 온씨 7명(설계 2-6 · 8-1) — 모두 펼침 · 기본 · 모두 접음', () {
      final s = kinFromMap(sampleOn);
      final all = kinLayout(s, kinOpenAll(s));
      expect(all.x, [7, 4, 4, 4, 2, 6, 10]);
      expect(all.w, [12, 8, 8, 8, 4, 4, 4]);
      expect(all.width, 12);
      expect(rowsOf(all), [
        [0],
        [1, 6],
        [2],
        [3],
        [4, 5],
      ]);
      expect(all.count, 7);
      expect(all.lastGen, 4);
      // px: 카드 왼쪽 = x·35 − 62, 위 = gen·82.
      expect(all.cardLeft(0), 7 * 35 - 62);
      expect(all.widthPx, 420);

      // 200명 이하라 기본 = 모두 펼침(목업 결정 2 A 그림과 같음).
      expect(kinDefaultOpen(s), kinOpenAll(s));

      final none = kinLayout(s, kinOpenNone(s));
      expect(none.x, [2, -1, -1, -1, -1, -1, -1]);
      expect(none.w, [4, 0, 0, 0, 0, 0, 0]);
      expect(none.width, 4);
      expect(rowsOf(none), [
        [0],
        [],
        [],
        [],
        [],
      ]);
      expect(none.lastGen, 0);

      // 바람대군파째 접음: 첫 임금 아래 바람대군 · 둘째 임금 두 카드.
      final folded = kinLayout(s, kinOpenAll(s)..[1] = 0);
      expect(folded.x.sublist(0, 2), [4, 2]);
      expect(folded.x[6], 6);
      expect(folded.width, 8);
    });

    test('옆구리 덧선 · 뿌리 둘 · 건너뛴 세대 11명', () {
      // 0 ─┬ 1 ─┬ 2        8 ─┬ 9(2대 건너뜀)
      //    │    └ 3           └ 10(옆구리)
      //    ├ 4(옆구리) ─┬ 5(옆구리)
      //    │            └ 6
      //    └ 7
      final s = kinFromNodes(
        [-1, 0, 1, 1, 0, 4, 4, 0, -1, 8, 8],
        [0, 1, 2, 2, 1, 2, 2, 1, 0, 2, 1],
        [1, 1, 1, 1, 9, 9, 1, 1, 1, 1, 9],
        edge: [0, 0, 0, 0, 1, 1, 0, 0, 0, 2, 1],
      );
      expect(s.size, [8, 3, 1, 1, 3, 1, 1, 1, 3, 1, 1]);
      final all = kinLayout(s, kinOpenAll(s));
      expect(all.x, [12, 4, 2, 6, 14, 12, 16, 20, 26, 24, 29]);
      expect(all.w, [22, 8, 4, 4, 10, 5, 4, 4, 9, 4, 5]);
      expect(all.width, 31);
      expect(rowsOf(all), [
        [0, 8],
        [1, 4, 7, 10],
        [2, 3, 5, 6, 9],
      ]);

      final none = kinLayout(s, kinOpenNone(s));
      expect(none.x, [2, -1, -1, -1, -1, -1, -1, -1, 6, -1, -1]);
      expect(none.width, 8);

      // 4번만 접음 — 옆구리 몫이 접힌 카드에도 남음.
      final part = kinLayout(s, kinOpenAll(s)..[4] = 0);
      expect(part.x, [9, 4, 2, 6, 11, -1, -1, 15, 21, 19, 24]);
      expect(part.w, [17, 8, 4, 4, 5, 0, 0, 4, 9, 4, 5]);
      expect(part.width, 26);
      expect(rowsOf(part), [
        [0, 8],
        [1, 4, 7, 10],
        [2, 3, 9],
      ]);
      for (final l in [all, none, part]) {
        expectNoOverlap(s, l);
      }
    });

    test('꼬투리는 펼침이어도 접힌 마디처럼 셈', () {
      final s = kinFromNodes([-1, 0, 0], [0, 1, 1], [1, 1 | kKinStub, 1], stubs: {1: const KinStub(key: 'kin:h-far', n: 40)});
      final l = kinLayout(s, kinOpenAll(s));
      expect(l.x, [4, 2, 6]);
      expect(l.width, 8);
      expect(kinShowsChildren(s, kinOpenAll(s), 1), isFalse);
    });
  });

  group('정수 칸 셈 — 재귀 대역과 접힘 32가지', () {
    for (final (name, s) in [
      ('합성 600명(뿌리 셋)', kinSynth(600, seed: 11)),
      ('합성 2천 명(꼬투리 · 뿌리 다섯)', kinSynth(2000, seed: 5, roots: 5, stubs: true)),
    ]) {
      test(name, () {
        final states = foldStates(s);
        expect(states.length, 32);
        for (var k = 0; k < states.length; k++) {
          final got = kinLayout(s, states[k]);
          final want = refLayout(s, states[k]);
          expect(got.x, want.x, reason: '접힘 $k번 x');
          expect(got.w, want.w, reason: '접힘 $k번 w');
          expect(got.width, want.width, reason: '접힘 $k번 width');
          expect(rowsOf(got), want.rows, reason: '접힘 $k번 rows');
          expectNoOverlap(s, got);
          // 같은 입력이면 같은 결과.
          final again = kinLayout(s, states[k]);
          expect(again.x, got.x);
        }
        // 모두 펼침 폭 = 잎마다 4 + 옆구리 몫의 합.
        var sum = 0;
        for (var i = 0; i < s.n; i++) {
          final leaf = s.size[i] == 1 || s.isStub(i);
          sum += (leaf ? 4 : 0) + (s.bits[i] & kKinSide != 0 ? 1 : 0);
        }
        expect(kinLayout(s, kinOpenAll(s)).width, sum);
      });
    }

    test('보이는 것 고르기 — 이분 탐색 = 하나씩 훑기', () {
      final s = kinSynth(800, seed: 3);
      final l = kinLayout(s, kinOpenAll(s));
      for (final (lo, hi) in [(0, 1920), (500, 1300), (3000, 3001), (-100, 50), (l.widthPx - 10, l.widthPx + 500)]) {
        for (var g = 0; g < s.gens; g++) {
          final r = l.rows[g];
          final want = [
            for (final i in r)
              if (l.cardLeft(i) + kKinCardWidth > lo && l.cardLeft(i) < hi) i,
          ];
          final got = l.visibleIn(g, lo, hi);
          expect(r.sublist(got.start, got.end).toList(), want, reason: '세대 $g · [$lo, $hi)');
        }
      }
      expect(l.visibleIn(-1, 0, 100), (start: 0, end: 0));
    });
  });

  group('기본 펼침 · 접힘 기억', () {
    test('200명 넘으면 지도자 · 조상 · 자녀 1대 · 파조 접힘', () {
      // 뿌리 0 아래 사슬 1 → 2(지도자) → 3, 그 옆 파조 4(지도자 아님) → 5, 그리고 잎 200개.
      final par = <int>[-1, 0, 1, 2, 0, 4];
      final gen = <int>[0, 1, 2, 3, 1, 2];
      final bits = <int>[1, 1, 1 | kKinLeader, 1, 1 | kKinFounder, 1];
      for (var i = 0; i < 200; i++) {
        par.add(5);
        gen.add(3);
        bits.add(1);
      }
      final s = kinFromNodes(par, gen, bits);
      final o = kinDefaultOpen(s);
      expect(o.sublist(0, 6), [1, 1, 1, 0, 0, 0]);
      final l = kinLayout(s, o);
      expect(rowsOf(l).sublist(0, 4), [
        [0],
        [1, 4],
        [2],
        [3],
      ]);
    });

    test('지도자 없는 큰 가문은 위 3세대까지', () {
      final s = kinSynth(500, seed: 21, roots: 1);
      final plain = kinFromNodes(
        s.par.toList(),
        s.gen.toList(),
        [for (final b in s.bits) b & ~kKinLeader],
      );
      final o = kinDefaultOpen(plain);
      final l = kinLayout(plain, o);
      for (var g = 0; g < plain.gens; g++) {
        for (final i in l.rows[g]) {
          expect(plain.gen[i], lessThanOrEqualTo(2 + 4), reason: '건너뛴 세대 말고는 3세대 안');
          if (plain.gen[i] >= 2) expect(o[i], 0);
          if (plain.bits[i] & kKinFounder != 0) expect(o[i], 0);
        }
      }
    });

    test('기억 — 기본과 다른 마디의 안정 열쇠만 · 되살리기', () {
      final s = kinSynth(300, seed: 4);
      final base = kinDefaultOpen(s);
      final open = Uint8List.fromList(base);
      kinToggle(s, open, 0);
      kinToggle(s, open, s.children(0).first, all: true);
      final diff = kinFoldDiff(s, open, base);
      final back = kinFoldApply(s, base, [...diff, 'f:test/없는 사람']);
      expect(kinLayout(s, back).x, kinLayout(s, open).x);
      for (final k in diff) {
        expect(s.size[s.indexOfKey(k)], greaterThan(1));
      }
      // 찾기 — 조상을 모두 펼치면 그 카드가 보임.
      final deep = s.n - 1;
      final shown = kinOpenTo(s, kinOpenNone(s), deep);
      expect(kinLayout(s, shown).rows[s.gen[deep]].contains(deep), isTrue);
      expect(kinOpenGenerations(s, 1).where((v) => v != 0).length, s.gen.where((g) => g < 1).length);
    });
  });

  group('승계표 줄', () {
    test('물빛 온씨 — 수준 넷(설계 2-6의 펼친 꼴)', () {
      final s = kinFromMap(sampleOn);
      final leaders = [KinLeaderSpot(s, 0), KinLeaderSpot(s, 6)];
      List<int> rowsAt(KinLevel level) => kinRows(leaders, kinLevelOpen(leaders, level)).toList();
      expect(rowsAt(KinLevel.leaders), [0, 0, 0, 0, 1, 0]);
      expect(rowsAt(KinLevel.children), [0, 0, 0, 1, 1, 1, 2, 1, 1, 0, 1, 0]);
      // 자녀까지(카드만 펼침)가 설계 2-6의 '바람대군 [바람대군파 · 5명 ▸] / → 2대 둘째 임금'.
      // 파 이름까지(웹 HT.successionOpen 규칙): 바깥 파조 바람대군이 안쪽 파조 솔군의 조상이라 펼쳐져 솔군파 이름 줄까지 보임.
      expect(rowsAt(KinLevel.branches), [0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 1, 1, 0, 1, 0]);
      expect(rowsAt(KinLevel.all), [0, 0, 0, 1, 1, 1, 1, 2, 2, 1, 3, 3, 1, 4, 4, 1, 5, 4, 2, 1, 1, 0, 1, 0]);
      expect(kinLevelOpen(leaders, KinLevel.branches)[s.key], [1, 1, 0, 0, 0, 0, 1]);
      // 빠진 뼈대 = 모두 접힘 · 카드 펼침 = 그 사람의 마디.
      expect(kinRows(leaders, const {}).toList(), [0, 0, 0, 0, 1, 0]);
      expect(kinRows(leaders, {s.key: Uint8List.fromList([1, 0, 0, 0, 0, 0, 0])}).toList(), [0, 0, 0, 1, 1, 1, 2, 1, 1, 0, 1, 0]);
      expect(kinLeaderReach(leaders, 0), 5);
      expect(kinLeaderReach(leaders, 1), 0);
      // 파조 알약의 사람 수 = 파조 포함 하위 수.
      expect(s.size[1], 5);
    });

    test('건너뛰기 · 복위 · 자리 없는 지도자 · 줄 높이', () {
      // 0 가 ─┬ 1 나 ─┬ 2 라
      //       │       └ 3 마
      //       └ 4 다 ── 5 바
      // 지도자: L0 가 · L1 나 · L2 가(복위) · L3 라 · L4 자리 없음.
      final s = kinFromNodes([-1, 0, 1, 1, 0, 4], [0, 1, 2, 2, 1, 2], [33, 33, 33, 1, 1, 1], names: ['가', '나', '라', '마', '다', '바']);
      final leaders = [KinLeaderSpot(s, 0), KinLeaderSpot(s, 1), KinLeaderSpot(s, 0), KinLeaderSpot(s, 2), const KinLeaderSpot.none()];
      final all = kinRows(leaders, {s.key: kinOpenAll(s)});
      expect(all.toList(), [0, 0, 0, 2, 1, 1, 1, 4, 1, 1, 5, 2, 0, 1, 0, 2, 3, 1, 1, 3, 1, 0, 2, 0, 0, 3, 0, 0, 4, 0]);
      expect(kinRowCount(all), 10);
      expect(kinFirstCards(leaders), [0, 1, 0, 3, 4]);
      expect([for (var m = 0; m < 5; m++) kinLeaderReach(leaders, m)], [2, 1, 0, 0, 0]);
      expect(kinRowTops(all, leaders.length), [0, 56, 84, 112, 140, 196, 224, 252, 308, 364, 398]);
      expect(kinRowIndent(3), 42);
      expect(kinRowIndent(11), 112);
      expect(kinRowDeeper(11), 3);
      expect(kinRowDeeper(8), 0);
      // 복위 카드(L2)는 펼쳐 있어도 줄을 내지 않음.
      final only2 = kinRows(leaders, {s.key: Uint8List.fromList([1, 0, 0, 0, 0, 0])});
      expect(only2.toList(), [0, 0, 0, 2, 1, 1, 1, 4, 1, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0, 4, 0]);
      // 자녀까지.
      final children = kinRows(leaders, kinLevelOpen(leaders, KinLevel.children));
      expect(children.toList(), [0, 0, 0, 2, 1, 1, 1, 4, 1, 0, 1, 0, 2, 3, 1, 1, 3, 1, 0, 2, 0, 0, 3, 0, 0, 4, 0]);
    });

    test('뼈대 둘에 걸친 정권 · 펼침은 뼈대마다', () {
      final on = kinFromMap(sampleOn);
      final other = kinFromNodes([-1, 0], [0, 1], [33, 1], uid: 'kin:polity:test/p');
      final leaders = [KinLeaderSpot(on, 0), KinLeaderSpot(other, 0)];
      final rows = kinRows(leaders, {on.key: kinOpenNone(on), other.key: kinOpenAll(other)});
      expect(rows.toList(), [0, 0, 0, 0, 1, 0, 1, 1, 1]);
      final lv = kinLevelOpen(leaders, KinLevel.children);
      expect(lv.keys.toSet(), {on.key, other.key});
    });

    test('합성 2천 명 — 한 사람 한 번 · 줄 수 ≤ 사람 + 지도자', () {
      final s = kinSynth(2000, seed: 17, roots: 2, stubs: true);
      final leaders = [
        for (var i = 0; i < s.n; i++)
          if (s.bits[i] & kKinLeader != 0) KinLeaderSpot(s, i),
      ];
      expect(leaders.length, greaterThan(10));
      for (final level in KinLevel.values) {
        final rows = kinRows(leaders, kinLevelOpen(leaders, level));
        final seen = <int>{};
        var leaderRows = 0;
        for (var r = 0; r < kinRowCount(rows); r++) {
          final kind = rows[r * 3], at = rows[r * 3 + 1], depth = rows[r * 3 + 2];
          if (kind == kKinRowLeader) {
            expect(at, leaderRows++);
          } else if (kind == kKinRowPerson) {
            expect(seen.add(at), isTrue, reason: '$level: $at번이 두 번');
            expect(s.bits[at] & kKinLeader, 0);
            expect(depth, greaterThan(0));
          } else {
            expect(kind, kKinRowSkip);
          }
        }
        expect(leaderRows, leaders.length);
        expect(kinRowCount(rows), lessThanOrEqualTo(s.n + leaders.length));
      }
    });
  });

  group('D1-E 정답 자리(있으면)', () {
    // KIN_FIXTURES=<폴더>면 그 폴더(저장소 밖에서 웹 도우미로 지은 정답)를 본다.
    final dir = Directory(Platform.environment['KIN_FIXTURES'] ?? 'test/fixtures');
    final files = dir.existsSync()
        ? (dir.listSync().whereType<File>().where((f) => RegExp(r'kin-golden-.*\.json$').hasMatch(f.path)).toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];
    test('정답 자리 ${files.length}개 — 세계표 자리 · 승계표 줄 정수 일치', () {
      if (files.isEmpty) {
        markTestSkipped('D1-E의 kin-golden-*.json이 아직 없음 — 결합 때 붙임');
        return;
      }
      final noPolity = <String>[];
      var checked = 0;
      for (final f in files) {
        final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final recs = [
          for (final r in jsonDecode(File('${dir.path}/${doc['records']}').readAsStringSync()) as List) (r as Map).cast<String, dynamic>(),
        ];
        final skels = <String, KinSkeleton>{
          for (final r in recs)
            if (r['kind'] == 'kin') r['uid'] as String: kinFromMap(jsonDecode(r['json'] as String) as Map<String, dynamic>, uid: r['uid'] as String),
        };
        var states = 0;
        for (final l in doc['layout'] as List) {
          final s = skels[l['uid']]!;
          for (final st in l['states'] as List) {
            final open = kinOpenAll(s);
            for (final c in st['closed'] as List) {
              open[c as int] = 0;
            }
            final got = kinLayout(s, open);
            final why = '${f.path} ${l['uid']} ${st['name']}';
            expect(got.x.toList(), st['x'], reason: '$why x');
            expect(got.w.toList(), st['w'], reason: '$why w');
            expect(rowsOf(got), st['rows'], reason: '$why rows');
            expect(got.width, st['width'], reason: '$why width');
            if (st['name'] == 'default') expect(open, kinDefaultOpen(s), reason: '$why 기본 펼침');
            states++;
          }
        }
        expect(states, greaterThan(0));
        // 승계표: 정권 기록의 x_lineage[leader:i].kinAt(한 벌 번호)으로 지도자 자리를 짓고 수준마다 줄을 견줌.
        for (final p in (doc['succession'] as List? ?? const [])) {
          // 정권 기록(x_lineage의 kinAt)이 기록 파일에 없으면 지도자 자리를 지을 수 없어 그 정권만 건너뜀(결합 때 본 것: D1-E 12728c0의
          // kin-family-1000.json에는 가문 · 뼈대 기록만 있고 정권 기록이 없음 — 넣으면 저절로 돎). 건너뛴 수는 아래에서 알림.
          final rec = recs.where((r) => r['uid'] == p['polity']).firstOrNull;
          if (rec == null) {
            noPolity.add('${f.uri.pathSegments.last} ${p['polity']}');
            continue;
          }
          checked++;
          final body = jsonDecode(rec['json'] as String) as Map<String, dynamic>;
          final lin = (body['x_lineage'] as Map? ?? const {}).cast<String, dynamic>();
          final count = (body['leaders'] as List? ?? const []).length;
          final leaders = <KinLeaderSpot>[
            for (var i = 0; i < count; i++)
              () {
                final ref = kinRefOf((lin['leader:$i'] as Map?)?['kinAt']);
                final s = ref == null ? null : skels[ref.key];
                if (ref == null || s == null) return const KinLeaderSpot.none();
                return KinLeaderSpot(s, s.locate(ref.at).at);
              }(),
          ];
          // 지도자 카드 끝 '후손 n'(웹 HT.successionReach — 정답 자료에 reach가 있을 때만).
          if (p['reach'] is List) {
            expect([for (var m = 0; m < leaders.length; m++) kinLeaderReach(leaders, m)], p['reach'], reason: '${f.path} ${p['polity']} 후손 n');
          }
          const levels = {'default': KinLevel.leaders, 'leaders': KinLevel.leaders, 'children': KinLevel.children, 'branches': KinLevel.branches, 'all': KinLevel.all};
          for (final st in p['states'] as List) {
            final why = '${f.path} ${p['polity']} ${st['name']}';
            // ㉠ 웹이 준 펼침 그대로로 줄 규칙만 견줌 — default는 null, 수준 넷은 HT.successionOpen의 { <뼈대 uid>: [0 · 1 …] }(W1 이음새 ⑥).
            final open = st['open'];
            final nodes = <String, Uint8List>{
              if (open is Map)
                for (final e in open.entries) '${e.key}': Uint8List.fromList([for (final b in e.value as List) b == true || (b is int && b != 0) ? 1 : 0]),
            };
            expect(kinRows(leaders, nodes).toList(), st['rows'], reason: '$why — 웹 펼침 그대로');
            // ㉡ 수준 → 펼침도 앱이 셈(KinLevel)해 같은 줄인지.
            final level = levels[st['name']];
            if (level == null) continue;
            expect(kinRows(leaders, kinLevelOpen(leaders, level)).toList(), st['rows'], reason: '$why — 앱 수준');
            if (open is Map) {
              final mine = kinLevelOpen(leaders, level);
              for (final e in open.entries) {
                expect(mine['${e.key}']?.toList(), e.value, reason: '$why — 수준 펼침 배열');
              }
            }
          }
        }
      }
      // 승계표 정답이 있는데 하나도 견주지 못하면 실패 — 정권 기록이 빠진 정권은 이름만 알림.
      if (noPolity.isNotEmpty) {
        // ignore: avoid_print
        print('승계표 정답 가운데 정권 기록이 없어 건너뜀 ${noPolity.length}: ${noPolity.join(', ')}');
      }
      final any = files.any((f) => ((jsonDecode(f.readAsStringSync()) as Map)['succession'] as List? ?? const []).isNotEmpty);
      if (any) expect(checked, greaterThan(0), reason: '승계표 정답을 하나도 견주지 못함');
    });
  });

  test('웹 대조용 내보내기(KIN_DUMP=<폴더>일 때만)', () {
    final out = Platform.environment['KIN_DUMP'];
    if (out == null || out.isEmpty) return;
    final samples = <String, KinSkeleton>{
      'on': kinFromMap(sampleOn),
      'side11': kinFromNodes(
        [-1, 0, 1, 1, 0, 4, 4, 0, -1, 8, 8],
        [0, 1, 2, 2, 1, 2, 2, 1, 0, 2, 1],
        [1, 1, 1, 1, 9, 9, 1, 1, 1, 1, 9],
        edge: [0, 0, 0, 0, 1, 1, 0, 0, 0, 2, 1],
      ),
      'synth600': kinSynth(600, seed: 11),
      'synth2000': kinSynth(2000, seed: 5, roots: 5, stubs: true),
      'big300': kinSynth(300, seed: 21, roots: 1),
    };
    for (final e in samples.entries) {
      final s = e.value;
      List<int> closedOf(Uint8List o) => [
        for (var i = 0; i < s.n; i++)
          if (o[i] == 0) i,
      ];
      final leaders = [
        for (var i = 0; i < s.n; i++)
          if (s.bits[i] & kKinLeader != 0) KinLeaderSpot(s, i),
      ];
      final doc = {
        'record': s.toRecord(),
        'default': closedOf(kinDefaultOpen(s)),
        'layout': [
          for (final o in [...foldStates(s), kinDefaultOpen(s)])
            () {
              final l = kinLayout(s, o);
              return {'closed': closedOf(o), 'x': l.x.toList(), 'w': l.w.toList(), 'rows': rowsOf(l), 'width': l.width};
            }(),
        ],
        'leaders': [for (final l in leaders) l.at],
        'succession': {
          for (final level in KinLevel.values)
            level.name: {
              'closed': closedOf(kinLevelOpen(leaders, level)[s.key] ?? kinOpenNone(s)),
              'rows': kinRows(leaders, kinLevelOpen(leaders, level)).toList(),
            },
        },
      };
      File('$out/kin-dart-${e.key}.json').writeAsStringSync(jsonEncode(doc));
    }
  });

  test('합성 5만 명 — 모두 펼친 자리 셈 시간(기록)', () {
    final s = kinSynth(50000, seed: 9, roots: 4);
    final open = kinOpenAll(s);
    double median(void Function(int k) work, {int rounds = 21}) {
      for (var k = 0; k < 5; k++) {
        work(k);
      }
      final t = <int>[];
      for (var k = 0; k < rounds; k++) {
        final w = Stopwatch()..start();
        work(k);
        t.add(w.elapsedMicroseconds);
      }
      t.sort();
      return t[t.length ~/ 2] / 1000;
    }

    // 모두 펼친 자리 셈 · 접기 1회(마디 하나를 접고 다시 셈 — 6-1 '접기 1회') · 보이는 것 고르기(1920px 한 화면 · 모든 세대).
    final ms = median((_) => kinLayout(s, open));
    final inner = [
      for (var i = 0; i < s.n; i++)
        if (s.size[i] > 50) i,
    ];
    final foldMs = median((k) {
      final i = inner[k % inner.length];
      open[i] = 0;
      kinLayout(s, open);
      open[i] = 1;
    });
    final l = kinLayout(s, open);
    final pickMs = median((k) {
      final lo = (k * 7919) % l.widthPx;
      for (var g = 0; g < s.gens; g++) {
        l.visibleIn(g, lo, lo + 1920);
      }
    });
    // ignore: avoid_print
    print('kin 5만: 접기 1회 ${foldMs.toStringAsFixed(2)}ms · 보이는 것 고르기 ${pickMs.toStringAsFixed(3)}ms(세대 ${s.gens}줄)');
    final leaders = [
      for (var i = 0; i < s.n; i++)
        if (s.bits[i] & kKinLeader != 0) KinLeaderSpot(s, i),
    ];
    final opened = kinLevelOpen(leaders, KinLevel.all);
    final rowsMs = median((_) => kinRowTops(kinRows(leaders, opened), leaders.length));
    final rows = kinRows(leaders, opened);
    final tops = kinRowTops(rows, leaders.length);
    // ignore: avoid_print
    print('kin 5만: 자리 셈 ${ms.toStringAsFixed(2)}ms · 승계표 줄 ${kinRowCount(rows)}개 ${rowsMs.toStringAsFixed(2)}ms · 높이 ${tops.last}px');
    expect(ms, lessThan(200));
  });
}

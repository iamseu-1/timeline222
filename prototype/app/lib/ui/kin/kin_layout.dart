import 'dart:typed_data';

import 'kin_record.dart';

// 세계표의 정수 칸 셈 — 계약(`docs/설계-10건/1-2-계승과-가문-확정.md` 4-4 · 웹 `HT.kinLayout`과 같은 셈) · 기본 펼침(4-5) · 접힘 기억 도우미.
//
// 웹과 앱이 같은 뼈대 위에서 이 정수 규칙 하나로 자리를 내므로 1배에서 1px까지 같다. 겹침 피하기 같은 판단은 없고
// 더하기 · 내림 나눗셈뿐이다(값이 음이 아니라 Dart `~/` = JS `Math.floor`). 규칙을 고칠 때는 계약 · 두 구현 · 정답 자료를 한 묶음으로 고친다.
//
//   side(i)  = (bits[i] & 8) ? 1 : 0                       // 옆구리로 들어오는 덧선
//   보이는 자식 = open[i]이 참일 때의 자식들(자식 차례 = 앞 차례) — 꼬투리(비트 128)는 접힌 마디처럼
//   w(i)     = 보이는 자식이 없으면 4 + side(i), 있으면 side(i) + Σ w(c)
//   left(뿌리 r) = 앞 뿌리들의 w 합,  left(cₖ) = left(i) + side(i) + Σ_{j<k} w(cⱼ)
//   x(i)     = 보이는 자식이 없으면 left(i) + side(i) + 2, 있으면 ⌊(x(첫 자식) + x(끝 자식)) / 2⌋
//   px:  카드 왼쪽 = x(i)·35 − 62,  카드 위 = gen[i]·82
//
// 비용은 O(보이는 마디)다 — 앞 차례로 돌며 접힌 하위는 `i += size[i]`로 건너뛴다.

/// 단위 u(1배 px).
const int kKinUnit = 35;

/// 칸 하나의 단위 수(4u = 140px — 카드 124 + 사이 16).
const int kKinCellUnits = 4;

/// 카드 크기(1배 px).
const int kKinCardWidth = 124;
const int kKinCardHeight = 42;

/// 카드 왼쪽 = x·35 − 62.
const int kKinCardHalf = 62;

/// 세대 줄 높이(카드 42 + 사이 40).
const int kKinRowHeight = 82;

/// 세계표의 보기 단계(건의 8의 4-가 · 2026-10-13 — 계약 4-4의 덧붙임): 자리 셈(정수 칸 x · 세대)은 그대로 두고 **칸의 px 크기만** 바꾼다.
/// 한 줄이 한 단계다 — 뒷날 '좁게'(u 23 · 카드 80×24 · 세대 줄 48)를 [levels]에 줄 하나로 더할 수 있다(이번에는 넣지 않음).
/// 사람의 왼쪽 = x·u − 폭 ÷ 2, 부모 → 자식 선이 꺾이는 높이 = 사람 아래 + (세대 줄 − 사람 높이) ÷ 2([elbow] — 사람 위에서 잰 값).
class KinScale {
  const KinScale(this.name, {required this.unit, required this.cardW, required this.cardH, required this.row, required this.radius, this.dots = false});

  /// 아래 줄 세그먼트에 적는 이름.
  final String name;

  /// 단위 u(1배 px).
  final int unit;

  /// 사람(카드 · 점)의 폭 · 높이 · 둥근 정도, 세대 줄 높이(1배 px).
  final double cardW, cardH, row, radius;

  /// 점으로 그리는 단계 — 이름 · 곁글 · 손잡이 · 알약 · 파 이름표 · 꼬리표 없이 점과 선만(이름은 풍선으로).
  final bool dots;

  /// 사람 폭의 반(정수 — 보이는 것 고르기의 이분 탐색이 쓴다).
  int get half => cardW ~/ 2;

  /// 부모 → 자식 선이 꺾이는 높이(사람 윗변에서).
  double get elbow => cardH + (row - cardH) / 2;

  /// 칸 [x]의 사람 왼쪽(1배 px).
  double left(int x) => (x * unit - half).toDouble();

  static const normal = KinScale('보통', unit: kKinUnit, cardW: 124, cardH: 42, row: 82, radius: 11);

  /// 점: 단위 6 · 지름 12 점 · 세대 줄 30.
  static const dot = KinScale('점', unit: 6, cardW: 12, cardH: 12, row: 30, radius: 6, dots: true);

  /// 고르는 차례(아래 줄 세그먼트 · V · Ctrl+휠이 이 차례로 오간다).
  static const levels = <KinScale>[normal, dot];
}

/// 기본 펼침에서 모두 펼치는 사람 수 상한(4-5 — 이하면 모두 펼침).
const int kKinOpenAllMax = 200;

/// 정수 칸 셈의 답. [x] · [w]는 단위 u(보이지 않는 마디는 x −1 · w 0), [rows]는 세대마다 보이는 번호(앞 차례 = 왼 → 오른), [width]는 모든 뿌리 w의 합.
class KinLayout {
  KinLayout({required this.x, required this.w, required this.rows, required this.width, required this.count});

  final Int32List x;
  final Int32List w;

  /// `rows[g]` — 세대 g의 보이는 마디 번호(길이 = 뼈대의 [KinSkeleton.gens]).
  final List<Int32List> rows;
  final int width;

  /// 보이는 마디 수.
  final int count;

  /// 카드 왼쪽(1배 px).
  int cardLeft(int i) => x[i] * kKinUnit - kKinCardHalf;

  /// 판 전체 폭(1배 px).
  int get widthPx => width * kKinUnit;

  /// 보이는 마디가 있는 가장 아래 세대(없으면 -1).
  int get lastGen {
    for (var g = rows.length - 1; g >= 0; g--) {
      if (rows[g].isNotEmpty) return g;
    }
    return -1;
  }

  /// 세대 [g]에서 카드가 px 구간 [lo, hi)에 걸치는 마디들 — `rows[g]` 안의 `[start, end)`. 이분 탐색 O(log n). px는 [scale]의 단계로.
  ({int start, int end}) visibleIn(int g, int lo, int hi, {KinScale scale = KinScale.normal}) {
    final unit = scale.unit, half = scale.half;
    if (g < 0 || g >= rows.length) return (start: 0, end: 0);
    final r = rows[g];
    // 카드 오른쪽(= x·35 + 62)이 lo보다 큰 첫 자리.
    var a = 0, b = r.length;
    while (a < b) {
      final mid = (a + b) >> 1;
      if (x[r[mid]] * unit + half > lo) {
        b = mid;
      } else {
        a = mid + 1;
      }
    }
    final start = a;
    // 카드 왼쪽이 hi 이상인 첫 자리.
    b = r.length;
    while (a < b) {
      final mid = (a + b) >> 1;
      if (x[r[mid]] * unit - half >= hi) {
        b = mid;
      } else {
        a = mid + 1;
      }
    }
    return (start: start, end: a);
  }
}

/// [open]의 [i]가 펼쳐져 보이는 자식을 내는가 — 펼침 · 자식 있음 · 꼬투리 아님.
bool kinShowsChildren(KinSkeleton s, Uint8List open, int i) => open[i] != 0 && s.size[i] > 1 && s.bits[i] & kKinStub == 0;

/// 보이는 마디 차례를 담는 작업 칸(한 isolate 안에서 되씀 — 셈마다 n 크기 배열을 새로 잡지 않게). 펼친 마디는 음수(−1 − i)로 적는다.
Int32List _scratch = Int32List(0);

/// 정수 칸 셈(4-4). [open]의 길이는 [KinSkeleton.n]이고 0이 아니면 펼침.
KinLayout kinLayout(KinSkeleton s, Uint8List open) {
  final n = s.n;
  final par = s.par, size = s.size, bits = s.bits, gen = s.gen;
  // 보이지 않는 마디는 x −1 · w 0(웹 HT.kinLayout과 같음 — 이음새 기록 D1-E ⑥).
  final x = Int32List(n)..fillRange(0, n, -1), w = Int32List(n);
  // ① 보이는 마디를 앞 차례로 모은다(접힌 하위는 건너뜀). 보이는 자식을 내는 마디는 −1 − i로 적어 둔다.
  if (_scratch.length < n) _scratch = Int32List(n);
  final vis = _scratch;
  var count = 0;
  for (var i = 0; i < n;) {
    if (open[i] != 0 && size[i] > 1 && bits[i] & kKinStub == 0) {
      vis[count++] = -1 - i;
      i++;
    } else {
      vis[count++] = i;
      i += size[i];
    }
  }
  // ② 거꾸로 돌며 w — 자식이 부모보다 뒤라, 부모의 w 칸에 자식 합을 먼저 쌓아 둔다. 세대마다 보이는 수도 센다.
  final perGen = Int32List(s.gens);
  for (var k = count - 1; k >= 0; k--) {
    final v = vis[k];
    final i = v < 0 ? -1 - v : v;
    final side = bits[i] & kKinSide != 0 ? 1 : 0;
    final wi = v < 0 ? side + w[i] : kKinCellUnits + side;
    w[i] = wi;
    final p = par[i];
    if (p >= 0) w[p] += wi;
    perGen[gen[i]]++;
  }
  // ③ 앞으로 돌며 left — 펼친 부모의 x 칸을 '다음 자식의 왼쪽' 자리로 잠시 쓰고(부모를 먼저 지나며 덮어씀), 잎은 곧바로 x를 낸다.
  //    세대 줄(앞 차례 = 왼 → 오른)도 채운다.
  final rows = [for (var g = 0; g < s.gens; g++) Int32List(perGen[g])];
  final fill = Int32List(s.gens);
  var width = 0;
  for (var k = 0; k < count; k++) {
    final v = vis[k];
    final i = v < 0 ? -1 - v : v;
    final p = par[i];
    int left;
    if (p < 0) {
      left = width;
      width += w[i];
    } else {
      left = x[p];
      x[p] += w[i];
    }
    final side = bits[i] & kKinSide != 0 ? 1 : 0;
    x[i] = v < 0 ? left + side : left + side + 2;
    final g = gen[i];
    rows[g][fill[g]++] = i;
  }
  // ④ 거꾸로 돌며 펼친 부모의 x — 첫 자식 i + 1, 끝 자식은 하위 구간의 끝에서 끝나는 자식.
  for (var k = count - 1; k >= 0; k--) {
    final v = vis[k];
    if (v >= 0) continue;
    final i = -1 - v, end = i + size[i];
    var c = i + 1;
    while (c + size[c] < end) {
      c += size[c];
    }
    x[i] = (x[i + 1] + x[c]) ~/ 2;
  }
  return KinLayout(x: x, w: w, rows: rows, width: width, count: count);
}

/// 모두 펼침.
Uint8List kinOpenAll(KinSkeleton s) => Uint8List(s.n)..fillRange(0, s.n, 1);

/// 모두 접음.
Uint8List kinOpenNone(KinSkeleton s) => Uint8List(s.n);

/// 세계표를 처음 열 때의 펼침(4-5 · 웹 `HT.kinDefaultOpen`과 같은 규칙).
/// - 사람이 [kKinOpenAllMax](200) 이하면 모두 펼침.
/// - 넘으면 지도자(비트 32)와 그 조상을 펼침 — 그래서 지도자 · 조상 · 지도자의 자녀 1대까지 보인다. 나머지는 접힘
///   (파조는 지도자이거나 지도자의 조상일 때만 펼쳐지고, 아니면 접혀 `○○파 · n명`으로 보임).
/// - 지도자가 없으면 위에서 3세대(세대 0 · 1 · 2)까지 보이게 세대 0 · 1을 펼침 — 파조는 접힘.
Uint8List kinDefaultOpen(KinSkeleton s) {
  final n = s.n;
  if (n <= kKinOpenAllMax) return kinOpenAll(s);
  final open = Uint8List(n);
  var leaders = false;
  for (var i = 0; i < n; i++) {
    if (s.bits[i] & kKinLeader == 0) continue;
    leaders = true;
    open[i] = 1;
    for (var p = s.par[i]; p >= 0 && open[p] == 0; p = s.par[p]) {
      open[p] = 1;
    }
  }
  if (leaders) return open;
  for (var i = 0; i < n; i++) {
    if (s.gen[i] < 2 && s.bits[i] & kKinFounder == 0) open[i] = 1;
  }
  return open;
}

/// [i]가 보이게 그 조상을 모두 펼친다(찾기 · '세계표에서 보기'). [open]을 고치고 돌려준다.
Uint8List kinOpenTo(KinSkeleton s, Uint8List open, int i) {
  for (var p = i >= 0 && i < s.n ? s.par[i] : -1; p >= 0; p = s.par[p]) {
    open[p] = 1;
  }
  return open;
}

/// 접고 펴기(누른 마디 하나). [all]이면 그 아래 모두를 같은 값으로(Alt+누름 · `*`). [open]을 고치고 돌려준다.
Uint8List kinToggle(KinSkeleton s, Uint8List open, int i, {bool all = false}) {
  final v = open[i] == 0 ? 1 : 0;
  if (all) {
    open.fillRange(i, i + s.size[i], v);
  } else {
    open[i] = v;
  }
  return open;
}

/// 세대 수준(`n세대까지`) — 세대 [upTo] 이하가 보이게(세대 < [upTo]인 마디를 펼침).
Uint8List kinOpenGenerations(KinSkeleton s, int upTo) {
  final open = Uint8List(s.n);
  for (var i = 0; i < s.n; i++) {
    if (s.gen[i] < upTo) open[i] = 1;
  }
  return open;
}

/// 접힘 기억(3-4 · 4-5 '기억') — [base](기본 펼침)와 다른 마디의 안정 열쇠. 꼬투리 · 자식 없는 마디는 남기지 않는다.
List<String> kinFoldDiff(KinSkeleton s, Uint8List open, Uint8List base) => [
  for (var i = 0; i < s.n; i++)
    if ((open[i] != 0) != (base[i] != 0) && s.size[i] > 1) s.keys[i],
];

/// 기억한 열쇠(기본과 다른 마디)를 [base]에 되살린 펼침. 없어진 열쇠는 조용히 건너뛴다.
Uint8List kinFoldApply(KinSkeleton s, Uint8List base, Iterable<String> diff) {
  final open = Uint8List.fromList(base);
  for (final k in diff) {
    final i = s.indexOfKey(k);
    if (i >= 0) open[i] = open[i] == 0 ? 1 : 0;
  }
  return open;
}

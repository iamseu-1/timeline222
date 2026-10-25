import 'dart:typed_data';

import 'kin_record.dart';

// 승계표의 줄 규칙 — 계약(`docs/설계-10건/1-2-계승과-가문-확정.md` 3-4 · 웹 `HT.successionRows`와 같은 규칙).
//
// 정권 P의 지도자를 시작 순으로 L₀ … Lₖ₋₁이라 할 때 위에서부터:
//  1. 지도자 줄 Lₘ(꼬리표 40 + 다음 꼬리표까지의 이음매 22 = 62, 끝 꼬리표는 40).
//  2. Lₘ이 펼쳐져 있고 그 사람의 뼈대 자리 s가 있으면 s의 하위 구간 (s, s + size[s])를 앞 차례로 훑는다. 마디 j마다
//     - j가 P의 다른 지도자의 사람이면 → 건너뛰기 줄 `→ n대 ○○` 하나를 두고 j의 하위를 건너뜀(j += size[j]).
//       '지도자의 사람'은 같은 뼈대의 마디로 가린다(그 지도자의 뼈대 자리가 이 뼈대의 j — 웹 successionInfo의 leaderAt과 같음).
//     - j가 접혀 있으면(꼬투리 포함) → 사람 줄 하나를 두고 하위를 건너뜀
//     - 그 밖이면 → 사람 줄을 두고 들어감
//  3. 같은 사람이 다시 오른 경우(복위)에는 처음 카드에서만 펼친다.
//  4. 사람 줄의 들여쓰기는 min(gen[j] − gen[s], 8) × 14px — 8대보다 깊으면 줄 머리에 `+n대`.
// 그래서 한 사람은 한 번만 나오고, 모두 펼친 줄 수는 사람 수 + 지도자 수를 넘지 않는다.
//
// 답은 `Int32List` — 줄마다 정수 셋 `[갈래, 번호, 깊이]`(이음새 기록 D1-N1):
//  - 갈래 [kKinRowLeader] 0: 번호 = 지도자 차례 m, 깊이 0
//  - 갈래 [kKinRowPerson] 1: 번호 = 그 카드 뼈대의 마디 j, 깊이 = gen[j] − gen[s](자르지 않은 값 — 들여쓰기는 [kinRowIndent])
//  - 갈래 [kKinRowSkip] 2: 번호 = 건너뛸 지도자의 **처음 카드** 차례 m′, 깊이 = gen[j] − gen[s]
// 사람 줄 · 건너뛰기 줄의 뼈대는 바로 위의 지도자 줄(그 카드의 [KinLeaderSpot.skel])이다.

/// 줄 갈래.
const int kKinRowLeader = 0;
const int kKinRowPerson = 1;
const int kKinRowSkip = 2;

/// 줄 높이(1배 px) — 지도자 꼬리표 40 · 이음매 22 · 사람 줄(건너뛰기 줄도) 28.
/// 리메이크 4단계 틀의 시트와 창 걸음 6(감독 고름 G5 #9 — 승계표를 서고로 다시 그림): 카드 34(둥근 10)가 그림판 꼬리표를 줄인 이름띠
/// (머리 24 + 흰 층 16 — `succession_look.dart`의 SuccLook.tag)로 바뀌어 40. 이음매 22는 열쇠표(바깥 상자 13 · 다음 꼬리표 윗변 1 위)가
/// 들고 위로 8이 남는 키라 그대로. 측정 대본(`lib/measure/scenarios.dart` — [kinRowTops])과 검사는 이 값으로 전체 높이를 셈한다.
const int kKinRowCard = 40;
const int kKinRowSeam = 22;
const int kKinRowLine = 28;

/// 들여쓰기 한 칸(px)과 자르는 깊이.
const int kKinIndentStep = 14;
const int kKinIndentMax = 8;

/// 승계표 수준(3-4 '바닥 단추') — 지도자만 · 자녀까지 · 파 이름까지 · 모두.
enum KinLevel { leaders, children, branches, all }

/// 지도자 칸 하나의 뼈대 자리 — [skel]의 [at]번(이 뼈대의 번호 — 기록 밖 한 벌 번호는 [KinSkeleton.locate]로 바꿈). 자리가 없으면 [skel] null · [at] -1.
class KinLeaderSpot {
  const KinLeaderSpot(this.skel, this.at);
  const KinLeaderSpot.none() : skel = null, at = -1;
  final KinSkeleton? skel;
  final int at;

  /// 이 자리의 사람(안정 열쇠) — 자리가 없으면 null.
  String? get person {
    final s = skel;
    return s == null || at < 0 || at >= s.n ? null : s.keys[at];
  }
}

/// 같은 사람의 처음 카드 — `first[m]` = m보다 앞에서 같은 사람이 처음 오른 카드(없으면 m). 뒤 카드의 알약 `← n대에서`.
Int32List kinFirstCards(List<KinLeaderSpot> leaders) {
  final first = Int32List(leaders.length);
  final seen = <String, int>{};
  for (var m = 0; m < leaders.length; m++) {
    final p = leaders[m].person;
    first[m] = p == null ? m : seen.putIfAbsent(p, () => m);
  }
  return first;
}

/// 정권 지도자의 색인 — 사람(안정 열쇠) → 처음 카드 차례, 뼈대 uid → (마디 번호 → 그 사람의 처음 카드 차례).
/// 건너뛰기 줄은 **같은 뼈대의 마디**로 가린다(웹 `successionInfo`의 `leaderAt`과 같음).
({Map<String, int> firstOf, Map<String, Map<int, int>> leaderAt}) _leaderIndex(List<KinLeaderSpot> leaders) {
  final firstOf = <String, int>{};
  final leaderAt = <String, Map<int, int>>{};
  for (var m = 0; m < leaders.length; m++) {
    final spot = leaders[m], p = spot.person;
    if (p == null) continue;
    final f = firstOf.putIfAbsent(p, () => m);
    leaderAt.putIfAbsent(spot.skel!.key, () => <int, int>{}).putIfAbsent(spot.at, () => f);
  }
  return (firstOf: firstOf, leaderAt: leaderAt);
}

/// 승계표 줄(3-4 · 웹 `HT.successionRows`와 같은 규칙 · 같은 꼴). [open]은 뼈대 열쇠([KinSkeleton.key]) → 펼침(마디마다 0 · 1 —
/// 웹 `HT.successionOpen`의 `{ <뼈대 uid>: [0 · 1 …] }`과 같은 꼴). 빠진 뼈대 · 마디는 접힘.
/// 지도자 카드 Lₘ의 펼침은 그 사람의 마디 `open[skel][at]`이다(카드와 사람 마디가 같은 칸 — 다시 오른 뒤 칸은 늘 접힘).
Int32List kinRows(List<KinLeaderSpot> leaders, Map<String, Uint8List> open) {
  final out = <int>[];
  final (:firstOf, :leaderAt) = _leaderIndex(leaders);
  for (var m = 0; m < leaders.length; m++) {
    out
      ..add(kKinRowLeader)
      ..add(m)
      ..add(0);
    final spot = leaders[m];
    final sk = spot.skel, s = spot.at;
    final p = spot.person;
    if (sk == null || p == null || firstOf[p] != m) continue;
    final o = open[sk.key];
    if (o == null || o[s] == 0 || sk.isStub(s)) continue;
    final end = s + sk.size[s];
    for (var j = s + 1; j < end;) {
      final d = sk.gen[j] - sk.gen[s];
      final other = leaderAt[sk.key]?[j];
      if (other != null) {
        out
          ..add(kKinRowSkip)
          ..add(other)
          ..add(d);
        j += sk.size[j];
        continue;
      }
      out
        ..add(kKinRowPerson)
        ..add(j)
        ..add(d);
      j += o[j] != 0 && !sk.isStub(j) ? 1 : sk.size[j];
    }
  }
  return Int32List.fromList(out);
}

/// 줄 수.
int kinRowCount(Int32List rows) => rows.length ~/ 3;

/// [r]번 줄의 높이 — 지도자 줄은 62(끝 꼬리표 40), 사람 줄 · 건너뛰기 줄은 28. [leaderCount]는 지도자 수(끝 카드 판정).
int kinRowExtent(Int32List rows, int r, int leaderCount) {
  if (rows[r * 3] != kKinRowLeader) return kKinRowLine;
  return rows[r * 3 + 1] == leaderCount - 1 ? kKinRowCard : kKinRowCard + kKinRowSeam;
}

/// 줄 위치의 누적합 — `tops[r]`은 [r]번 줄의 위(px), `tops[줄 수]`는 목록 전체 높이. O(줄 수).
Int32List kinRowTops(Int32List rows, int leaderCount) {
  final count = kinRowCount(rows);
  final tops = Int32List(count + 1);
  for (var r = 0; r < count; r++) {
    tops[r + 1] = tops[r] + kinRowExtent(rows, r, leaderCount);
  }
  return tops;
}

/// 깊이 → 들여쓰기(px) — min(깊이, 8) × 14.
int kinRowIndent(int depth) => (depth < kKinIndentMax ? depth : kKinIndentMax) * kKinIndentStep;

/// 깊이가 8대를 넘은 만큼(줄 머리의 `+n대` — 넘지 않으면 0).
int kinRowDeeper(int depth) => depth > kKinIndentMax ? depth - kKinIndentMax : 0;

/// 지도자 카드 끝 알약 `후손 n ▸`의 n — 그 카드의 펼침 구간에 드는 사람 수(건너뛰기 줄 · 다른 지도자의 하위는 셈하지 않음 —
/// 웹 `HT.successionReach`와 같음). 꼬투리는 그 덩어리의 사람 수([KinStub.n])로 센다(웹은 나누지 않아 꼬투리가 없음).
/// 처음 카드가 아니거나(복위) 자리가 없으면 0.
int kinLeaderReach(List<KinLeaderSpot> leaders, int m) {
  final spot = leaders[m];
  final sk = spot.skel, s = spot.at, p = spot.person;
  if (sk == null || p == null) return 0;
  final (:firstOf, :leaderAt) = _leaderIndex(leaders);
  if (firstOf[p] != m || sk.isStub(s)) return 0;
  final mine = leaderAt[sk.key] ?? const <int, int>{};
  var count = 0;
  final end = s + sk.size[s];
  for (var j = s + 1; j < end;) {
    if (mine.containsKey(j)) {
      j += sk.size[j];
      continue;
    }
    count += sk.isStub(j) ? (sk.stubs[j]?.n ?? 1) : 1;
    j++;
  }
  return count;
}

/// 수준 → 펼침(3-4 '바닥 단추' · 웹 `HT.successionOpen`과 같은 규칙 — W1 87069ca). 지도자 자리가 든 뼈대마다 하나씩.
/// - [KinLevel.leaders]: 모두 접음(처음 열 때와 같음 — 지도자만 보임)
/// - [KinLevel.children]: 처음 카드의 사람 마디만 펼침 — 자녀 줄까지 보임
/// - [KinLevel.branches]: 모든 파조(비트 16)의 조상과 지도자(비트 32)인 파조를 펼치고, 처음 카드의 마디도 펼침.
///   그 밖의 파조는 접힘 — 그래서 모든 파 이름(파 안의 파조도 — 바깥 파조가 그 조상이라 펼쳐짐) 줄까지 보임
/// - [KinLevel.all]: 모두 펼침
Map<String, Uint8List> kinLevelOpen(List<KinLeaderSpot> leaders, KinLevel level) {
  final out = <String, Uint8List>{};
  final firstOf = <String, int>{};
  for (var m = 0; m < leaders.length; m++) {
    final spot = leaders[m], sk = spot.skel, person = spot.person;
    if (sk == null || person == null) continue;
    final first = firstOf.putIfAbsent(person, () => m);
    final o = out.putIfAbsent(sk.key, () {
      final a = Uint8List(sk.n);
      if (level == KinLevel.all) a.fillRange(0, sk.n, 1);
      if (level == KinLevel.branches) {
        for (var j = 0; j < sk.n; j++) {
          if (sk.bits[j] & kKinFounder == 0) continue;
          if (sk.bits[j] & kKinLeader != 0) a[j] = 1;
          for (var q = sk.par[j]; q >= 0; q = sk.par[q]) {
            a[q] = 1;
          }
        }
      }
      return a;
    });
    if (level != KinLevel.leaders && first == m) o[spot.at] = 1;
  }
  return out;
}

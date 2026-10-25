import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

// 계보 뼈대 기록(항목 기록의 갈래 `kin` · 열 꼴 JSON) — 풀기 · 덩어리 합치기 · 안정 열쇠.
//
// 설계: `docs/설계-10건/1-2-계승과-가문-확정.md` 2-4 아(계보 뼈대) · 8-1(열 꼴 기록 · 덩어리 상한) · 8-3(조회 · 풀기) · 8-4(D1-N1).
// 이음새: 같은 문서 끝 '구현 이음새 기록'의 D1-E 절(기록 꼴 — 머리 `uid` · 열 `key` · 덩어리 · `extraFar`)과 D1-N1 절(이 파일의 이름 · 꼴).
//
// - 기록은 `{"op":"entity","uid":"kin:…"}` 답의 `json` 글이다. 창을 열 때 한 번만 받는다(8-3).
// - **풀기는 작업자 isolate에서만** 한다([decodeKin] — `Isolate.run`). 정수 열은 `Int32List`로 바꿔
//   `TransferableTypedData`로 넘기고, 글 열은 `List<String>` 그대로 넘긴다. 화면 쪽(UI isolate)은 JSON을 풀지 않는다.
//   `lib/ui/kin/`에서 JSON 풀기를 부르는 곳은 [_kinWork] 하나뿐이다(검사 `test/kin_record_test.dart`가 소스를 훑어 본다).
// - 앞 차례(선순) 번호 `i`는 자료가 바뀌면 밀린다. 접힘 기억 · 찾기는 안정 열쇠([KinSkeleton.keys])로 한다.
// - 나눈 덩어리(5만 명 상한)는 [mergeKin]으로 꼬투리 자리에 끼워 하나의 뼈대로 합친다. 모두 합치면 나누지 않은 한 벌과 같다(D1-E ③).
// - 기록 밖의 번호(`x_lineage[ref].kinAt` · 가문 `x_kin.at` · 파 표 `at`)는 **나누기 전 한 벌의 번호**다.
//   덩어리 일부만 받은 뼈대에서는 [KinSkeleton.locate]로 이 뼈대의 번호를 찾는다.

/// 비트(2-4 아) — 1 구성원 · 2 이름 미상 · 4 찾지 못함 · 8 옆구리 덧선 · 16 파조 · 32 지도자 · 64 계보 전용 · 128 꼬투리 · 256 두 나라.
const int kKinMember = 1;
const int kKinUnknown = 2;
const int kKinMissing = 4;
const int kKinSide = 8;
const int kKinFounder = 16;
const int kKinLeader = 32;
const int kKinLineageOnly = 64;
const int kKinStub = 128;
const int kKinTwoPolities = 256;

/// 나무 선 갈래(`edge`) — 0 실선 · 1 짧은 파선(나무 부모가 양부 · 양모) · 2 긴 파선(후손 — 몇 대 건너뜀). + 4는 옅게(추정 · 전승 70%).
const int kKinEdgeSolid = 0;
const int kKinEdgeAdopted = 1;
const int kKinEdgeSkip = 2;
const int kKinEdgeFaint = 4;

/// 선 갈래(0 · 1 · 2)만.
int kinEdgeKind(int edge) => edge & 3;

/// 추정 · 전승이라 옅게 그릴 선인가.
bool kinEdgeIsFaint(int edge) => edge & kKinEdgeFaint != 0;

/// 기록의 판(`v`). 이 판만 읽는다.
const int kKinRecordVersion = 1;

/// 기록 안의 정수 열 여덟(차례 고정 — D1-E ②).
const List<String> kKinIntColumns = ['par', 'size', 'gen', 'bits', 'edge', 'branch', 'color', 'color2'];

/// 파 표의 한 줄 — 가문 uid(`house:<id>`) · 이름 · 색 · 파조 번호(`at` — 한 벌 번호 · 못 풀면 -1) · 위 파 번호(`up` — 뿌리 -1).
class KinBranch {
  const KinBranch({required this.uid, required this.name, required this.color, required this.at, required this.up});
  final String uid;
  final String name;
  final String color;
  final int at;
  final int up;

  Map<String, Object?> toJson() => {'uid': uid, 'name': name, 'color': color, 'at': at, 'up': up};

  @override
  bool operator ==(Object other) =>
      other is KinBranch && other.uid == uid && other.name == name && other.color == color && other.at == at && other.up == up;

  @override
  int get hashCode => Object.hash(uid, name, color, at, up);

  @override
  String toString() => 'KinBranch($uid, $name, at $at, up $up)';
}

/// 꼬투리 — 다른 덩어리로 나뉜 하위 나무의 자리. [key]는 그 덩어리 기록의 uid, [n]은 한 벌에서 그 하위 나무의 사람 수(뿌리 포함 — `size[s]`).
class KinStub {
  const KinStub({required this.key, required this.n});
  final String key;
  final int n;

  @override
  bool operator ==(Object other) => other is KinStub && other.key == key && other.n == n;

  @override
  int get hashCode => Object.hash(key, n);

  @override
  String toString() => 'KinStub($key, $n)';
}

/// 덩어리 기록의 머리 `root` — 뿌리 뼈대 uid · 이 덩어리 0번의 한 벌 번호 · 꼬투리를 가진 기록 uid · 그 기록 안 꼬투리 번호.
class KinRoot {
  const KinRoot({required this.uid, required this.at, required this.up, required this.upAt});
  final String uid;
  final int at;
  final String up;
  final int upAt;

  Map<String, Object?> toJson() => {'uid': uid, 'at': at, 'up': up, 'upAt': upAt};

  @override
  bool operator ==(Object other) => other is KinRoot && other.uid == uid && other.at == at && other.up == up && other.upAt == upAt;

  @override
  int get hashCode => Object.hash(uid, at, up, upAt);
}

/// 끝이 다른 덩어리에 있는 덧선(덩어리 기록의 `extraFar` 한 줄) — 부모 안정 열쇠 · 부모의 한 벌 번호 · 이 기록 안 자식 번호 · 갈래 · gen.
class KinFarExtra {
  const KinFarExtra({required this.from, required this.fromAt, required this.to, required this.kind, required this.gen});
  final String from;
  final int fromAt;
  final int to;
  final int kind;
  final int gen;

  KinFarExtra moved(int to) => KinFarExtra(from: from, fromAt: fromAt, to: to, kind: kind, gen: gen);

  Map<String, Object?> toJson() => {'from': from, 'fromAt': fromAt, 'to': to, 'kind': kind, 'gen': gen};

  @override
  bool operator ==(Object other) =>
      other is KinFarExtra && other.from == from && other.fromAt == fromAt && other.to == to && other.kind == kind && other.gen == gen;

  @override
  int get hashCode => Object.hash(from, fromAt, to, kind, gen);
}

/// [KinSkeleton.locate]의 답 — 이 뼈대의 번호([at] — 없으면 -1)와, 그 사람이 아직 받지 않은 덩어리 안이면 그 꼬투리 번호([stub] — 아니면 -1).
typedef KinSpot = ({int at, int stub});

/// 계보 뼈대 한 벌(열 꼴 기록을 푼 것). 모든 열의 길이는 [n]이고 번호는 앞 차례(선순)다.
///
/// - [par] 나무 부모(뿌리 -1) · [size] 자기 포함 하위 수 · [gen] 세대 줄 · [bits] 비트 · [edge] 나무 선 갈래
/// - [branch] 파 번호([branches]) · [color] · [color2] 색 번호([colors] — 0 = 종이빛, [color2]는 두 나라일 때만 0이 아님)
/// - [name] · [sub] 곁글 · [keys] 안정 열쇠(기록의 열 `key`)
/// - [extra] 덧선 `[from, to, 갈래, gen]`을 평평하게 늘어놓은 정수 줄(길이 4 × m · 차례 `(to, from, 갈래, gen)` 오름)
/// - [cells] 칸 열쇠 → 번호 · [stubs] 꼬투리 번호 → 덩어리 · [warnings]
/// - 덩어리 기록만: [root] · [extraFar]
class KinSkeleton {
  KinSkeleton({
    required this.key,
    required this.n,
    required this.gens,
    required this.par,
    required this.size,
    required this.gen,
    required this.bits,
    required this.edge,
    required this.branch,
    required this.color,
    required this.color2,
    required this.name,
    required this.sub,
    required this.keys,
    required this.extra,
    required this.colors,
    required this.branches,
    required this.cells,
    required this.stubs,
    required this.warnings,
    this.root,
    this.extraFar = const [],
  });

  /// 기록 uid(머리 `uid` — `kin:<뿌리 가문 id>` · `kin:polity:<정권 uid>` · 덩어리 `kin:<파 가문 id>` · `<뿌리 uid>#<안정 열쇠>`).
  final String key;
  final int n;

  /// 세대 줄 수(가장 큰 `gen` + 1).
  final int gens;
  final Int32List par, size, gen, bits, edge, branch, color, color2;
  final List<String> name, sub, keys;
  final Int32List extra;
  final List<String> colors;
  final List<KinBranch> branches;
  final Map<String, int> cells;
  final Map<int, KinStub> stubs;
  final List<String> warnings;
  final KinRoot? root;
  final List<KinFarExtra> extraFar;

  Map<String, int>? _byKey;
  Int32List? _full;

  /// 안정 열쇠 → 앞 차례 번호(없으면 -1). 처음 부를 때 한 번 표를 짓는다.
  int indexOfKey(String k) => (_byKey ??= {for (var i = 0; i < n; i++) keys[i]: i})[k] ?? -1;

  /// 다른 덩어리로 나뉜 꼬투리인가(접힌 마디처럼 센다 — 4-4).
  bool isStub(int i) => bits[i] & kKinStub != 0;

  /// 이 뼈대 안에 자식이 있는가(꼬투리는 덩어리를 받기 전까지 자식이 없다).
  bool hasChildren(int i) => size[i] > 1;

  /// 다음 형제(또는 하위 나무 끝) — `i + size[i]`.
  int next(int i) => i + size[i];

  /// 나무 자식들(앞 차례 = 자식 차례) — O(자식 수).
  Iterable<int> children(int i) sync* {
    final end = i + size[i];
    for (var j = i + 1; j < end; j += size[j]) {
      yield j;
    }
  }

  /// 뿌리들(나무 부모가 없는 마디) — 앞 차례.
  Iterable<int> roots() sync* {
    for (var j = 0; j < n; j += size[j]) {
      yield j;
    }
  }

  /// 덧선 수.
  int get extraCount => extra.length ~/ 4;

  /// 이 뼈대 [i]번의 한 벌 번호(나누기 전 앞 차례 번호). 덩어리를 다 받은 뼈대면 [i] 그대로다.
  int fullIndexOf(int i) => _fullTable()[i];

  /// 한 벌 번호 [full]의 사람이 이 뼈대 어디에 있는지(D1-E ① `kinAt` · ④ `x_kin.at`을 이 뼈대 번호로).
  /// - 이 뼈대의 마디면 `(at: 번호, stub: -1)` — 꼬투리 카드 자신도 그 사람이다.
  /// - 아직 받지 않은 덩어리 안이면 `(at: -1, stub: 그 꼬투리 번호)` — [KinStub.key]를 받아 [mergeKin]한 뒤 다시 찾는다.
  /// - 이 뼈대 범위 밖이면 `(at: -1, stub: -1)`.
  KinSpot locate(int full) {
    final t = _fullTable();
    if (n == 0 || full < t[0]) return (at: -1, stub: -1);
    // 한 벌 번호는 앞 차례로 늘어나므로 이분 탐색 — t[i] ≤ full인 가장 큰 i.
    var lo = 0, hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (t[mid] <= full) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    if (t[lo] == full) return (at: lo, stub: -1);
    if (isStub(lo)) {
      final s = stubs[lo];
      if (s != null && full < t[lo] + s.n) return (at: -1, stub: lo);
    }
    return (at: -1, stub: -1);
  }

  Int32List _fullTable() {
    final had = _full;
    if (had != null) return had;
    final t = Int32List(n);
    var at = root?.at ?? 0;
    for (var i = 0; i < n; i++) {
      t[i] = at;
      at += isStub(i) ? (stubs[i]?.n ?? 1) : 1;
    }
    return _full = t;
  }

  /// 열 꼴 기록(8-1 · D1-E ②)으로 되돌린다 — 열쇠 차례 고정. 덩어리를 모두 합친 뼈대는 나누지 않은 한 벌의 기록과 같은 글이 된다.
  Map<String, Object?> toRecord() {
    // color2는 0이 아닌 값이 하나라도 있을 때만 길이 n으로(D1-E ② · export/kin.mjs와 같음).
    var two = false;
    for (var i = 0; i < n && !two; i++) {
      two = color2[i] != 0;
    }
    final stubKeys = stubs.keys.toList()..sort();
    return {
      'v': kKinRecordVersion,
      'uid': key,
      'n': n,
      'gens': gens,
      'par': par.toList(),
      'size': size.toList(),
      'gen': gen.toList(),
      'bits': bits.toList(),
      'edge': edge.toList(),
      'branch': branch.toList(),
      'color': color.toList(),
      'color2': two ? color2.toList() : <int>[],
      'name': List<String>.of(name),
      'sub': List<String>.of(sub),
      'key': List<String>.of(keys),
      'extra': extra.toList(),
      'colors': List<String>.of(colors),
      'branches': [for (final b in branches) b.toJson()],
      'cells': Map<String, int>.of(cells),
      'stubs': {
        for (final k in stubKeys) '$k': {'key': stubs[k]!.key, 'n': stubs[k]!.n},
      },
      'warnings': List<String>.of(warnings),
      if (root != null) 'root': root!.toJson(),
      if (extraFar.isNotEmpty) 'extraFar': [for (final e in extraFar) e.toJson()],
    };
  }
}

/// 이미 풀린 맵(검사가 `jsonDecode`로 푼 것 · 작업자 안)에서 뼈대를 짓는다. 꼴이 어긋나면 [FormatException].
///
/// 기록 uid는 머리 `uid`(D1-E ②) → 머리 `key`가 글이면 그것(8-1 초안) → [uid](부른 쪽이 아는 조회 uid) 차례로 정한다.
/// 안정 열쇠 열은 `key`(목록)이고, 없으면 `keys`도 받는다. 기록이 `{"kin": {...}}`처럼 한 겹 싸여 있으면 그 안을 읽는다.
KinSkeleton kinFromMap(Map<String, dynamic> raw, {String uid = ''}) {
  var m = raw;
  if (m['par'] == null && m['kin'] is Map) m = (m['kin'] as Map).cast<String, dynamic>();
  final v = m['v'];
  if (v is! int || v != kKinRecordVersion) throw FormatException('계보 뼈대 기록의 판을 읽지 못했습니다: $v');
  final n = _int(m['n'], 'n');
  final cols = <String, Int32List>{};
  for (final c in kKinIntColumns) {
    final list = m[c];
    if (c == 'color2' && (list == null || (list is List && list.isEmpty))) {
      cols[c] = Int32List(n);
      continue;
    }
    if (list is! List || list.length != n) throw FormatException('계보 뼈대 열 `$c`의 길이가 $n이 아닙니다');
    cols[c] = _ints(list, c);
  }
  final head = m['key'];
  final keyCol = head is List ? head : m['keys'];
  final id = m['uid'] is String ? m['uid'] as String : (head is String ? head : uid);
  final names = _strs(m['name'], n, 'name');
  final subs = m['sub'] == null ? List<String>.filled(n, '') : _strs(m['sub'], n, 'sub');
  final keys = keyCol == null ? List<String>.generate(n, (i) => '#$i') : _strs(keyCol, n, 'key');
  final extraRaw = m['extra'] ?? const [];
  if (extraRaw is! List || extraRaw.length % 4 != 0) throw const FormatException('계보 뼈대의 덧선 줄은 넷씩이어야 합니다');
  final extra = _ints(extraRaw, 'extra');
  for (var e = 0; e < extra.length; e += 4) {
    if (extra[e] < 0 || extra[e] >= n || extra[e + 1] < 0 || extra[e + 1] >= n) {
      throw FormatException('계보 뼈대의 덧선 ${e ~/ 4}번이 범위 밖입니다');
    }
  }
  final colors = m['colors'] == null ? <String>[''] : _strs(m['colors'], -1, 'colors');
  final branches = <KinBranch>[
    for (final b in (m['branches'] as List? ?? const []))
      if (b is Map)
        KinBranch(
          uid: '${b['uid'] ?? ''}',
          name: '${b['name'] ?? ''}',
          color: '${b['color'] ?? ''}',
          at: b['at'] is int ? b['at'] as int : -1,
          up: b['up'] is int ? b['up'] as int : -1,
        ),
  ];
  final cells = <String, int>{};
  final cellsRaw = m['cells'];
  if (cellsRaw is Map) {
    cellsRaw.forEach((k, v) {
      if (v is int && v >= 0 && v < n) cells['$k'] = v;
    });
  }
  final stubs = <int, KinStub>{};
  final stubsRaw = m['stubs'];
  if (stubsRaw is Map) {
    stubsRaw.forEach((k, v) {
      final i = int.tryParse('$k');
      if (i != null && i >= 0 && i < n && v is Map) stubs[i] = KinStub(key: '${v['key'] ?? ''}', n: v['n'] is int ? v['n'] as int : 1);
    });
  }
  final warnings = [for (final w in (m['warnings'] as List? ?? const [])) '$w'];
  final r = m['root'];
  final root = r is Map
      ? KinRoot(
          uid: '${r['uid'] ?? ''}',
          at: r['at'] is int ? r['at'] as int : 0,
          up: '${r['up'] ?? ''}',
          upAt: r['upAt'] is int ? r['upAt'] as int : -1,
        )
      : null;
  final far = <KinFarExtra>[
    for (final e in (m['extraFar'] as List? ?? const []))
      if (e is Map && e['to'] is int && (e['to'] as int) >= 0 && (e['to'] as int) < n)
        KinFarExtra(
          from: '${e['from'] ?? ''}',
          fromAt: e['fromAt'] is int ? e['fromAt'] as int : -1,
          to: e['to'] as int,
          kind: e['kind'] is int ? e['kind'] as int : 0,
          gen: e['gen'] is int ? e['gen'] as int : 0,
        ),
  ];
  final skel = KinSkeleton(
    key: id,
    n: n,
    gens: m['gens'] is int ? m['gens'] as int : _gensOf(cols['gen']!),
    par: cols['par']!,
    size: cols['size']!,
    gen: cols['gen']!,
    bits: cols['bits']!,
    edge: cols['edge']!,
    branch: cols['branch']!,
    color: cols['color']!,
    color2: cols['color2']!,
    name: names,
    sub: subs,
    keys: keys,
    extra: extra,
    colors: colors,
    branches: branches,
    cells: cells,
    stubs: stubs,
    warnings: warnings,
    root: root,
    extraFar: far,
  );
  kinCheck(skel);
  return skel;
}

/// 나무 꼴을 확인한다 — 앞 차례 · 하위 수 · 세대가 어긋나면 [FormatException](자리 셈이 끝없이 돌거나 범위를 넘지 않게). O(n).
void kinCheck(KinSkeleton s) {
  final n = s.n;
  // 열린 하위 구간의 주인을 쌓아 두고, 각 마디의 나무 부모가 바로 그 주인인지 본다.
  final stack = <int>[];
  for (var i = 0; i < n; i++) {
    while (stack.isNotEmpty && i >= stack.last + s.size[stack.last]) {
      stack.removeLast();
    }
    final want = stack.isEmpty ? -1 : stack.last;
    if (s.par[i] != want) throw FormatException('계보 뼈대 $i번의 나무 부모가 앞 차례와 맞지 않습니다');
    final sz = s.size[i];
    if (sz < 1 || i + sz > n || (want >= 0 && i + sz > want + s.size[want])) {
      throw FormatException('계보 뼈대 $i번의 하위 수가 맞지 않습니다');
    }
    if (s.gen[i] < 0 || (want >= 0 && s.gen[i] <= s.gen[want])) throw FormatException('계보 뼈대 $i번의 세대가 맞지 않습니다');
    if (s.gen[i] >= s.gens) throw FormatException('계보 뼈대 $i번의 세대가 세대 줄 수를 넘습니다');
    if (s.isStub(i) && sz != 1) throw FormatException('계보 뼈대 $i번 꼬투리에 하위가 있습니다');
    stack.add(i);
  }
}

int _gensOf(Int32List gen) {
  var g = -1;
  for (final v in gen) {
    if (v > g) g = v;
  }
  return g + 1;
}

int _int(Object? v, String what) {
  if (v is int && v >= 0) return v;
  throw FormatException('계보 뼈대 기록의 `$what`이 음이 아닌 정수가 아닙니다');
}

Int32List _ints(List list, String what) {
  final out = Int32List(list.length);
  for (var i = 0; i < list.length; i++) {
    final v = list[i];
    if (v is! int) throw FormatException('계보 뼈대 열 `$what`의 $i번이 정수가 아닙니다');
    out[i] = v;
  }
  return out;
}

List<String> _strs(Object? v, int n, String what) {
  if (v is! List || (n >= 0 && v.length != n)) throw FormatException('계보 뼈대 열 `$what`의 길이가 맞지 않습니다');
  return List<String>.generate(v.length, (i) => v[i] is String ? v[i] as String : '${v[i] ?? ''}', growable: false);
}

// ── 작업자 isolate 풀기 ─────────────────────────────────────────────────────────

/// 기록 글(`entity` 답의 `json`)을 **작업자 isolate에서** 풀어 뼈대를 돌려준다(8-3). 꼴이 어긋나면 [FormatException]으로 끝난다.
///
/// 정수 열은 작업자에서 `Int32List`로 바꿔 `TransferableTypedData`로 넘기므로 화면 쪽은 바이트를 복사하지 않고 받는다.
/// [uid]는 조회한 기록 uid — 기록 안에 uid 글이 없을 때 뼈대 열쇠로 쓴다.
Future<KinSkeleton> decodeKin(String json, {String uid = ''}) async {
  final wire = await Isolate.run(() => _kinWork(json, uid), debugName: 'kin-decode');
  return wire.materialize();
}

/// 작업자 안에서만 도는 일 — JSON을 풀고 열을 정수 배열로 바꾼다. `lib/ui/kin/`에서 JSON 풀기는 여기서만 부른다.
_KinWire _kinWork(String json, String uid) {
  final raw = jsonDecode(json);
  if (raw is! Map) throw const FormatException('계보 뼈대 기록이 객체가 아닙니다');
  return _KinWire.of(kinFromMap(raw.cast<String, dynamic>(), uid: uid));
}

/// isolate 사이를 건너는 꼴 — 정수 열은 [TransferableTypedData], 나머지는 그대로.
class _KinWire {
  _KinWire.of(KinSkeleton s)
    : key = s.key,
      n = s.n,
      gens = s.gens,
      ints = [
        for (final c in [s.par, s.size, s.gen, s.bits, s.edge, s.branch, s.color, s.color2, s.extra]) TransferableTypedData.fromList([c]),
      ],
      name = s.name,
      sub = s.sub,
      keys = s.keys,
      colors = s.colors,
      branches = s.branches,
      cells = s.cells,
      stubs = s.stubs,
      warnings = s.warnings,
      root = s.root,
      extraFar = s.extraFar;

  final String key;
  final int n, gens;
  final List<TransferableTypedData> ints;
  final List<String> name, sub, keys, colors, warnings;
  final List<KinBranch> branches;
  final Map<String, int> cells;
  final Map<int, KinStub> stubs;
  final KinRoot? root;
  final List<KinFarExtra> extraFar;

  KinSkeleton materialize() {
    final c = [for (final t in ints) t.materialize().asInt32List()];
    return KinSkeleton(
      key: key,
      n: n,
      gens: gens,
      par: c[0],
      size: c[1],
      gen: c[2],
      bits: c[3],
      edge: c[4],
      branch: c[5],
      color: c[6],
      color2: c[7],
      name: name,
      sub: sub,
      keys: keys,
      extra: c[8],
      colors: colors,
      branches: branches,
      cells: cells,
      stubs: stubs,
      warnings: warnings,
      root: root,
      extraFar: extraFar,
    );
  }
}

// ── 기록 밖의 뼈대 자리 ───────────────────────────────────────────────────────

/// 엔티티 기록의 뼈대 자리를 읽는다 — 정권 `x_lineage[ref].kinAt`(`[뼈대 uid, 한 벌 번호]` — D1-E ①) ·
/// 가문 · 인물 `x_kin`(`{ key, at?, chunk? }` — D1-E ④ ⑤). 번호가 없으면 `at`은 -1(가문의 뿌리 세계표).
({String key, int at})? kinRefOf(Object? v) {
  if (v is List && v.length >= 2 && v[0] is String && v[1] is int) return (key: v[0] as String, at: v[1] as int);
  if (v is Map && v['key'] is String) return (key: v['key'] as String, at: v['at'] is int ? v['at'] as int : -1);
  return null;
}

/// 한 벌 번호 [full]의 사람이 든 덩어리를 차례로 받아 합친다 — 그 사람이 [skel]의 마디가 될 때까지.
/// [fetch]는 덩어리 uid로 기록 글을 받는 함수(보통 `entity` 조회). 풀기는 [decodeKin](작업자 isolate)이다.
/// 답은 `(skel: 합친 뼈대, at: 그 사람의 번호 — 못 찾으면 -1)`.
Future<({KinSkeleton skel, int at})> kinReveal(KinSkeleton skel, int full, Future<String?> Function(String uid) fetch) async {
  var s = skel;
  for (var guard = 0; guard < 64; guard++) {
    final spot = s.locate(full);
    if (spot.at >= 0 || spot.stub < 0) return (skel: s, at: spot.at);
    final uid = s.stubs[spot.stub]!.key;
    final text = await fetch(uid);
    if (text == null || text.isEmpty) return (skel: s, at: -1);
    final merged = mergeKin(s, await decodeKin(text, uid: uid));
    if (identical(merged, s)) return (skel: s, at: -1);
    s = merged;
  }
  return (skel: s, at: -1);
}

// ── 덩어리 합치기 ─────────────────────────────────────────────────────────────

/// [main]의 꼬투리 자리에 덩어리 [chunk]를 끼워 하나의 뼈대로 합친다(8-3 · D1-E ③ 합치기). [main] · [chunk]는 바꾸지 않는다.
///
/// - 꼬투리 `t`는 [main]의 `stubs`에서 덩어리 uid가 [chunk]의 uid인 것(없으면 덩어리 0번의 안정 열쇠로 찾음).
/// - 덩어리의 마디 0…m−1을 `t` 자리에 앞 차례 그대로 끼운다(원래 `t` 뒤 마디는 m−1만큼 밀림). `t`의 조상 `size` += m−1,
///   덩어리 0번의 나무 부모 = 꼬투리의 부모, 비트는 덩어리 쪽(128 없음). 세대는 한 벌 값 그대로(D1-E — 절대 세대)지만,
///   덩어리가 0세대부터 적었어도 맞도록 `gen[t] − chunk.gen[0]`만큼 옮긴다.
/// - 색 · 파 표는 모든 덩어리에 같은 한 벌 표다(D1-E). 다르면 글 · uid로 맞춰 [main]의 표에 이어 붙인다. 파조 번호 `at`은 한 벌 번호라 고치지 않는다.
/// - `cells` · `stubs` · `extra` 번호를 옮기고, 두 끝이 다 들어온 `extraFar`는 `extra`로 옮겨 `(to, from, 갈래, gen)` 차례로 다시 맞춘다.
///   `cells`는 `(번호, 칸 열쇠)` 오름으로 다시 늘어놓는다(D1-E ② — 한 벌과 같은 차례).
/// - 남은 `extraFar`는 `(to, fromAt, 갈래, gen)` 오름, 나누기가 덧붙인 `덩어리 …` 경고는 뺀다(export/kin.mjs `joinKin`과 같음).
/// - `n` · `gens`는 다시 센다. [main]이 덩어리 기록이면 그 `root`는 그대로 둔다.
/// 꼬투리를 찾지 못하면(이미 합쳤거나 다른 뼈대) [main]을 그대로 돌려준다.
KinSkeleton mergeKin(KinSkeleton main, KinSkeleton chunk) {
  var t = -1;
  for (final e in main.stubs.entries) {
    if (e.value.key == chunk.key && main.isStub(e.key)) t = e.key;
  }
  if (t < 0 && chunk.n > 0) {
    final i = main.indexOfKey(chunk.keys[0]);
    if (i >= 0 && main.isStub(i)) t = i;
  }
  if (t < 0 || chunk.n == 0) return main;
  final m = chunk.n, d = m - 1, n = main.n + d;
  int mapMain(int i) => i < t ? i : (i == t ? t : i + d);
  int mapChunk(int i) => i + t;

  // 색 · 파 표 — 같은 표면 번호도 같다. 다르면 글 · uid로 맞춘다.
  final colors = List<String>.of(main.colors);
  final colorIx = <String, int>{};
  for (var i = 0; i < colors.length; i++) {
    colorIx.putIfAbsent(colors[i], () => i);
  }
  final chunkColor = Int32List(chunk.colors.length);
  for (var i = 0; i < chunk.colors.length; i++) {
    if (i < main.colors.length && main.colors[i] == chunk.colors[i]) {
      chunkColor[i] = i;
      continue;
    }
    chunkColor[i] = colorIx.putIfAbsent(chunk.colors[i], () {
      colors.add(chunk.colors[i]);
      return colors.length - 1;
    });
  }
  final branches = List<KinBranch>.of(main.branches);
  final branchIx = <String, int>{};
  for (var i = 0; i < branches.length; i++) {
    branchIx.putIfAbsent(branches[i].uid, () => i);
  }
  final chunkBranch = Int32List(chunk.branches.length);
  final added = <int>[];
  for (var i = 0; i < chunk.branches.length; i++) {
    final b = chunk.branches[i];
    if (i < main.branches.length && main.branches[i].uid == b.uid) {
      chunkBranch[i] = i;
      continue;
    }
    final had = branchIx[b.uid];
    if (had != null) {
      chunkBranch[i] = had;
    } else {
      branches.add(b);
      branchIx[b.uid] = branches.length - 1;
      chunkBranch[i] = branches.length - 1;
      added.add(i);
    }
  }
  for (final i in added) {
    final up = chunk.branches[i].up;
    final b = chunk.branches[i];
    branches[chunkBranch[i]] = KinBranch(
      uid: b.uid,
      name: b.name,
      color: b.color,
      at: b.at,
      up: up < 0 || up >= chunkBranch.length ? -1 : chunkBranch[up],
    );
  }

  final par = Int32List(n), size = Int32List(n), gen = Int32List(n), bits = Int32List(n), edge = Int32List(n);
  final branch = Int32List(n), color = Int32List(n), color2 = Int32List(n);
  final name = List<String>.filled(n, ''), sub = List<String>.filled(n, ''), keys = List<String>.filled(n, '');
  for (var i = 0; i < main.n; i++) {
    if (i == t) continue;
    final to = mapMain(i);
    final p = main.par[i];
    par[to] = p < 0 ? -1 : mapMain(p);
    size[to] = main.size[i];
    gen[to] = main.gen[i];
    bits[to] = main.bits[i];
    edge[to] = main.edge[i];
    branch[to] = main.branch[i];
    color[to] = main.color[i];
    color2[to] = main.color2[i];
    name[to] = main.name[i];
    sub[to] = main.sub[i];
    keys[to] = main.keys[i];
  }
  final shift = main.gen[t] - chunk.gen[0];
  int mapColor(int c) => c >= 0 && c < chunkColor.length ? chunkColor[c] : 0;
  for (var i = 0; i < m; i++) {
    final to = mapChunk(i);
    final p = chunk.par[i];
    par[to] = p < 0 ? main.par[t] : mapChunk(p);
    size[to] = chunk.size[i];
    gen[to] = chunk.gen[i] + shift;
    bits[to] = chunk.bits[i];
    edge[to] = chunk.edge[i];
    branch[to] = chunk.branch[i] >= 0 && chunk.branch[i] < chunkBranch.length ? chunkBranch[chunk.branch[i]] : 0;
    color[to] = mapColor(chunk.color[i]);
    color2[to] = chunk.color2[i] == 0 ? 0 : mapColor(chunk.color2[i]);
    name[to] = chunk.name[i];
    sub[to] = chunk.sub[i];
    keys[to] = chunk.keys[i];
  }
  bits[t] &= ~kKinStub;
  // 조상들의 하위 수를 늘린다.
  for (var p = main.par[t]; p >= 0; p = main.par[p]) {
    size[mapMain(p)] += d;
  }

  // 덧선: 두 기록의 것 + 두 끝이 다 들어온 extraFar.
  final lines = <List<int>>[
    for (var e = 0; e < main.extra.length; e += 4)
      [mapMain(main.extra[e]), mapMain(main.extra[e + 1]), main.extra[e + 2], main.extra[e + 3]],
    for (var e = 0; e < chunk.extra.length; e += 4)
      [mapChunk(chunk.extra[e]), mapChunk(chunk.extra[e + 1]), chunk.extra[e + 2], chunk.extra[e + 3]],
  ];
  final byKey = <String, int>{for (var i = 0; i < n; i++) keys[i]: i};
  final far = <KinFarExtra>[];
  for (final f in [for (final f in main.extraFar) f.moved(mapMain(f.to)), for (final f in chunk.extraFar) f.moved(mapChunk(f.to))]) {
    final from = byKey[f.from];
    if (from != null) {
      lines.add([from, f.to, f.kind, f.gen]);
    } else {
      far.add(f);
    }
  }
  // 남은 extraFar는 (to, fromAt, 갈래, gen) 오름(export/kin.mjs joinKin과 같음).
  far.sort((a, b) {
    var c = a.to.compareTo(b.to);
    if (c == 0) c = a.fromAt.compareTo(b.fromAt);
    if (c == 0) c = a.kind.compareTo(b.kind);
    if (c == 0) c = a.gen.compareTo(b.gen);
    return c;
  });
  lines.sort((a, b) {
    for (final k in const [1, 0, 2, 3]) {
      final c = a[k].compareTo(b[k]);
      if (c != 0) return c;
    }
    return 0;
  });
  final extra = Int32List(lines.length * 4);
  for (var i = 0; i < lines.length; i++) {
    extra.setRange(i * 4, i * 4 + 4, lines[i]);
  }

  // 칸 표: (번호, 칸 열쇠) 오름 — 한 벌 기록의 칸 표 차례(D1-E ②).
  final cellList = [
    for (final e in main.cells.entries) MapEntry(e.key, mapMain(e.value)),
    for (final e in chunk.cells.entries) MapEntry(e.key, mapChunk(e.value)),
  ]..sort((a, b) {
      final c = a.value.compareTo(b.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  final cells = <String, int>{for (final e in cellList) e.key: e.value};
  final stubs = <int, KinStub>{
    for (final e in main.stubs.entries)
      if (e.key != t) mapMain(e.key): e.value,
    for (final e in chunk.stubs.entries) mapChunk(e.key): e.value,
  };
  return KinSkeleton(
    key: main.key,
    n: n,
    gens: _gensOf(gen),
    par: par,
    size: size,
    gen: gen,
    bits: bits,
    edge: edge,
    branch: branch,
    color: color,
    color2: color2,
    name: name,
    sub: sub,
    keys: keys,
    extra: extra,
    colors: colors,
    branches: branches,
    cells: cells,
    stubs: stubs,
    // 나누기가 덧붙인 '덩어리 …' 경고는 합치면 뺀다(export/kin.mjs joinKin과 같음 — 한 벌 기록에는 없음).
    warnings: [
      for (final w in [...main.warnings, ...chunk.warnings])
        if (!w.startsWith('덩어리 ')) w,
    ],
    root: main.root,
    extraFar: far,
  );
}

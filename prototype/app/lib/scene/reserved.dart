import 'scene.dart';

// 사건 이름과 점이 비켜 갈 구간 — 건국 · 멸망 네모, 소속/대범위 단추, 내림줄이 차지한 자리(지금 연표의 _sqZones · plan.zones).
// 그 자리를 아는 층(관계선)이 장면마다 적고, 이름 자리 셈(사건 층)이 읽는다. 자리는 분으로 적는다 — 옆으로 움직여도 다시 적을 일이 없고, 배율이 바뀌면 적는 쪽이 다시 적는다.
// 이름 자리 셈은 그리기보다 앞(scene.prepare)에 돌기 때문에 한 장면 늦게 반영된다: 적힌 것이 달라지면 [version]이 오르고, 읽는 쪽은 그 번호가 바뀌었을 때 다시 셈한다.

class ReservedZone {
  const ReservedZone(this.lo, this.hi, {this.line = -1, this.noDot = false, this.strength = 1, this.dir = 1});

  /// 비켜 갈 구간(분).
  final double lo, hi;

  /// 글줄 번호(−1이면 그 줄의 모든 글줄).
  final int line;

  /// 이름뿐 아니라 점도 놓지 않는 구간인가.
  final bool noDot;

  /// 이름이 얼마나 비켜야 하는가(지금 연표 `_placeRow`의 `blocks` 세 갈래):
  /// **0** = 이름 줄 전체를 막는다(소속 · 대범위 단추 · 내림줄 — js의 `reserved[row][k].push([l, r])`처럼 셋째 값이 없는 것) ·
  /// **1** = 글자 상자만 비킨다(글줄이 둘 이상인 줄의 건국 · 멸망 네모 — 점은 글줄 가운데라 네모와 3.5px 떨어져 있다) ·
  /// **2** = 글자의 먹 구간과 점 쪽 끝까지 비킨다(글줄이 하나인 줄의 네모).
  final int strength;

  /// [noDot]일 때 점을 미는 쪽(지금 연표 `avoid`의 `dir`): **+1** 오른쪽(건국 네모 · 단추 — `[a−4.5, b+8]`) ·
  /// **−1** 왼쪽(멸망 네모 — `[a−10, b+4.5]`). 부풀리는 폭이 미는 쪽에 따라 비대칭이라 함께 적는다.
  final int dir;

  @override
  bool operator ==(Object other) =>
      other is ReservedZone && other.lo == lo && other.hi == hi && other.line == line && other.noDot == noDot && other.strength == strength && other.dir == dir;
  @override
  int get hashCode => Object.hash(lo, hi, line, noDot, strength, dir);
}

class ReservedZones {
  static final _byScene = Expando<ReservedZones>('비켜 갈 구간');

  /// 그 장면의 것(없으면 만든다). 장면의 밭을 늘리지 않으려고 곁에 매단다.
  static ReservedZones of(TimelineScene scene) => _byScene[scene] ??= ReservedZones();

  final _bySource = <String, Map<int, List<ReservedZone>>>{};
  int version = 0;

  /// 한 출처(층)가 이번 장면에 적을 것을 통째로 갈아 끼운다: 줄 → 구간들. 앞 장면과 같으면 번호를 올리지 않는다.
  void put(String source, Map<int, List<ReservedZone>> zones) {
    final old = _bySource[source];
    if (old != null && _same(old, zones)) return;
    _bySource[source] = zones;
    version++;
  }

  /// 그 줄에 걸린 구간 모두(출처를 가리지 않고).
  /// [except]를 주면 그 출처가 적은 것은 뺀다(제가 적은 것에 스스로 막히지 않게).
  List<ReservedZone> at(int row, {String? except}) => [
    for (final e in _bySource.entries)
      if (e.key != except) ...?e.value[row],
  ];

  bool get isEmpty => _bySource.values.every((z) => z.isEmpty);

  static bool _same(Map<int, List<ReservedZone>> a, Map<int, List<ReservedZone>> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final other = b[e.key];
      if (other == null || other.length != e.value.length) return false;
      for (int i = 0; i < other.length; i++) {
        if (other[i] != e.value[i]) return false;
      }
    }
    return true;
  }
}

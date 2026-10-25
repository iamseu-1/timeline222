import 'dart:typed_data';

import 'levels.dart';
import 'tile.dart';

// 타일 보관. 화면은 장면마다 여기에 있는 것만 그리고, 없는 것은 뒤에서 받는 동안 윗단계 타일로 메운다.
// 자료 처리부에는 한 번에 하나만 묻고, 다음에 물을 것은 그때그때 '지금 원하는 목록'에서 고른다 —
// 빠르게 지나가 버린 단계의 요청은 보내지도 않고 사라진다.

class TileKey {
  const TileKey(this.level, this.x, this.chunk, this.packsVersion);
  final int level, x, chunk;

  /// 켠 자료집 조합의 판 번호(SceneLayout.version).
  final int packsVersion;

  @override
  bool operator ==(Object other) =>
      other is TileKey && other.level == level && other.x == x && other.chunk == chunk && other.packsVersion == packsVersion;
  @override
  int get hashCode => Object.hash(level, x, chunk, packsVersion);
  @override
  String toString() => 'TileKey(L$level x$x c$chunk v$packsVersion)';
}

class _Entry {
  _Entry(this.tile, this.arrivedMs);
  final Tile tile;
  final double arrivedMs;
}

class TileCache {
  TileCache({required this.fetch, this.limitBytes = 64 * 1024 * 1024, this.onArrive, double Function()? clock})
    : _clock = clock ?? _stopwatchClock();

  final Future<Uint8List> Function(TileKey key) fetch;
  final int limitBytes;
  final void Function(TileKey key)? onArrive;
  final double Function() _clock;

  static double Function() _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds / 1000;
  }

  /// 넣은 순서 = 쓴 순서. 쓸 때마다 맨 뒤로 옮긴다(LRU).
  final _tiles = <TileKey, _Entry>{};
  final _failedAt = <TileKey, double>{};
  List<TileKey> _visible = const [], _ahead = const [];
  TileKey? _inFlight;
  int _bytes = 0, _hits = 0, _misses = 0;

  int requests = 0, failures = 0, evictions = 0;
  double lastRoundTripMs = 0;
  int lastBytes = 0;
  final roundTrips = <double>[];

  int get bytes => _bytes;
  int get count => _tiles.length;
  double get hitRate => _hits + _misses == 0 ? 1 : _hits / (_hits + _misses);

  /// 제 단계의 타일. 없으면 null — 그리는 쪽은 [cover]로 메운다.
  Tile? get(TileKey key) {
    final entry = _tiles.remove(key);
    if (entry == null) {
      _misses++;
      return null;
    }
    _tiles[key] = entry;
    _hits++;
    return entry.tile;
  }

  double? arrivedAt(TileKey key) => _tiles[key]?.arrivedMs;

  /// 받기에 실패해 다시 묻기까지 쉬는 중인가(2초). 장면이 '타일을 기다리는 중'에서 뺀다.
  bool failedRecently(TileKey key) {
    final failed = _failedAt[key];
    return failed != null && _clock() - failed < 2000;
  }

  /// 방금까지 보던 자료집 조합의 판 번호들(가장 최근 것부터, 넷까지). 자료집을 켜고 끌 때 장면이 알려 준다.
  List<int> olderVersions = const [];

  /// 메움: 같은 자리의 옛 자료집 조합 타일, 없으면 같은 줄 묶음의 윗단계 타일(가까운 단계부터 맨 위까지).
  /// 타일 번호는 단계마다 4로 나눠 내림한다.
  Tile? cover(TileKey key) {
    for (final version in olderVersions) {
      final old = _tiles[TileKey(key.level, key.x, key.chunk, version)];
      if (old != null) return old.tile;
    }
    int x = key.x;
    for (int level = key.level + 1; level <= levelMax; level++) {
      x >>= 2;
      final up = _tiles[TileKey(level, x, key.chunk, key.packsVersion)];
      if (up != null) return up.tile;
      for (final version in olderVersions) {
        final old = _tiles[TileKey(level, x, key.chunk, version)];
        if (old != null) return old.tile;
      }
    }
    return null;
  }

  /// 지금 보이는 타일과 미리 받아 둘 타일(좌우 · 위아래 · 단계 위아래 · 맨 윗단계). 보이는 것을 먼저 묻는다.
  void want(List<TileKey> visible, List<TileKey> ahead) {
    _visible = visible;
    _ahead = ahead;
    _pump();
  }

  /// 새 타일을 묻지 않고 기다린다(있는 타일 · 메움은 그대로 그린다). 저장소를 제자리에서 고쳐 쓰는 동안 앱이 건다 — COMMIT 뒤의 답(새 줄 번호)이
  /// 옛 뼈대의 판 번호로 들어와 엉뚱한 줄에 그려지지 않게(계약 2-7). 풀어도 곧바로 묻지 않는다 — 다음 장면의 [want]가 그때의 판 번호로 묻는다
  /// (멈춰 있던 목록은 옛 뼈대의 것이다).
  bool paused = false;

  void _pump() {
    if (_inFlight != null || paused) return;
    final now = _clock();
    TileKey? next;
    for (final key in _visible.followedBy(_ahead)) {
      if (_tiles.containsKey(key)) continue;
      final failed = _failedAt[key];
      if (failed != null && now - failed < 2000) continue;
      next = key;
      break;
    }
    if (next == null) return;
    final key = _inFlight = next;
    requests++;
    fetch(key).then(
      (bytes) {
        _inFlight = null;
        _failedAt.remove(key);
        lastRoundTripMs = _clock() - now;
        lastBytes = bytes.length;
        roundTrips.add(lastRoundTripMs);
        try {
          _store(key, Tile.decode(bytes));
        } on FormatException {
          failures++;
          _failedAt[key] = _clock();
        }
        _pump();
      },
      onError: (Object _) {
        _inFlight = null;
        failures++;
        _failedAt[key] = _clock();
        _pump();
      },
    );
  }

  void _store(TileKey key, Tile tile) {
    final old = _tiles.remove(key);
    if (old != null) _bytes -= old.tile.byteLength;
    _tiles[key] = _Entry(tile, _clock());
    _bytes += tile.byteLength;
    if (_bytes > limitBytes) {
      // 보이는 것과 방금 온 것은 지킨다 — 빈 화면보다 한도를 잠깐 넘는 편이 낫다.
      final keep = {..._visible, key};
      for (final victim in _tiles.keys.toList()) {
        if (_bytes <= limitBytes) break;
        if (keep.contains(victim)) continue;
        _bytes -= _tiles.remove(victim)!.tile.byteLength;
        evictions++;
      }
    }
    onArrive?.call(key);
  }

  void clear() {
    _tiles.clear();
    _failedAt.clear();
    _bytes = 0;
  }

  /// 저장소를 제자리에서 고쳐 쓴 뒤(엔진 apply의 `first_pos` — 계약 2-7): 판 [from]의 타일 가운데 줄 묶음 [chunks] 앞의 것(묶음 번호 < [chunks] —
  /// 그 묶음의 끝 줄까지 바뀌지 않았다)만 새 판 [to]로 옮겨 남기고 나머지는 모두 버린다. [chunks]가 null이면 판 [from]의 타일을 모두 남긴다(바뀐 트랙 없음).
  void keepChunks({required int? chunks, required int from, required int to}) {
    final kept = <TileKey, _Entry>{
      for (final e in _tiles.entries)
        if (e.key.packsVersion == from && (chunks == null || e.key.chunk < chunks)) TileKey(e.key.level, e.key.x, e.key.chunk, to): e.value,
    };
    clear();
    _tiles.addAll(kept);
    for (final e in kept.values) {
      _bytes += e.tile.byteLength;
    }
  }
}

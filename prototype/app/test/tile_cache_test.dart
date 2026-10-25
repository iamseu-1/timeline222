import 'dart:async';
import 'dart:typed_data';

import 'package:archive_prototype/scene/tile_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tile_builder.dart';

/// 내용이 빈 타일 바이트(타일 2판). [pad]만큼 뒤를 늘려 큰 타일을 흉내 낸다.
Uint8List tileBytes(TileKey k, {int pad = 0}) {
  final bytes = TileBuilder(level: k.level, x: k.x, chunk: k.chunk).build();
  return pad == 0 ? bytes : (Uint8List(bytes.length + pad)..setAll(0, bytes));
}

/// 응답을 손으로 늦추는 가짜 자료 처리부.
class FakeEngine {
  final asked = <TileKey>[];
  final _waiting = <TileKey, Completer<Uint8List>>{};
  Future<Uint8List> fetch(TileKey k) {
    asked.add(k);
    return (_waiting[k] = Completer<Uint8List>()).future;
  }

  Future<void> answer(TileKey k, {int pad = 0}) async {
    _waiting.remove(k)!.complete(tileBytes(k, pad: pad));
    await pumpEventQueue();
  }

  Future<void> fail(TileKey k) async {
    _waiting.remove(k)!.completeError(StateError('읽기 실패'));
    await pumpEventQueue();
  }
}

const a = TileKey(9, 0, 0, 0), b = TileKey(9, 1, 0, 0), c = TileKey(9, 2, 0, 0), d = TileKey(7, 40, 0, 0);

void main() {
  test('보이는 것부터 한 번에 하나씩 묻고, 도착하면 알린다', () async {
    final engine = FakeEngine();
    final arrived = <TileKey>[];
    final cache = TileCache(fetch: engine.fetch, onArrive: arrived.add);
    cache.want([a, b], [c]);
    expect(engine.asked, [a]);
    expect(cache.get(a), isNull);
    await engine.answer(a);
    expect(cache.get(a), isNotNull);
    expect(arrived, [a]);
    expect(engine.asked, [a, b]);
    await engine.answer(b);
    expect(engine.asked, [a, b, c], reason: '보이는 것이 다 온 뒤에야 미리 받기');
    await engine.answer(c);
    cache.want([a, b], [c]);
    expect(engine.asked.length, 3, reason: '이미 있는 타일은 다시 묻지 않는다');
  });

  test('빠르게 지나간 단계의 보내지 않은 요청은 버려진다', () async {
    final engine = FakeEngine();
    final cache = TileCache(fetch: engine.fetch);
    cache.want([a, b], []);
    cache.want([c], []);
    cache.want([d], []);
    expect(engine.asked, [a], reason: '이미 보낸 하나만 나가 있다');
    await engine.answer(a);
    expect(engine.asked, [a, d], reason: 'b · c는 묻지 않고 마지막 보기의 것만');
    expect(cache.get(a), isNotNull, reason: '늦게 온 것도 보관은 한다(돌아올 수 있다)');
  });

  test('빈 타일도 도착한 타일이다', () async {
    final engine = FakeEngine();
    final cache = TileCache(fetch: engine.fetch);
    cache.want([a], []);
    await engine.answer(a);
    expect(cache.get(a)!.eventCount, 0);
    cache.want([a], []);
    expect(engine.asked, [a]);
  });

  test('없는 타일은 윗단계 타일로 메운다', () async {
    final engine = FakeEngine();
    final cache = TileCache(fetch: engine.fetch);
    const parent = TileKey(10, 5, 3, 0), grand = TileKey(12, 1, 3, 0);
    cache.want([grand], []);
    await engine.answer(grand);
    // 단계 9의 타일 20~23은 단계 10의 타일 5, 단계 12의 타일 0(=5>>4)… 타일 번호는 단계마다 4로 나눠 내림한다.
    expect(cache.cover(const TileKey(9, 21, 3, 0)), isNull, reason: '12단계의 1번은 9단계의 64~127번을 덮는다');
    expect(cache.cover(const TileKey(9, 100, 3, 0))!.level, 12);
    cache.want([parent], []);
    await engine.answer(parent);
    expect(cache.cover(const TileKey(9, 21, 3, 0))!.level, 10, reason: '가까운 윗단계가 먼저');
    expect(cache.cover(const TileKey(9, 21, 4, 0)), isNull, reason: '줄 묶음이 다르면 메우지 못한다');
    expect(cache.cover(const TileKey(9, -1, 3, 0)), isNull);
    const negative = TileKey(11, -1, 3, 0);
    cache.want([negative], []);
    await engine.answer(negative);
    expect(cache.cover(const TileKey(9, -3, 3, 0))!.x, -1, reason: '기원전 타일 번호도 내림');
  });

  test('자료집 조합이 바뀌면 옛 조합의 타일은 메움으로만 쓰인다', () async {
    final engine = FakeEngine();
    final cache = TileCache(fetch: engine.fetch);
    cache.want([a], []);
    await engine.answer(a);
    const next = TileKey(9, 0, 0, 1);
    expect(cache.get(next), isNull);
    expect(cache.cover(next), isNull, reason: '어느 조합을 보다가 왔는지 모르면 메우지 않는다');
    cache.olderVersions = [0]; // 방금까지 보던 조합의 판 번호(장면이 알려 준다)
    expect(cache.cover(next), same(cache.get(a)));
    cache.want([next], []);
    await engine.answer(next);
    expect(cache.get(next), isNotNull);
    expect(cache.get(next), isNot(same(cache.get(a))));
  });

  test('한도를 넘으면 오래 안 쓴 것부터 버리되 보이는 것은 지킨다', () async {
    final engine = FakeEngine();
    final cache = TileCache(fetch: engine.fetch, limitBytes: 3000);
    for (final k in [a, b, c]) {
      cache.want([k], []);
      await engine.answer(k, pad: 924); // 1,000바이트씩
    }
    expect(cache.bytes, 3000);
    cache.get(a); // a를 방금 썼다 → 가장 오래된 것은 b
    cache.want([d], []);
    await engine.answer(d, pad: 924);
    expect(cache.get(b), isNull);
    expect(cache.get(a), isNotNull);
    expect(cache.get(d), isNotNull);
    expect(cache.bytes, 3000);
    // 보이는 것만으로 한도를 넘으면 버리지 않는다(빈 화면보다 낫다).
    final small = TileCache(fetch: engine.fetch, limitBytes: 1500);
    small.want([a, b], []);
    await engine.answer(a, pad: 924);
    await engine.answer(b, pad: 924);
    expect(small.get(a), isNotNull);
    expect(small.get(b), isNotNull);
  });

  test('읽기에 실패한 타일은 곧바로 다시 묻지 않고 다른 타일은 계속 받는다', () async {
    final engine = FakeEngine();
    var now = 0.0;
    final cache = TileCache(fetch: engine.fetch, clock: () => now);
    cache.want([a, b], []);
    await engine.fail(a);
    expect(cache.failures, 1);
    expect(engine.asked, [a, b]);
    await engine.answer(b);
    cache.want([a, b], []);
    expect(engine.asked, [a, b], reason: '2초 안에는 다시 묻지 않는다');
    now = 2500;
    cache.want([a, b], []);
    expect(engine.asked, [a, b, a]);
  });

  test('적중률과 도착 시각을 센다', () async {
    final engine = FakeEngine();
    var now = 100.0;
    final cache = TileCache(fetch: engine.fetch, clock: () => now);
    cache.want([a], []);
    expect(cache.get(a), isNull);
    now = 130;
    await engine.answer(a);
    expect(cache.get(a), isNotNull);
    expect(cache.get(a), isNotNull);
    expect(cache.hitRate, closeTo(2 / 3, 1e-9));
    expect(cache.arrivedAt(a), 130);
    expect(cache.requests, 1);
    expect(cache.lastRoundTripMs, 30);
  });
}

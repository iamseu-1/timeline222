import 'dart:async';
import 'dart:typed_data';

import 'package:archive_prototype/scene/label_worker.dart';
import 'package:archive_prototype/scene/labels.dart';
import 'package:flutter_test/flutter_test.dart';

LabelInput input(int version, {double x = 100}) => LabelInput(
  version: version,
  pxPerMinute: 1,
  spanYears: 100,
  at: Float64List.fromList([x, x + 300]),
  row: Int32List.fromList([0, 0]),
  importance: Int32List.fromList([1, 2]),
  eventId: Int32List.fromList([1, 2]),
  look: Uint32List.fromList([255 << 8, 255 << 8]),
  band: Int32List.fromList([0, 0]),
  nameWidth: Float32List.fromList([50, 50]),
  yearWidth: Float32List.fromList([0, 0]),
  countWidth: Float32List.fromList([0, 0]),
  kids: Int32List.fromList([0, 0]),
  bandLo: Float64List.fromList([double.negativeInfinity, double.negativeInfinity]),
  bandHi: Float64List.fromList([double.infinity, double.infinity]),
  precLo: Float64List.fromList([double.nan, double.nan]),
  precHi: Float64List.fromList([double.nan, double.nan]),
  pillLo: Float64List(0),
  pillHi: Float64List(0),
  pillRow: Int32List(0),
  pillRest: Int32List(0),
  rowBase: 0,
  rowLines: Int32List.fromList([2]),
  expandedKeys: Int32List(0),
);

/// 계산을 손으로 끝내는 가짜 작업자.
class Manual {
  final started = <int>[];
  final _waiting = <int, Completer<LabelOutput>>{};
  Future<LabelOutput> compute(LabelInput i) {
    started.add(i.version);
    return (_waiting[i.version] = Completer<LabelOutput>()).future;
  }

  Future<void> finish(int version, LabelInput i) async {
    _waiting.remove(version)!.complete(placeLabels(i));
    await pumpEventQueue();
  }

  Future<void> fail(int version) async {
    _waiting.remove(version)!.completeError(StateError('작업자가 죽었습니다'));
    await pumpEventQueue();
  }
}

void main() {
  test('한 번에 하나만 계산하고, 밀린 요청은 마지막 것만 남긴다', () async {
    final manual = Manual();
    final got = <int>[];
    final worker = LabelWorker(compute: manual.compute, onResult: (o) => got.add(o.version));
    worker.request(input(1));
    worker.request(input(2));
    worker.request(input(3));
    expect(manual.started, [1]);
    await manual.finish(1, input(1));
    expect(got, [1]);
    expect(manual.started, [1, 3], reason: '2번은 계산하지 않고 버린다');
    await manual.finish(3, input(3));
    expect(got, [1, 3]);
    expect(worker.latest!.version, 3);
    expect((worker.requested, worker.computed, worker.dropped), (3, 2, 1));
  });

  test('앞 판의 결과를 다음 계산의 이력으로 넘긴다', () async {
    final seen = <LabelOutput?>[];
    final worker = LabelWorker(
      compute: (i) async {
        seen.add(i.previous);
        return placeLabels(i);
      },
    );
    worker.request(input(1));
    await pumpEventQueue();
    worker.request(input(2));
    await pumpEventQueue();
    expect(seen[0], isNull);
    expect(seen[1]!.version, 1);
  });

  test('이미 더 새 판을 적용했으면 늦게 온 결과는 버린다', () async {
    final got = <int>[];
    final worker = LabelWorker(compute: (i) async => placeLabels(i), onResult: (o) => got.add(o.version));
    worker.request(input(5));
    await pumpEventQueue();
    worker.accept(placeLabels(input(4)));
    expect(got, [5]);
    expect(worker.latest!.version, 5);
    expect(worker.dropped, 1);
  });

  test('작업자가 실패해도 앞 판은 남고 다음 요청은 계속 돈다', () async {
    final manual = Manual();
    final worker = LabelWorker(compute: manual.compute);
    worker.request(input(1));
    await manual.finish(1, input(1));
    worker.request(input(2));
    await manual.fail(2);
    expect(worker.failures, 1);
    expect(worker.latest!.version, 1, reason: '화면은 앞 판으로 계속 그린다');
    worker.request(input(3));
    await manual.finish(3, input(3));
    expect(worker.latest!.version, 3);
  });

  test('진짜 작업자(isolate)도 같은 결과를 낸다', () async {
    final done = Completer<LabelOutput>();
    final worker = LabelWorker(onResult: done.complete);
    addTearDown(worker.dispose);
    worker.request(input(7));
    final out = await done.future.timeout(const Duration(seconds: 20));
    final same = placeLabels(input(7));
    expect(out.version, 7);
    expect(out.shownCandidate, same.shownCandidate);
    expect(out.shownSide, same.shownSide);
    expect(worker.lastMs, greaterThanOrEqualTo(0));
  });

  test('작업자를 띄우지 못해도 이름 자리는 그 자리에서 계산되어 나오고, 다음 요청에서 다시 띄워 본다', () async {
    // 띄우기가 한 번 실패한 채로 굳으면 그 뒤로 이름과 묶음 개수가 영영 나오지 않는다 — 사건이 없는 자료처럼 보인다.
    int attempts = 0;
    final results = <LabelOutput>[];
    final worker = LabelWorker(
      onResult: results.add,
      spawn: (entry, port) {
        attempts++;
        throw StateError('작업자를 띄울 수 없음');
      },
    );
    addTearDown(worker.dispose);
    worker.request(input(1));
    await pumpEventQueue();
    expect(results.map((r) => r.version), [1], reason: '느려도 이름은 나온다');
    expect(results.single.shownCandidate, placeLabels(input(1)).shownCandidate);
    expect(attempts, 1);
    worker.request(input(2));
    await pumpEventQueue();
    expect(attempts, 2, reason: '다음 요청에서 다시 띄워 본다');
    worker.request(input(3));
    await pumpEventQueue();
    worker.request(input(4));
    await pumpEventQueue();
    expect(attempts, 3, reason: '세 번 실패하면 더 띄우지 않고 그 자리에서만 계산한다');
    expect(results.map((r) => r.version), [1, 2, 3, 4]);
    expect(worker.failures, 0, reason: '계산은 실패하지 않았다');
  });
}

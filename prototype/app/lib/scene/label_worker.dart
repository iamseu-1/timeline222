import 'dart:async';
import 'dart:isolate';

import 'labels.dart';

// 이름 자리 계산을 화면 뒤에서 돌린다. 화면은 결과를 기다리지 않고 앞 판으로 계속 그린다.
//  · 한 번에 하나만 계산하고, 그동안 밀린 요청은 마지막 것만 남긴다(지나가 버린 배율의 자리는 쓸모가 없다).
//  · 결과에는 판 번호가 붙어 있어, 이미 더 새 판을 적용했으면 늦게 온 결과는 버린다.
//  · 작업자가 실패해도 앞 판이 남고 다음 요청은 계속 돈다.
/// 작업자를 띄우는 방법(검사는 실패하는 것을 넣어 본다).
typedef SpawnWorker = Future<Isolate> Function(void Function(SendPort) entry, SendPort port);

class LabelWorker {
  LabelWorker({Future<LabelOutput> Function(LabelInput input)? compute, this.onResult, SpawnWorker? spawn}) {
    _compute = compute ?? (_isolate = _IsolateCompute(spawn ?? Isolate.spawn<SendPort>)).call;
  }

  late final Future<LabelOutput> Function(LabelInput input) _compute;
  _IsolateCompute? _isolate;
  final void Function(LabelOutput output)? onResult;

  /// 지금 화면이 쓰는 판.
  LabelOutput? latest;
  LabelInput? _next;
  bool _busy = false;
  int requested = 0, computed = 0, dropped = 0, failures = 0;
  double lastMs = 0;
  final times = <double>[];

  bool get busy => _busy;

  void request(LabelInput input) {
    requested++;
    if (_busy) {
      if (_next != null) dropped++;
      _next = input;
      return;
    }
    _run(input);
  }

  void _run(LabelInput input) {
    _busy = true;
    final watch = Stopwatch()..start();
    // 앞 판의 결과가 이력이다: 보이던 이름은 남고, 묶여 있던 것은 14px 벌어져야 풀린다.
    _compute(input.withPrevious(latest)).then(
      (output) {
        lastMs = watch.elapsedMicroseconds / 1000;
        times.add(lastMs);
        computed++;
        accept(output);
        _after();
      },
      onError: (Object _) {
        failures++;
        _after();
      },
    );
  }

  void _after() {
    _busy = false;
    final next = _next;
    _next = null;
    if (next != null) _run(next);
  }

  /// 결과를 적용한다. 이미 더 새 판을 적용했으면 버린다.
  void accept(LabelOutput output) {
    if (latest != null && output.version <= latest!.version) {
      dropped++;
      return;
    }
    latest = output;
    onResult?.call(output);
  }

  void dispose() => _isolate?.close();
}

/// 오래 사는 작업자 하나. 입력 · 출력은 배열이라 값으로 넘어간다.
class _IsolateCompute {
  _IsolateCompute(this._spawn);
  final SpawnWorker _spawn;
  Isolate? _isolate;
  SendPort? _port;
  ReceivePort? _replies;
  Completer<LabelOutput>? _waiting;
  Future<void>? _starting;

  int _startFailures = 0;

  /// 작업자를 띄우지 못하면 그 자리에서 계산한다 — 느려도 이름과 묶음 개수는 나와야 한다(안 나오면 사건이 없는 자료처럼 보인다).
  /// 다음 요청에서 다시 띄워 보고, 세 번 실패하면 더 띄우지 않는다.
  Future<LabelOutput> call(LabelInput input) async {
    if (_startFailures >= 3) return placeLabels(input);
    try {
      await (_starting ??= _start());
    } catch (_) {
      _startFailures++;
      _starting = null;
      _replies?.close();
      _replies = null;
      return placeLabels(input);
    }
    final waiting = _waiting = Completer<LabelOutput>();
    _port!.send(input);
    return waiting.future;
  }

  Future<void> _start() async {
    final ready = Completer<void>();
    final replies = _replies = ReceivePort();
    replies.listen((message) {
      if (message is SendPort) {
        _port = message;
        ready.complete();
      } else if (message is LabelOutput) {
        _waiting?.complete(message);
      } else {
        _waiting?.completeError(StateError(message.toString()));
      }
    });
    _isolate = await _spawn(_main, replies.sendPort);
    await ready.future;
  }

  static void _main(SendPort parent) {
    final inbox = ReceivePort();
    parent.send(inbox.sendPort);
    inbox.listen((message) {
      try {
        parent.send(placeLabels(message as LabelInput));
      } catch (e) {
        parent.send('이름 자리 계산 실패: $e');
      }
    });
  }

  void close() {
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
  }
}

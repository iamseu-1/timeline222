import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// 자료 처리부의 기본 자리 — Windows는 실행 파일 곁의 dll, 안드로이드는 설치 꾸러미의 .so(이름만으로 찾음),
/// 아이패드 · 아이폰은 앱 묶음(Runner.app)의 Frameworks에 넣은 프레임워크를 온전한 경로로 연다
/// (iOS는 따로 둔 라이브러리를 이름만으로 찾지 않는다 — 넣는 것은 prototype/scripts/release/build-ios.sh).
String engineLibraryPath() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isWindows) return '$exeDir/archive_engine.dll';
  if (Platform.isIOS) return '$exeDir/Frameworks/archive_engine.framework/archive_engine';
  return 'libarchive_engine.so';
}

/// 자료 처리부의 `archive_call`을 한 번 부른다 — 따로 띄운 isolate(`Isolate.run`) 안에서 쓴다([ArchiveEngine.apply]).
/// 같은 경로의 라이브러리를 다시 열면 운영체제가 이미 올린 것을 그대로 준다(같은 전역 저장소). 답은 JSON 그대로 · 던지지 않는다.
Map<String, dynamic> callEngineOnce(String library, String request) {
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open(library);
  } catch (e) {
    return {'ok': false, 'error': '자료 처리부를 열 수 없습니다: $e'};
  }
  final call = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>), Pointer<Utf8> Function(Pointer<Utf8>)>('archive_call');
  final release = lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('archive_free');
  final input = request.toNativeUtf8();
  Pointer<Utf8> output = nullptr;
  try {
    output = call(input);
    if (output == nullptr) return {'ok': false, 'error': '자료 처리부의 답이 비었습니다'};
    return Map<String, dynamic>.from(jsonDecode(output.toDartString()) as Map);
  } catch (e) {
    return {'ok': false, 'error': '자료 처리부를 부르지 못했습니다: $e'};
  } finally {
    malloc.free(input);
    if (output != nullptr) release(output);
  }
}

// 긴 조회는 이 작업자에서만 실행한다. 화면에는 제한된 결과만 전달한다.
class ArchiveEngine {
  /// [libraryPath]를 비우면 실행 파일 곁의 자료 처리부를 연다. 검사는 빌드 폴더의 것을 직접 가리킨다.
  ArchiveEngine({this.libraryPath});
  final String? libraryPath;
  late SendPort _worker;
  late Isolate _isolate;
  final _replies = ReceivePort();
  final _pending = <int, Completer<Object>>{};
  int _id = 0;
  Future<Map<String, dynamic>> start(String path) async {
    final ready = Completer<void>();
    _replies.listen((message) {
      if (message is SendPort) {
        _worker = message;
        ready.complete();
      } else {
        final reply = message as List;
        final waiter = _pending.remove(reply[0]);
        final value = reply[1];
        if (value is TransferableTypedData) {
          waiter?.complete(value.materialize().asUint8List());
        } else if (value is Map && value['ok'] == true) {
          waiter?.complete(Map<String, dynamic>.from(value));
        } else {
          waiter?.completeError(StateError((value as Map)['error'].toString()));
        }
      }
    });
    _isolate = await Isolate.spawn(_run, [_replies.sendPort, libraryPath]);
    await ready.future.timeout(const Duration(seconds: 10));
    return call({'op': 'open', 'path': path});
  }

  Future<T> _ask<T extends Object>(List<Object?> message) {
    final id = ++_id;
    final result = Completer<Object>();
    _pending[id] = result;
    _worker.send([id, ...message]);
    return result.future
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            _pending.remove(id);
            throw StateError("자료 조회 응답 시간 초과");
          },
        )
        .then((value) => value as T);
  }

  Future<Map<String, dynamic>> call(Map<String, dynamic> query) =>
      _ask<Map<String, dynamic>>(['call', query]);

  /// 넣고 빼기(`{"op":"apply"}` — 계약 2-7)를 **쓰기 전용 일꾼**에서 부른다: `Isolate.run`이 같은 자료 처리부를 열어(같은 프로세스라 열린 저장소를
  /// 함께 쓴다) `archive_call`로 부른다. 이 작업자(타일 · 조회)의 줄을 막지 않는다 — 엔진은 쓰기 연결을 따로 열고 COMMIT 순간만 저장소 잠금을 쥐므로
  /// 쓰는 몇 초 동안에도 타일 · 조회가 옛 답을 곧바로 받는다. 답의 겉은 `archive_call` 그대로(`{"ok":true,"data":{…}}` ·
  /// `{"ok":false,"error",["committed":true]}`) — 던지지 않는다. 15초 시간 제한이 없다(큰 저장소의 고쳐 쓰기는 더 걸릴 수 있다).
  Future<Map<String, dynamic>> apply(Map<String, dynamic> request) => write({...request, 'op': 'apply'});

  /// 저장소에 쓰는 명령 하나(`{"op":"apply" | "add_pack" | "remove_pack", …}` — 계약 2-7 · 2-7-1)를 [apply]와 같은 **쓰기 전용 일꾼**에서 부른다
  /// (DLC 넣기 · 빼기를 엔진 하나로 — 계획 P4 과제 10b). 답의 겉은 `archive_call` 그대로(`code` · `committed` 포함) — 던지지 않는다 · 시간 제한 없음.
  Future<Map<String, dynamic>> write(Map<String, dynamic> request) {
    final library = libraryPath ?? engineLibraryPath();
    final text = jsonEncode(request);
    return Isolate.run(() => callEngineOnce(library, text));
  }

  /// 이진 타일 하나(단계 · 타일 번호 · 줄 묶음 · 켠 자료집). 바이트는 작업자에서 복사 없이 넘어온다.
  /// [filter]는 필터의 거르개(계약 2-2절 — 없으면 거르지 않는다).
  /// [variants]는 켠 변형(소속 펼치기 · 대범위 모아 보기 — 계약 2-4절)의 열쇠들.
  Future<Uint8List> tile(int level, int x, int chunk, List<int> packs, {Map<String, dynamic>? filter, List<String>? variants}) =>
      _ask<Uint8List>(['tile', level, x, chunk, packs, filter, variants]);

  /// 문서 그림 바이트 하나(열쇠 `img:<DLC id>/<그림 id>` — 문서 기록의 `images[이름].key`). 바이트는 작업자에서 복사 없이 넘어온다.
  /// 없으면 null. `archive_blob`이 없는 옛 자료 처리부는 `{"op":"blob"}`(base64)로 받는다 — 둘 다 없거나 실패하면 null.
  Future<Uint8List?> blob(String key) async {
    try {
      final bytes = await _ask<Uint8List>(['blob', key]);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  void close() {
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    for (final c in _pending.values) {
      c.completeError(StateError('자료 처리 종료'));
    }
    _pending.clear();
  }

  static void _run(List<Object?> boot) {
    final parent = boot[0] as SendPort;
    final requests = ReceivePort();
    // 자료 처리부를 먼저 불러온 뒤 준비 상태를 알린다.
    final lib = DynamicLibrary.open(boot[1] as String? ?? engineLibraryPath());
    final call = lib
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)
        >('archive_call');
    final release = lib
        .lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)
        >('archive_free');
    final tile = lib
        .lookupFunction<
          Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Size>),
          Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Size>)
        >('archive_tile');
    final releaseBytes = lib
        .lookupFunction<
          Void Function(Pointer<Uint8>, Size),
          void Function(Pointer<Uint8>, int)
        >('archive_free_bytes');
    final length = calloc<Size>();
    // 문서 그림(`archive_blob`)은 이 일 뒤의 자료 처리부에만 있다 — 없으면 null로 두고 base64 조회로 대신한다.
    final blob = lib.providesSymbol('archive_blob')
        ? lib.lookupFunction<
            Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Size>),
            Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Size>)
          >('archive_blob')
        : null;

    Map<String, dynamic> ask(Object? query) {
      final input = jsonEncode(query).toNativeUtf8();
      Pointer<Utf8>? output;
      try {
        output = call(input);
        return Map<String, dynamic>.from(jsonDecode(output.toDartString()));
      } finally {
        malloc.free(input);
        if (output != null) release(output);
      }
    }

    parent.send(requests.sendPort);
    requests.listen((message) {
      final request = message as List;
      try {
        if (request[1] == 'tile') {
          final input = jsonEncode({
            'level': request[2],
            'x': request[3],
            'chunk': request[4],
            'packs': request[5],
            if (request.length > 6 && request[6] != null) 'filter': request[6],
            if (request.length > 7 && request[7] != null && (request[7] as List).isNotEmpty) 'variants': request[7],
          }).toNativeUtf8();
          try {
            final bytes = tile(input, length);
            if (bytes == nullptr) {
              final why = ask({'op': 'last_error'});
              parent.send([
                request[0],
                {'ok': false, 'error': why['data']?['error'] ?? '타일을 만들지 못했습니다'},
              ]);
            } else {
              // 처리부의 메모리는 곧바로 돌려주고, 복사본 하나만 화면 쪽으로 넘긴다.
              final copy = Uint8List.fromList(bytes.asTypedList(length.value));
              releaseBytes(bytes, length.value);
              parent.send([
                request[0],
                TransferableTypedData.fromList([copy]),
              ]);
            }
          } finally {
            malloc.free(input);
          }
        } else if (request[1] == 'blob') {
          final key = request[2] as String;
          if (blob == null) {
            final answer = ask({'op': 'blob', 'key': key});
            final data = answer['ok'] == true ? (answer['data'] as Map)['data'] : null;
            parent.send([request[0], data is String ? TransferableTypedData.fromList([base64Decode(data)]) : TransferableTypedData.fromList([Uint8List(0)])]);
          } else {
            final input = jsonEncode({'key': key}).toNativeUtf8();
            try {
              final bytes = blob(input, length);
              if (bytes == nullptr) {
                parent.send([request[0], TransferableTypedData.fromList([Uint8List(0)])]);
              } else {
                final copy = Uint8List.fromList(bytes.asTypedList(length.value));
                releaseBytes(bytes, length.value);
                parent.send([request[0], TransferableTypedData.fromList([copy])]);
              }
            } finally {
              malloc.free(input);
            }
          }
        } else {
          parent.send([request[0], ask(request[2])]);
        }
      } catch (e) {
        parent.send([
          request[0],
          {'ok': false, 'error': e.toString()},
        ]);
      }
    });
  }
}

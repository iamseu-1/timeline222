import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

// 검사가 저장소를 짓는 길 — 자료 처리부의 `archive_import`(배치 JSON · 예전 아카이브 배치 .htlayout → 새 저장소). 앱은 계획 P4 과제 11c부터 배치를
// 받지 않으므로 이 길은 검사에만 남는다(원본 없이 든 DLC가 있는 옛 저장소 · 문서 그림의 작은 저장소를 짓는다 — `lib/ui/dlc_layout_import.dart`에서 옮김).

/// `archive_import`의 요청(계약 초안 가-3). [fromStore]를 주면 자료 처리부가 조합을 대조하고(5-3) 그 저장소의 원본을 옮겨 싣는다(5-4 라).
/// 기본팩 원본([base])은 주지 않으면 지금 저장소에서 옮긴다. [out]이 있으면 자료 처리부가 거절한다(덮어쓰지 않는다).
Map<String, dynamic> layoutImportRequest({required String layout, required String out, String? fromStore, String? base, List<String> originals = const [], bool checkOnly = false}) => {
  'layout': layout,
  'out': out,
  'base': ?base,
  if (originals.isNotEmpty) 'originals': originals,
  'from_store': ?fromStore,
  'check_only': checkOnly,
};

/// `archive_import`를 부른다 — 따로 띄운 isolate(`Isolate.run`)에서 [libraryPath]의 자료 처리부를 열어 부르고 답(JSON)을 돌려준다.
/// 답의 겉은 `archive_call`과 같다: `{"ok":true,"data":{…}}` 또는 `{"ok":false,"error":"<한국어 까닭>"}`.
Future<Map<String, dynamic>> callArchiveImport(Map<String, dynamic> request, {required String libraryPath}) {
  final text = jsonEncode(request);
  return Isolate.run(() => _importNow(libraryPath, text));
}

/// 자료 처리부에 `archive_import`가 있는가.
bool engineHasImport(String library) {
  try {
    return DynamicLibrary.open(library).providesSymbol('archive_import');
  } catch (_) {
    return false;
  }
}

Map<String, dynamic> _importNow(String library, String request) {
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open(library);
  } catch (e) {
    return {'ok': false, 'error': '자료 처리부를 열 수 없습니다: $e'};
  }
  if (!lib.providesSymbol('archive_import')) {
    return {'ok': false, 'error': '이 자료 처리부에는 배치 가져오기(archive_import)가 없습니다 — 앱과 자료 처리부를 함께 새로 받아 주세요.'};
  }
  final run = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>), Pointer<Utf8> Function(Pointer<Utf8>)>('archive_import');
  final release = lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('archive_free');
  final input = request.toNativeUtf8();
  Pointer<Utf8> output = nullptr;
  try {
    output = run(input);
    if (output == nullptr) return {'ok': false, 'error': '배치를 가져오지 못했습니다(자료 처리부의 답이 비었습니다).'};
    return Map<String, dynamic>.from(jsonDecode(output.toDartString()) as Map);
  } catch (e) {
    return {'ok': false, 'error': '배치를 가져오지 못했습니다: $e'};
  } finally {
    malloc.free(input);
    if (output != nullptr) release(output);
  }
}

/// 지문이 맞는 진짜 DLC 전용 팩(.htpack)을 엔진 도구로 봉인해 [dir]/`<id>-v<판>.htpack`에 둔다 — 짓기가 .json 본문을 봉인해 싣고(`build`)
/// `pack-out`이 꺼낸다(검사의 흉내 팩은 지문이 0이라 엔진이 받지 않는다). 본문은 맨 바깥 칸과 트랙 하나.
Future<String> sealDlcWithTool(String tool, String dir, {required String id, required String version, String? name}) async {
  final sep = Platform.pathSeparator;
  final source = (File('$dir$sep$id.json')
        ..writeAsStringSync(jsonEncode({'format': 'history-timeline-dlc', 'id': id, 'name': name ?? id, 'version': version, 'tracks': [{'id': '$id-t', 'name': '갈래'}]})))
      .path;
  final seal = '$dir$sep봉인-$id.db';
  final built = await Process.run(tool, [
    'build', seal, source, '--now=2026-10-22T09:00:00+09:00', '--calendar=${File('../engine/tests/fixtures/lay/calendar-slice.json').absolute.path}', '--calendar-narrow',
  ], stdoutEncoding: utf8, stderrEncoding: utf8);
  if (built.exitCode != 0) throw StateError('archive-tool build: ${built.stderr}');
  final out = '$dir$sep$id-v$version.htpack';
  final taken = await Process.run(tool, ['pack-out', seal, id, out], stdoutEncoding: utf8, stderrEncoding: utf8);
  if (taken.exitCode != 0) throw StateError('archive-tool pack-out: ${taken.stderr}');
  return out;
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'archive_app.dart';

void main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.contains('--offline=yes')) {
    HttpOverrides.global = OfflineOnly();
  }
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 * 1024 * 1024;
  // DLC 더하기는 앱 안에서 뒤에서 돈다(ui/dlc_add.dart · 4단계 1걸음) — 따로 뜨던 진행 창(--dlc-add=)은 없앴다.
  // 연결 프로그램으로 .htpack을 열었을 때: `--add-dlc=<파일;파일>`을 앱 틀이 받아 뜬 뒤에 더한다.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // 휴대폰: 위의 상태 줄과 옆 · 아래의 길잡이 줄을 걷어 세로 자리를 번다(가장자리를 쓸면 잠깐 나온다).
  if (Platform.isAndroid || Platform.isIOS) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(ArchiveApp(arguments: arguments));
}

// 검사 실행에서 모든 Dart 네트워크 요청을 즉시 거절한다. 원문과 DB는 로컬 파일만 연다.
class OfflineOnly extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('오프라인 검사 중 네트워크 요청은 허용하지 않습니다');
}

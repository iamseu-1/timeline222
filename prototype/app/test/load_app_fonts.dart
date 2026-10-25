import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _loaded = false;

/// 그림·폭 검사는 실행본과 같은 내장 글꼴을 읽는다. 누락된 파일은 즉시 실패한다.
/// 완료된 Future는 testWidgets의 이전 FakeAsync 영역에 남을 수 있어 완료 여부만 기억한다.
Future<void> loadAppFonts() async {
  if (_loaded) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (family, files) in const [
    ('Pretendard', ['Pretendard-Regular.otf', 'Pretendard-SemiBold.otf', 'Pretendard-Bold.otf']),
    ('ChosunKm', ['ChosunKm.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      // rootBundle의 비동기 자산 응답을 기다리지 않아 위젯 검사의 가상 시간 안에서도 끝난다.
      final bytes = File('assets/fonts/$file').readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  _loaded = true;
}

import 'dart:io';

import '../ui/app_memory.dart';
import 'cleartype.dart';

/// ClearType 설정 — 사용자 켬/끔(기억 `parts['text']`) · Windows 설정(앱을 켤 때 한 번 읽음) · 굽개 유무.
class ClearTypePrefs {
  static bool on = true;
  static ClearTypeInfo system = const ClearTypeInfo(true, false);

  /// 글자 굽개를 열었는가. 연표 화면이 그림판을 지을 때 한 번 정한다(DLL을 차림표가 다시 열지 않게). 옛 자료 처리부 · Windows가 아니면 거짓.
  static bool bakerReady = false;

  /// `⋯` 차림표에 'ClearType' 줄을 보일 것인가 — 켜 볼 수 있는 때(Windows · Windows 설정 켬 · 굽개 있음)만.
  static bool get shown => Platform.isWindows && system.on && bakerReady;

  /// 기억에서 읽는다. 담긴 것이 없거나 false가 아니면 켬(기본).
  static void load(AppMemory m) => loadPart(m.parts['text']);

  /// 기억의 `parts['text']` 칸에서 읽는다 — 기억을 열기 전에 [AppMemory.readPart]로 먼저 읽은 것도.
  static void loadPart(Map<String, dynamic>? text) => on = text?['clearType'] != false;

  /// 사용자가 고른 값을 적용하고 기억에 남긴다. 같은 칸의 다른 열쇠는 그대로 둔다.
  static void save(AppMemory m, bool value) {
    on = value;
    m.parts['text'] = {...?m.parts['text'], 'clearType': value};
    m.save();
  }

  /// 명령줄 `--cleartype=off`: 검증 대본이 회색 그림을 얻으려는 것이라 기억에는 쓰지 않는다. 그 밖의 값은 무시한다.
  static void applyOption(String? value) {
    if (value == 'off') on = false;
  }
}

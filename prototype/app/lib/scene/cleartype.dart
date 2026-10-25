import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'fonts.dart';
import 'text_paragraph.dart';

// ClearType 글자(설계 docs/설계-한벌-체제-목업판-ClearType.md 3-2 · 계획 P2 과제 2): 자료 처리부의 archive_glyphs를 따로 띄운 isolate에서 불러
// 글자마다 ClearType 3x1 덮임을 받는다. 엔진 작업자의 isolate와 줄을 서지 않고, 저장소도 잡지 않는다.

/// 구운 글자 하나. [left] · [top]은 펜(정수 화소) · 바탕선에서 덮임 왼쪽 위까지의 화면 px. [cov]는 화소마다 빨강 · 초록 · 파랑(0~255).
class LcdGlyph {
  const LcdGlyph(this.rune, this.ok, this.left, this.top, this.width, this.height, this.advance, this.cov);
  final int rune;
  final bool ok;
  final int left, top, width, height;
  final double advance;
  final Uint8List cov;
}

/// archive_glyphs의 답("HTGL" 판 1)을 읽는다. 꼴이 틀리거나 잘렸으면 [FormatException].
List<LcdGlyph> parseGlyphs(Uint8List b) {
  if (b.length < 8 || String.fromCharCodes(b.sublist(0, 4)) != 'HTGL') throw const FormatException('글자 답의 머리가 아닙니다');
  final d = ByteData.sublistView(b);
  final n = d.getUint16(6, Endian.little);
  var p = 8;
  final out = <LcdGlyph>[];
  for (var i = 0; i < n; i++) {
    if (p + 18 > b.length) throw const FormatException('글자 답이 잘렸습니다');
    final rune = d.getUint32(p, Endian.little), ok = d.getUint8(p + 5) != 0;
    final left = d.getInt16(p + 6, Endian.little), top = d.getInt16(p + 8, Endian.little);
    final w = d.getUint16(p + 10, Endian.little), h = d.getUint16(p + 12, Endian.little);
    final adv = d.getFloat32(p + 14, Endian.little);
    p += 18;
    final len = w * h * 3;
    if (p + len > b.length) throw const FormatException('글자 덮임이 잘렸습니다');
    out.add(LcdGlyph(rune, ok, left, top, w, h, adv, Uint8List.fromList(b.sublist(p, p + len))));
    p += len;
  }
  return out;
}

/// 글자를 굽는 쪽의 약속. 그리는 쪽은 이것만 알아서, 검사에서 가짜로 바꿔 끼울 수 있다.
abstract class GlyphBaker {
  Future<List<LcdGlyph>> bake(String font, double sizePx, List<int> runes);
}

/// 자료 처리부 {"op":"cleartype"}의 답: 화면에 ClearType이 켜져 있는가 · 부화소가 파랑이 앞인가.
class ClearTypeInfo {
  const ClearTypeInfo(this.on, this.bgr);
  final bool on, bgr;
  static ClearTypeInfo read(Map<String, dynamic> answer) {
    final d = answer['ok'] == true ? answer['data'] as Map? : null;
    return ClearTypeInfo(d?['on'] == true, d?['bgr'] == true);
  }
}

class ClearTypeBaker implements GlyphBaker {
  ClearTypeBaker._(this.library);
  final String library;

  /// Windows가 아니거나 자료 처리부에 archive_glyphs가 없으면 null(그때 앱은 회색 그대로).
  static ClearTypeBaker? open([String? library]) {
    if (!Platform.isWindows) return null;
    final path = library ?? '${File(Platform.resolvedExecutable).parent.path}/archive_engine.dll';
    try {
      final lib = DynamicLibrary.open(path);
      if (!lib.providesSymbol('archive_glyphs')) return null;
    } catch (_) {
      return null;
    }
    return ClearTypeBaker._(path);
  }

  @override
  Future<List<LcdGlyph>> bake(String font, double sizePx, List<int> runes) {
    final request = jsonEncode({'font': font, 'size': sizePx, 'glyphs': [for (final r in runes) {'rune': r, 'phase': 0}]});
    final library = this.library;
    return Isolate.run(() => parseGlyphs(_bakeNow(library, request)));
  }
}

/// 따로 띄운 isolate 안에서 DLL을 열어 한 번 굽는다. 실패하면(null 답) [StateError].
Uint8List _bakeNow(String library, String request) {
  final lib = DynamicLibrary.open(library);
  final bake = lib.lookupFunction<Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Size>), Pointer<Uint8> Function(Pointer<Utf8>, Pointer<Size>)>('archive_glyphs');
  final free = lib.lookupFunction<Void Function(Pointer<Uint8>, Size), void Function(Pointer<Uint8>, int)>('archive_free_bytes');
  final input = request.toNativeUtf8();
  final len = calloc<Size>();
  try {
    final ptr = bake(input, len);
    if (ptr == nullptr) throw StateError('글자를 굽지 못했습니다');
    try {
      return Uint8List.fromList(ptr.asTypedList(len.value));
    } finally {
      free(ptr, len.value);
    }
  } finally {
    malloc.free(input);
    calloc.free(len);
  }
}

/// 장면 글자의 글꼴 파일(프리텐다드 400 · 600 · 700). 화면 글꼴이 프리텐다드가 아니거나 · 기울임이거나 · 파일이 없으면 null.
/// [root]의 기본은 실행 파일 곁의 `data/flutter_assets/assets/fonts`.
String? sceneFontFile(TextLook look, {String? root}) {
  if (sceneFamilyNow != sceneFontFamily || look.italic) return null;
  final name = switch (look.weight.value) { >= 650 => 'Pretendard-Bold.otf', >= 550 => 'Pretendard-SemiBold.otf', _ => 'Pretendard-Regular.otf' };
  final base = root ?? '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/fonts';
  final file = File('$base/$name');
  return file.existsSync() ? file.absolute.path : null;
}

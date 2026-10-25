// 원어 병기 · 글꼴(10건 3 · 9 — 감독 선택 D2 · 갈래 D2의 새 앱 몫)의 판정 표 — 그릴 수 있는 글자 범위.
// 웹 js/core.js의 '원어 표기 · 글자 범위 표 · 글꼴 팩' 덩어리(HT.GLYPH_BAND · GLYPH_WINDOW · BAND_NEVER · SCRIPT_RANGES · fontRanges ·
// glyphTables · glyphMissing · missingScriptName)와 같은 범위 · 같은 답이다(설계 docs/설계-10건/3-9-원어와-글꼴.md 7-6).
//
// 새 앱은 내장 표로 판정한 결과를 **내보내기가 미리 실어 온다**: 이름마다 내장 창 표에 없는 글자(`mw`) · 내장 띠 표에 없는 글자(`mb`)의
// 코드 포인트 목록(빈 목록은 싣지 않음 — 곧 '그릴 수 있음'). 그래서 이 파일은 내장 표 둘을 다시 갖지 않고, **켜진 글꼴 팩이 덮는 범위**로
// 그 목록만 다시 본다 — 목록의 글자가 모두 팩의 범위에 들면 그린다. 띠(글자 그림판)에는 그림판이 그릴 수 없는 범위([bandNever] —
// 결합 부호 · 오른쪽에서 왼쪽 · 이어 쓰는 문자 · 옛한글 자모 …)를 뺀 팩 범위만 더한다(아랍 글꼴 팩이어도 띠 표에 아랍을 넣지 않는다).
//
// [SceneNames]는 장면마다 하나 — 왼쪽 줄 이름 칸(paint/gutter.dart)이 '원어: 왼쪽 칸에도' · 띠에 더할 팩 범위를 읽는다.
// 값은 앱 쪽(ui/names_display.dart의 NamesGlue)이 표기 설정 · 켜진 글꼴이 바뀔 때 적고 장면을 다시 그리게 한다.

/// 글자 범위 하나(끝 포함).
typedef GlyphRange = (int, int);

/// 범위 목록 → 겹치거나 이어진 범위를 합친 차례 목록.
List<GlyphRange> mergeRanges(Iterable<GlyphRange> list) {
  final sorted = [for (final r in list) if (r.$1 <= r.$2) r]..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <GlyphRange>[];
  for (final r in sorted) {
    if (out.isNotEmpty && r.$1 <= out.last.$2 + 1) {
      final last = out.removeLast();
      out.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
    } else {
      out.add(r);
    }
  }
  return out;
}

/// 범위 목록 [a]에서 [b]의 범위를 뺀 목록.
List<GlyphRange> subtractRanges(Iterable<GlyphRange> a, Iterable<GlyphRange> b) {
  var cur = mergeRanges(a);
  for (final (lo, hi) in b) {
    final next = <GlyphRange>[];
    for (final (x, y) in cur) {
      if (y < lo || x > hi) {
        next.add((x, y));
      } else {
        if (x < lo) next.add((x, lo - 1));
        if (y > hi) next.add((hi + 1, y));
      }
    }
    cur = next;
  }
  return cur;
}

/// 차례 목록(합친 것)에 그 글자가 있는가 — 반 가르기.
bool inRanges(List<GlyphRange> table, int cp) {
  var lo = 0, hi = table.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final r = table[mid];
    if (cp < r.$1) {
      hi = mid - 1;
    } else if (cp > r.$2) {
      lo = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// 글꼴 팩이 있어도 띠 표에는 넣지 않는 범위 — 웹 core.js의 BAND_NEVER 그대로.
/// 그림판은 글자를 하나씩 왼쪽에서 오른쪽으로 놓을 뿐이라(scene/glyph_atlas.dart — 이음 글자 없음) 그리지 못한다.
const List<GlyphRange> bandNever = [
  (0x300, 0x36f), (0x483, 0x489), (0x590, 0x8ff), (0x900, 0xdff), (0xe00, 0xeff), (0xf00, 0xfff), (0x1000, 0x109f), (0x1100, 0x11ff), (0x1780, 0x18af),
  (0x1ab0, 0x1aff), (0x1dc0, 0x1dff), (0x200b, 0x200f), (0x202a, 0x202e), (0x2060, 0x206f), (0x20d0, 0x20ff), (0xa960, 0xa97f), (0xd7b0, 0xd7ff),
  (0xfb1d, 0xfdff), (0xfe00, 0xfe0f), (0xfe20, 0xfe2f), (0xfe70, 0xfeff), (0x10800, 0x10fff), (0x1e800, 0x1efff), (0xe0100, 0xe01ef),
];

/// 글꼴이 덮는 범위를 밝히지 않았을 때(`ranges` 없음) 문자 꼬리표(ISO 15924)마다의 기본 범위 — 웹 HT.SCRIPT_RANGES 그대로.
/// 가상 문자(Qaaa~Qabx) · 한자 확장 · 옛한글은 기본 범위가 없어 `ranges`로 적어야 '있음'이 된다.
const Map<String, List<GlyphRange>> scriptRanges = {
  'Latn': [(0x20, 0x7e), (0xa0, 0x24f), (0x2b0, 0x2ff), (0x1e00, 0x1eff)],
  'Grek': [(0x370, 0x3ff), (0x1f00, 0x1fff)],
  'Cyrl': [(0x400, 0x4ff)],
  'Armn': [(0x530, 0x58f)],
  'Hebr': [(0x590, 0x5ff)],
  'Arab': [(0x600, 0x6ff), (0x750, 0x77f), (0x8a0, 0x8ff)],
  'Syrc': [(0x700, 0x74f)],
  'Deva': [(0x900, 0x97f)],
  'Beng': [(0x980, 0x9ff)],
  'Thai': [(0xe00, 0xe7f)],
  'Laoo': [(0xe80, 0xeff)],
  'Tibt': [(0xf00, 0xfff)],
  'Mymr': [(0x1000, 0x109f)],
  'Geor': [(0x10a0, 0x10ff)],
  'Ethi': [(0x1200, 0x137f)],
  'Khmr': [(0x1780, 0x17ff)],
  'Mong': [(0x1800, 0x18af)],
  'Hang': [(0x3130, 0x318f), (0xac00, 0xd7a3)],
  'Hira': [(0x3040, 0x309f)],
  'Kana': [(0x30a0, 0x30ff)],
  'Hani': [(0x4e00, 0x9fff)],
  'Hans': [(0x4e00, 0x9fff)],
  'Hant': [(0x4e00, 0x9fff)],
  'Jpan': [(0x3040, 0x30ff), (0x4e00, 0x9fff)],
  'Kore': [(0x3130, 0x318f), (0xac00, 0xd7a3), (0x4e00, 0x9fff)],
};

final _rangeText = RegExp(r'^\s*U\+([0-9A-F]{1,6})\s*(?:[-–~]\s*(?:U\+)?([0-9A-F]{1,6}))?\s*$', caseSensitive: false);

/// 글자 범위 글 → 범위: `U+F1A00-F1A0B` · `U+4E00`(끝 포함 · 끝 쪽의 U+는 빼도 됨). 꼴이 틀리면 null — 웹 HT.parseRange.
GlyphRange? parseRange(String text) {
  final m = _rangeText.firstMatch(text);
  if (m == null) return null;
  final lo = int.parse(m[1]!, radix: 16);
  final hi = m[2] == null ? lo : int.parse(m[2]!, radix: 16);
  return lo <= hi && hi <= 0x10ffff ? (lo, hi) : null;
}

/// 글꼴 하나가 덮는 범위 — 적은 `ranges`, 없으면 `scripts`마다의 기본 범위(웹 HT.fontRanges).
List<GlyphRange> fontRanges({List<String> ranges = const [], List<String> scripts = const []}) {
  if (ranges.isNotEmpty) return mergeRanges([for (final r in ranges) ?parseRange(r)]);
  return mergeRanges([for (final s in scripts) ...?scriptRanges[s]]);
}

/// 화면 글꼴로 쓸 수 있는 글꼴인가 — 한글 음절 전부(AC00–D7A3)를 덮어야 한다(웹 HT.fontHasHangul).
bool coversHangul(List<GlyphRange> ranges) => ranges.any((r) => r.$1 <= 0xac00 && 0xd7a3 <= r.$2);

/// 켜진 글꼴들이 덮는 범위 → 창 표에 더할 것 · 띠 표에 더할 것(그림판이 그릴 수 없는 범위를 뺀 것).
({List<GlyphRange> window, List<GlyphRange> band}) packExtras(Iterable<List<GlyphRange>> fonts) {
  final all = mergeRanges([for (final f in fonts) ...f]);
  return (window: all, band: subtractRanges(all, bandNever));
}

/// 미리 실려 온 '내장 표에 없는 글자' 가운데 켜진 팩의 범위([extra])로도 덮이지 않는 것(나온 차례).
List<int> stillMissing(List<int> missing, List<GlyphRange> extra) => [for (final cp in missing) if (!inRanges(extra, cp)) cp];

/// 내보내기의 코드 포인트 목록(`mw` · `mb` — 없으면 빈 목록).
List<int> codePoints(Object? v) => [if (v is List) for (final x in v) if (x is num) x.toInt()];

/// 없는 글자가 어떤 문자인가 — '글꼴 없음' 딱지의 말(첫째 없는 글자로 · 웹 HT.missingScriptName과 같은 표).
const List<(String, List<GlyphRange>)> _missingNames = [
  ('가상 문자', [(0xe000, 0xf8ff), (0xf0000, 0x10ffff)]),
  ('한자 확장 글자', [(0x3400, 0x4dbf), (0xf900, 0xfaff), (0x20000, 0x3ffff)]),
  ('옛한글', [(0x1100, 0x11ff), (0xa960, 0xa97f), (0xd7b0, 0xd7ff)]),
  ('아랍 문자', [(0x600, 0x6ff), (0x750, 0x77f), (0x8a0, 0x8ff), (0xfb50, 0xfdff), (0xfe70, 0xfeff)]),
  ('히브리 문자', [(0x590, 0x5ff), (0xfb1d, 0xfb4f)]),
  ('결합 부호', [(0x300, 0x36f), (0x1ab0, 0x1aff), (0x1dc0, 0x1dff), (0x20d0, 0x20ff), (0xfe20, 0xfe2f)]),
  ('인도계 문자', [(0x900, 0xdff)]),
  ('타이 문자', [(0xe00, 0xe7f)]),
  ('티베트 문자', [(0xf00, 0xfff)]),
  ('몽골 문자', [(0x1800, 0x18af)]),
];

String missingScriptName(List<int> missing) {
  if (missing.isEmpty) return '';
  final cp = missing.first;
  for (final (name, ranges) in _missingNames) {
    if (ranges.any((r) => r.$1 <= cp && cp <= r.$2)) return name;
  }
  return '이 문자';
}

/// 장면마다의 표기 상태 — 왼쪽 줄 이름 칸이 읽는다(지도자 표기 · 대수가 SceneMarks로 가는 것과 같은 길이지만 이 갈래의 값만 따로 둔다).
class SceneNames {
  static final _byScene = Expando<SceneNames>('원어 표기');
  static SceneNames of(Object scene) => _byScene[scene] ??= SceneNames();

  /// '원어: 왼쪽 칸에도' + 적용 '나라' — 웹 viewer.js `origFn`이 함수를 넘기는 때. 거짓이면 줄 이름 칸은 지금 그대로.
  bool origBand = false;

  /// 켜진 글꼴 팩이 덮는 범위 가운데 띠(글자 그림판)에 그릴 수 있는 것 — [packExtras]의 band.
  List<GlyphRange> bandExtra = const [];

  /// 바뀔 때마다 오른다 — 적는 쪽이 올리고 장면에 다음 장면을 청한다.
  int version = 0;
}

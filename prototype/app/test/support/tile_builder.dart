import 'dart:convert';
import 'dart:typed_data';

// 검사용 타일 만들기. 자료 처리부의 부호화(engine/src/tile.rs의 encode)와 같은 약속으로 2판 바이트를 짠다.
// 구역 표를 두고, 구역마다 '열 × 항목'의 4바이트 배열을 잇는다(계약 5절).
class TileBuilder {
  TileBuilder({required this.level, required this.x, required this.chunk});
  final int level, x, chunk;
  final _strings = <String>[];
  final _bands = <List<num>>[], _cells = <List<num>>[], _events = <List<num>>[], _pills = <List<num>>[];

  /// 일반 구역(16 이상): 구역 번호 → 항목들.
  final _items = <int, List<List<num>>>{};

  static const bandColumns = 10, cellColumns = 9, eventColumns = 10, pillColumns = 4, itemColumns = 14;

  int get span => 256 * (1 << (2 * level));
  int get origin => x * span;

  int _name(String text) {
    if (text.isEmpty) return 0xFFFFFFFF;
    final at = _strings.indexOf(text);
    if (at >= 0) return at;
    _strings.add(text);
    return _strings.length - 1;
  }

  /// [x0] · [x1]은 타일 시작에서 잰 분. [form]은 스키마 4의 열 10(값은 계약 6-1 가 비트 — 0 = 모름 · 열 자리는 계약 5절 띠 행).
  void band(int id, int row, double x0, double x1, String name,
          {int color = 0xa0bcc5, int flags = 0, int look = 0, String tag = '', int sub = 0, int form = 0}) =>
      _bands.add([x0, x1, id, color, _name(name), row, flags, look, _name(tag), sub, form]);

  void cell(int id, int row, double x0, double x1, String name,
          {int kind = 1, int flags = 0, int lane = 0, int style = 0, int color = 0}) =>
      _cells.add([x0, x1, id, _name(name), row, kind | flags << 8, lane, style, color]);

  void event(int id, int row, double x0, String name,
          {double? x1, int bits = 33, int look = 0, String label = '', int rail = 0, int band = 0}) =>
      _events.add([x0, x1 ?? x0, id, _name(name), row, bits, look, _name(label), rail, band]);

  void pill(int row, double x0, double x1, int count) => _pills.add([x0, x1, count, row]);

  /// 일반 구역의 항목 하나(뜻은 계약 6절 — 자료 처리부도 화면도 뜻을 모른 채 실어 나른다).
  void item(int section, int id, int row, double x0, double x1,
      {int row2 = -1, int flags = 0, String name = '', int ref = 0, int color = 0,
      int a = 0, int b = 0, int c = 0, int d = 0, String text2 = ''}) {
    if (section < 16) throw ArgumentError('일반 구역의 번호는 16 이상입니다: $section');
    _items.putIfAbsent(section, () => []).add([x0, x1, id, _name(name), row, flags, row2 < 0 ? row : row2, ref, color, a, b, c, d, _name(text2)]);
  }

  Uint8List build() {
    // 자료 처리부와 같은 약속: 사건은 (줄, 시각, 번호) 순.
    _events.sort((a, b) {
      final row = a[4].compareTo(b[4]);
      if (row != 0) return row;
      final at = a[0].compareTo(b[0]);
      return at != 0 ? at : a[2].compareTo(b[2]);
    });
    // 알약도 (줄, 시각) 순. 알약의 줄은 넷째 값.
    _pills.sort((a, b) {
      final row = a[3].compareTo(b[3]);
      return row != 0 ? row : a[0].compareTo(b[0]);
    });
    // 띠의 form(열 10)은 form≠0인 띠가 하나라도 있을 때만 싣는다 — 계약 5절 띠 행(엔진 tile.rs와 같은 규칙 — BAND_FORM_COLUMNS ·
    // band_columns) — 진짜 엔진 대조 schema4_real_engine_test가 지킴.
    // 없으면 지금처럼 10열이고, 읽는 쪽은 없는 열을 0 배열(모름)로 받는다.
    final bandWidth = _bands.any((b) => b[10] != 0) ? bandColumns + 1 : bandColumns;
    // 빈 구역은 싣지 않는다(없는 구역과 빈 구역은 읽는 쪽에서 같다). 구역 번호는 오름차순.
    final table = <(int, List<List<num>>, int)>[
      if (_bands.isNotEmpty) (1, _bands, bandWidth),
      if (_cells.isNotEmpty) (2, _cells, cellColumns),
      if (_events.isNotEmpty) (3, _events, eventColumns),
      if (_pills.isNotEmpty) (4, _pills, pillColumns),
      for (final kind in _items.keys.toList()..sort())
        if (_items[kind]!.isNotEmpty) (kind, _items[kind]!, itemColumns),
    ];
    final text = [for (final s in _strings) utf8.encode(s)];
    final textBytes = text.fold<int>(0, (n, b) => n + b.length);
    final dataWords = table.fold<int>(0, (n, s) => n + s.$2.length * s.$3);
    final words = table.length * 4 + dataWords + _strings.length + 1;
    final bytes = Uint8List(((72 + words * 4 + textBytes + 3) ~/ 4) * 4);
    final data = ByteData.sublistView(bytes)
      ..setUint32(0, 0x32545448, Endian.little)
      ..setUint16(4, 2, Endian.little)
      ..setInt32(8, level, Endian.little)
      ..setInt32(12, chunk, Endian.little)
      ..setInt64(16, x, Endian.little)
      ..setInt64(24, origin, Endian.little)
      ..setInt64(32, span, Endian.little)
      ..setUint32(40, table.length, Endian.little)
      ..setUint32(44, _strings.length, Endian.little)
      ..setUint32(48, textBytes, Endian.little);
    int at = 72;
    int offsetWords = 72 ~/ 4 + 4 * table.length;
    for (final (kind, items, columns) in table) {
      data
        ..setUint32(at, kind, Endian.little)
        ..setUint32(at + 4, items.length, Endian.little)
        ..setUint32(at + 8, columns, Endian.little)
        ..setUint32(at + 12, offsetWords, Endian.little);
      at += 16;
      offsetWords += items.length * columns;
    }
    // 배열의 구조체: 같은 자리의 값끼리 한 줄로. 앞의 둘(x0 · x1)은 f32, 나머지는 u32.
    for (final (_, items, columns) in table) {
      for (int column = 0; column < columns; column++) {
        for (final item in items) {
          if (column < 2) {
            data.setFloat32(at, item[column].toDouble(), Endian.little);
          } else {
            data.setUint32(at, item[column].toInt(), Endian.little);
          }
          at += 4;
        }
      }
    }
    int offset = 0;
    for (final b in text) {
      data.setUint32(at, offset, Endian.little);
      offset += b.length;
      at += 4;
    }
    data.setUint32(at, offset, Endian.little);
    at += 4;
    for (final b in text) {
      bytes.setRange(at, at + b.length, b);
      at += b.length;
    }
    return bytes;
  }
}

import 'dart:convert';
import 'dart:typed_data';

// 자료 처리부가 만든 이진 타일(2판)을 읽는다. 약속은 engine/src/tile.rs와 docs/계약-아카이브-3단계.md 5절.
// 값을 객체로 풀지 않고 받은 바이트 위에 배열 보기만 얹는다 — 장면마다 같은 종류의 값을 한 줄로 훑기 위해서다.
//
// 2판은 굳은 열 대신 **구역 표**를 둔다: 머리 뒤에 (구역 종류 · 항목 수 · 열 수 · 자리)의 표가 오고, 구역마다
// '열 × 항목'의 4바이트 배열이 이어진다. 아는 구역 · 아는 열만 읽고 모르는 것은 건너뛴다 → 묶음을 하나 옮길 때마다
// 자료 처리부가 열을 더해도 앞 묶음의 읽기가 깨지지 않는다.

/// 구역 하나. 없는 구역은 빈 구역(항목 0개), 없는 열은 0으로 찬 배열이다.
class TileSection {
  TileSection._(this.kind, this.count, this.columns, this._buffer, this._byteOffset)
    : _cache = List<TypedData?>.filled(columns * 2, null);

  /// 없는 구역.
  static final TileSection none = TileSection._(0, 0, 0, Uint8List(0).buffer, 0);

  final int kind, count, columns;
  final ByteBuffer _buffer;
  final int _byteOffset;
  final List<TypedData?> _cache;

  /// [col]번째 열을 소수(f32)로. 열 0 · 1(x0 · x1)이 소수다.
  Float32List f(int col) {
    if (col >= columns || count == 0) return Float32List(count);
    return (_cache[col * 2] ??= Float32List.view(_buffer, _byteOffset + col * count * 4, count)) as Float32List;
  }

  /// [col]번째 열을 정수(u32)로.
  Uint32List u(int col) {
    if (col >= columns || count == 0) return Uint32List(count);
    return (_cache[col * 2 + 1] ??= Uint32List.view(_buffer, _byteOffset + col * count * 4, count)) as Uint32List;
  }
}

class Tile {
  Tile._(this._bytes, this._textAt, this._textBase, this._sections, ByteData head)
    : level = head.getInt32(8, Endian.little),
      chunk = head.getInt32(12, Endian.little),
      x = head.getInt64(16, Endian.little),
      origin = head.getInt64(24, Endian.little),
      span = head.getInt64(32, Endian.little);

  static const magic = 0x32545448; // "HTT2"
  static const version = 2;
  static const headerBytes = 72;
  static const sectionEntryWords = 4;
  static const noName = 0xFFFFFFFF;

  /// 구역 번호. 16 이상은 일반 구역(뜻은 계약 6절).
  static const secBand = 1, secCell = 2, secEvent = 3, secPill = 4, secGeneral = 16;

  /// 띠 · 칸의 표시
  static const clipLeft = 1, clipRight = 2, fuzzyStart = 4, fuzzyEnd = 8;

  /// 사건의 표시(아래 2비트는 중요도)
  static const bar = 4, eventClipLeft = 8, eventClipRight = 16, counted = 32;

  final Uint8List _bytes;
  final Uint32List _textAt;
  final int _textBase;
  final Map<int, TileSection> _sections;
  late final List<String?> _texts = List.filled(_textAt.length - 1, null);

  final int level, chunk, x;

  /// 타일의 시작(분)과 너비(분). 가로 값 x0 · x1은 시작에서 잰 분이다.
  final int origin, span;

  /// [kind]번 구역. 없으면 빈 구역이다.
  TileSection section(int kind) => _sections[kind] ?? TileSection.none;

  /// 이 타일에 든 구역 번호들(오름차순) — 일반 구역을 훑을 때 쓴다.
  late final List<int> sectionKinds = _sections.keys.toList()..sort();

  late final TileSection _bands = section(secBand);
  late final TileSection _cells = section(secCell);
  late final TileSection _events = section(secEvent);
  late final TileSection _pills = section(secPill);

  // ---- 띠(구역 1): x0 · x1 · id · color · name · row · flags ‖ look · tag · sub
  //      ‖ form(스키마 4 · 열 10 — 계약 5절 띠 행 · 아래 bandForm. 없으면 0 배열 = 모름) ----
  late final Float32List bandX0 = _bands.f(0), bandX1 = _bands.f(1);
  late final Uint32List bandId = _bands.u(2), bandColor = _bands.u(3), bandName = _bands.u(4), bandRow = _bands.u(5), bandFlags = _bands.u(6);
  late final Uint32List bandLook = _bands.u(7), bandTag = _bands.u(8), bandSub = _bands.u(9);

  /// 형식 4의 종류 · 관계 · 정통성 · 중요도를 담은 비트(계약 6-1 가의 비트 표 — 풀기는 band_form.dart의 BandForm).
  /// 열 10이 없는 타일(옛 타일 등)에서는 띠 수만큼의 0이 온다. 그림은 이 값을 보지 않는다(4단계).
  ///
  /// 타일에서의 자리는 계약 5절 띠 행(엔진 tile.rs와 같은 규칙) — 진짜 엔진 대조 schema4_real_engine_test가 지킴: 띠 구역의 열 10,
  /// 그 타일에 form ≠ 0인 띠가 하나라도 있을 때만 11열(엔진 `BAND_FORM_COLUMNS` · `band_columns` — 알약 구역 cats 열의 `pill_columns`와
  /// 같은 규칙이라 form이 없는 옛 저장소의 타일은 바이트까지 예전과 같다). 이 읽개는 열이 없으면 조용히 0을 주므로 손으로 짠 타일로는
  /// 엔진이 다른 자리에 싣는 어긋남을 못 잡는다 — 그래서 진짜 엔진 답과의 대조(계획 과제 8 걸음 5)가 따로 있다.
  late final Uint32List bandForm = _bands.u(10);

  // ---- 칸(구역 2): x0 · x1 · id · name · row · kind ‖ lane · style · color ----
  late final Float32List cellX0 = _cells.f(0), cellX1 = _cells.f(1);
  late final Uint32List cellId = _cells.u(2), cellName = _cells.u(3), cellRow = _cells.u(4);

  /// 아래 8비트는 종류(0 왕조 · 1 지도자 · 2 내각 · 3 기관 …), 그 위는 잘림 표시.
  late final Uint32List cellKind = _cells.u(5);
  late final Uint32List cellLane = _cells.u(6), cellStyle = _cells.u(7), cellColor = _cells.u(8);

  // ---- 사건(구역 3): x0 · x1 · id · name · row · bits ‖ look · label · rail · band ----
  late final Float32List eventX0 = _events.f(0), eventX1 = _events.f(1);
  late final Uint32List eventId = _events.u(2), eventName = _events.u(3), eventRow = _events.u(4), eventBits = _events.u(5);
  late final Uint32List eventLook = _events.u(6), eventLabel = _events.u(7), eventRail = _events.u(8);

  /// 그 사건이 든 띠의 번호(없으면 0) — 점 색 · 이름 가두기 · 묶기가 모두 이 띠 안에서 일어난다.
  late final Uint32List eventBand = _events.u(9);

  // ---- 알약(구역 4): x0 · x1 · count · row ----
  late final Float32List pillX0 = _pills.f(0), pillX1 = _pills.f(1);

  /// 그 통에서 대표를 뺀 나머지 개수.
  late final Uint32List pillRest = _pills.u(2), pillRow = _pills.u(3);

  // ---- 장면이 적어 두는 것(타일의 자료에서 한 번 셈하면 바뀌지 않는 값). NaN = 아직 셈하지 않음 ----
  /// 사건 이름의 폭(px, 돋보기 100% 기준). 폭은 배율과 무관해서, 확대할 때마다 다시 재지 않는다.
  late final Float32List eventNameWidth = Float32List(eventCount)..fillRange(0, eventCount, double.nan);

  /// 사건이 든 띠의 범위(타일 안의 분). 끝을 모르면(타일 경계에서 잘림 · 띠 밖) ±무한.
  late final Float64List eventBandLo = Float64List(eventCount)..fillRange(0, eventCount, double.nan);
  late final Float64List eventBandHi = Float64List(eventCount)..fillRange(0, eventCount, double.nan);

  /// 긴 기간 막대인 사건의 번호들 — 그리는 쪽이 장면마다 사건 전부를 훑지 않게 따로 짚어 둔다.
  late final Int32List barIndices = Int32List.fromList([for (int i = 0; i < eventCount; i++) if (isBar(i)) i]);

  // 자료 처리부는 사건과 알약을 (줄, 시각) 순으로 보낸다 → 줄마다의 구간에서 시각으로 이분 검색할 수 있다.
  late final _RowIndex _eventRows = _RowIndex(eventRow, eventX0), _pillRows = _RowIndex(pillRow, pillX0);

  /// [row] 줄에서 시작 시각(타일 안의 분)이 [from] 이상 [to] 이하인 사건의 범위 [처음, 끝).
  /// 타일 하나에 사건이 8천 개까지 들어 있어도(1,000만 건) 보이는 것만 짚는다.
  (int, int) eventsIn(int row, double from, double to) => _eventRows.range(row, from, to);

  /// 같은 방식으로, 통의 시작이 범위 안에 든 알약.
  (int, int) pillsIn(int row, double from, double to) => _pillRows.range(row, from, to);

  int get byteLength => _bytes.length;
  int get bandCount => _bands.count;
  int get cellCount => _cells.count;
  int get eventCount => _events.count;
  int get pillCount => _pills.count;
  int get stringCount => _texts.length;

  int cellKindOf(int i) => cellKind[i] & 0xff;
  int cellFlagsOf(int i) => cellKind[i] >> 8;
  int importanceOf(int i) => eventBits[i] & 3;
  bool isBar(int i) => eventBits[i] & bar != 0;
  bool isCounted(int i) => eventBits[i] & counted != 0;

  /// 일반 구역(16 이상)의 항목 하나를 짚는 데 쓰는 열 번호.
  static const itemX0 = 0, itemX1 = 1, itemId = 2, itemName = 3, itemRow = 4, itemFlags = 5,
      itemRow2 = 6, itemRef = 7, itemColor = 8, itemA = 9, itemB = 10, itemC = 11, itemD = 12, itemText2 = 13;

  /// 글자는 처음 물을 때만 풀고 타일이 기억한다.
  String text(int index) {
    if (index == noName || index >= _texts.length) return '';
    return _texts[index] ??= utf8.decode(
      Uint8List.sublistView(
        _bytes,
        _textBase + _textAt[index],
        _textBase + _textAt[index + 1],
      ),
    );
  }

  factory Tile.decode(Uint8List input) {
    // 배열 보기는 4바이트 경계에서만 만들 수 있다. 어긋나게 놓인 바이트는 한 번 베낀다.
    final bytes = input.offsetInBytes % 4 == 0
        ? input
        : Uint8List.fromList(input);
    if (bytes.length < headerBytes) throw const FormatException('타일 머리가 모자랍니다');
    final head = ByteData.sublistView(bytes, 0, headerBytes);
    if (head.getUint32(0, Endian.little) != magic ||
        head.getUint16(4, Endian.little) != version) {
      throw const FormatException('타일 표지 또는 판이 다릅니다');
    }
    final sectionCount = head.getUint32(40, Endian.little),
        strings = head.getUint32(44, Endian.little),
        textBytes = head.getUint32(48, Endian.little);
    final words = bytes.length ~/ 4;
    final tableAt = headerBytes ~/ 4;
    if (tableAt + sectionEntryWords * sectionCount > words) {
      throw const FormatException('구역 표가 타일 바깥을 가리킵니다');
    }
    final table = Uint32List.view(bytes.buffer, bytes.offsetInBytes + headerBytes, sectionEntryWords * sectionCount);
    final sections = <int, TileSection>{};
    // 글자표는 마지막 구역의 뒤에 온다(자료 처리부가 구역을 표 바로 뒤에 차례로 놓는다).
    int stringsAt = tableAt + sectionEntryWords * sectionCount;
    for (int i = 0; i < sectionCount; i++) {
      final kind = table[i * sectionEntryWords],
          count = table[i * sectionEntryWords + 1],
          columns = table[i * sectionEntryWords + 2],
          at = table[i * sectionEntryWords + 3];
      final end = at + count * columns;
      if (at < tableAt + sectionEntryWords * sectionCount || end > words) {
        throw const FormatException('구역 자료가 타일 바깥을 가리킵니다');
      }
      sections[kind] = TileSection._(kind, count, columns, bytes.buffer, bytes.offsetInBytes + at * 4);
      if (end > stringsAt) stringsAt = end;
    }
    final textBase = (stringsAt + strings + 1) * 4;
    if (stringsAt + strings + 1 > words || bytes.length < textBase + textBytes) {
      throw const FormatException('타일 바이트가 모자랍니다');
    }
    final offsets = Uint32List.view(bytes.buffer, bytes.offsetInBytes + stringsAt * 4, strings + 1);
    for (int i = 0; i < strings; i++) {
      if (offsets[i] > offsets[i + 1] || offsets[i + 1] > textBytes) {
        throw const FormatException('글자표의 자리가 범위 밖입니다');
      }
    }
    return Tile._(bytes, offsets, textBase, sections, head);
  }
}

/// (줄, 시각) 순으로 놓인 배열에서 줄마다의 구간을 짚어 두고, 그 안에서 시각으로 이분 검색한다.
class _RowIndex {
  _RowIndex(Uint32List rows, this._x0) : _count = rows.length {
    if (_count == 0) {
      _starts = Int32List(1);
      return;
    }
    _firstRow = rows[0];
    _starts = Int32List(rows[_count - 1] - _firstRow + 2);
    int row = _firstRow;
    for (int i = 0; i < _count; i++) {
      while (row < rows[i]) {
        _starts[++row - _firstRow] = i;
      }
    }
    _starts[_starts.length - 1] = _count;
  }

  final Float32List _x0;
  final int _count;
  late final Int32List _starts;
  int _firstRow = 0;

  /// 시각이 [from] 이상 [to] 이하인 것의 범위 [처음, 끝).
  (int, int) range(int row, double from, double to) {
    final r = row - _firstRow;
    if (_count == 0 || r < 0 || r + 1 >= _starts.length) return (0, 0);
    final end = _starts[r + 1];
    int lo = _starts[r], hi = end;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_x0[mid] < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final first = lo;
    hi = end;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_x0[mid] <= to) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return (first, lo);
  }
}

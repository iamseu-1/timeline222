// 스키마 4(docs/계약-아카이브-3단계.md 1-1절)가 타일에 더하는 칸 종류 · 칸 비트 · 일반 구역을 **받기만** 하는 자리.
// 값을 짓는 쪽은 내보내기 JS(prototype/scripts/export/strips.mjs의 KIND_OFFICE · ST_BORROW · SECTION.borrow · officeName,
// export/power.mjs의 SECTION_POWER_LINE)와 그 거울인 엔진이다. 4단계가 이 값을 그릴 때 여기서 읽어 쓴다(계획 정한 것 #14).
//
// 지금 그림판(paint/*)은 이 구역 · 종류 · 비트를 읽지 않는다 — strips.dart `_stripAt`이 종류 9를 (−1, 0)으로 버리고
// (layout.dart `RowGeo.strip`의 나머지 갈래), `CellStyle.bandOf`는 종류 8에서만 본다. 구역 54 ~ 56은 어느 그림도 찾지 않는다.
// 그래서 이 파일은 그림판을 import하지 않고, 그림판도 이 파일을 import하지 않는다.

import 'tile.dart';

/// 스키마 4의 상수와 타일 하나에서 읽어 주는 작은 읽개.
abstract final class Schema4 {
  /// 칸 종류 9 = **직위 줄 더**(셋째 직위 줄부터). 칸의 `lane`(아래 8비트) = 그 줄의 차례(0 ~).
  /// 8은 공용 칸 단(계약 6-9 가-D5)이 쓴다. 띠의 칸 층 셈(look 21 ~ 29) · 줄 높이에는 3단계에서 넣지 않는다.
  static const cellOfficeMore = 9;

  /// 칸 `style` 27비트 = **빌린 직위 줄의 칸**(`leadersFrom` · `cabinetsFrom` · `offices[].from` — 출처의 칸을 복제해 비트만 더함).
  /// 종류 1 · 2 · 9에서만 이 뜻이다. 종류 1에서는 29비트(명목 지도자)와 함께 설 수 있고, 순번(15 ~ 26비트)과 겹치지 않는다.
  static const borrowed = 1 << 27;

  /// 그 칸이 빌린 직위 줄의 칸인가. [kind]는 칸 종류 — 타일의 `cellKind` 값 그대로(위의 잘림 표시는 떼고 본다)나
  /// `Tile.cellKindOf`를 넘긴다. 종류 1(지도자) · 2(내각) · 9(직위 줄 더)에서만 참이 될 수 있다 —
  /// 종류 8(공용 칸 단)의 27 ~ 29비트는 단 갈래(`CellStyle.bandOf`)라 늘 거짓이다.
  static bool isBorrowed(int kind, int style) {
    final k = kind & 0xff;
    return (k == 1 || k == 2 || k == cellOfficeMore) && style & borrowed != 0;
  }

  /// 일반 구역 번호(계약 6-12 표): 54 빌린 직위 줄의 머리 글 · 55 직위 줄 더의 이름 · 56 실권 밑줄.
  static const secBorrowHead = 54, secOfficeName = 55, secPowerLine = 56;

  /// 타일 [t]에서 종류 9(직위 줄 더) 칸의 번호들(타일 칸 배열의 차례). 칸의 값은 `t.cellX0` · `t.cellLane` · `t.cellStyle` 같은
  /// 칸 배열 그대로 읽으면 되므로 따로 풀지 않는다.
  static List<int> officeMoreCells(Tile t) => [
    for (int i = 0; i < t.cellCount; i++)
      if (t.cellKindOf(i) == cellOfficeMore) i,
  ];

  /// 구역 54(빌린 직위 줄의 머리 글)의 항목들 — 타일에 실린 차례 그대로. 구역이 없으면 빈 목록.
  static List<BorrowHead> borrowHeads(Tile t) {
    final s = t.section(secBorrowHead);
    if (s.count == 0) return const [];
    final x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1);
    final id = s.u(Tile.itemId), ref = s.u(Tile.itemRef), row = s.u(Tile.itemRow), name = s.u(Tile.itemName);
    final a = s.u(Tile.itemA), b = s.u(Tile.itemB), text2 = s.u(Tile.itemText2);
    return List.unmodifiable([
      for (int i = 0; i < s.count; i++)
        BorrowHead(
          id: id[i],
          band: ref[i],
          row: row[i],
          x0: x0[i],
          x1: x1[i],
          source: t.text(name[i]),
          kind: a[i],
          lane: b[i],
          sourceUid: t.text(text2[i]),
        ),
    ]);
  }

  /// 구역 55(직위 줄 더의 이름)의 항목들 — 타일에 실린 차례 그대로. 구역이 없으면 빈 목록.
  static List<OfficeName> officeNames(Tile t) {
    final s = t.section(secOfficeName);
    if (s.count == 0) return const [];
    final id = s.u(Tile.itemId), ref = s.u(Tile.itemRef), row = s.u(Tile.itemRow), name = s.u(Tile.itemName), b = s.u(Tile.itemB);
    return List.unmodifiable([
      for (int i = 0; i < s.count; i++) OfficeName(id: id[i], band: ref[i], row: row[i], lane: b[i], name: t.text(name[i])),
    ]);
  }

  /// 구역 56(실권 밑줄)의 항목들 — 타일에 실린 차례 그대로. 구역이 없으면 빈 목록.
  static List<PowerLine> powerLines(Tile t) {
    final s = t.section(secPowerLine);
    if (s.count == 0) return const [];
    final x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1);
    final id = s.u(Tile.itemId), ref = s.u(Tile.itemRef), row = s.u(Tile.itemRow), name = s.u(Tile.itemName);
    final color = s.u(Tile.itemColor), a = s.u(Tile.itemA), text2 = s.u(Tile.itemText2);
    return List.unmodifiable([
      for (int i = 0; i < s.count; i++)
        PowerLine(
          id: id[i],
          band: ref[i],
          row: row[i],
          x0: x0[i],
          x1: x1[i],
          holder: t.text(name[i]),
          color: color[i],
          own: a[i] == 1,
          holderUid: t.text(text2[i]),
        ),
    ]);
  }
}

/// 구역 54 — 빌린 직위 줄의 머리 글(빌린 줄마다 하나 · 머리 줄 이름 뒤 `· 직위 ← 출처`).
final class BorrowHead {
  const BorrowHead({
    required this.id,
    required this.band,
    required this.row,
    required this.x0,
    required this.x1,
    required this.source,
    required this.kind,
    required this.lane,
    required this.sourceUid,
  });

  /// 항목 번호.
  final int id;

  /// 그 띠의 id(`ref`)와 줄.
  final int band, row;

  /// 띠의 구간(타일 시작에서 잰 분).
  final double x0, x1;

  /// 출처 글(`출처 이름/직위`).
  final String source;

  /// 빌린 줄의 칸 종류(`a` — 1 지도자 · 2 내각 · 9 직위 줄 더)와 직위 줄 더의 `lane`(`b` — 아니면 0).
  final int kind, lane;

  /// 출처 객체의 uid(`text2` — 출처를 못 찾았으면 빈 글).
  final String sourceUid;

  @override
  bool operator ==(Object other) =>
      other is BorrowHead &&
      other.id == id &&
      other.band == band &&
      other.row == row &&
      other.x0 == x0 &&
      other.x1 == x1 &&
      other.source == source &&
      other.kind == kind &&
      other.lane == lane &&
      other.sourceUid == sourceUid;

  @override
  int get hashCode => Object.hash(id, band, row, x0, x1, source, kind, lane, sourceUid);

  @override
  String toString() => 'BorrowHead(id: $id, band: $band, row: $row, x: $x0 ~ $x1, source: $source, kind: $kind, lane: $lane, uid: $sourceUid)';
}

/// 구역 55 — 직위 줄 더의 이름(줄마다 하나).
final class OfficeName {
  const OfficeName({required this.id, required this.band, required this.row, required this.lane, required this.name});

  /// 항목 번호.
  final int id;

  /// 그 띠의 id(`ref`)와 줄.
  final int band, row;

  /// 그 줄의 `lane`(`b`) — 같은 띠의 종류 9 칸의 `lane`과 같은 값.
  final int lane;

  /// 직위 이름.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is OfficeName && other.id == id && other.band == band && other.row == row && other.lane == lane && other.name == name;

  @override
  int get hashCode => Object.hash(id, band, row, lane, name);

  @override
  String toString() => 'OfficeName(id: $id, band: $band, row: $row, lane: $lane, name: $name)';
}

/// 구역 56 — 실권 밑줄(`power[].over` — 빼앗긴 쪽 띠에 · 그 기간마다 하나). `over` 없이 이름만인 줄(제 안의 실권자 —
/// 세도 가문 · 권신)은 제 띠에 실리고 [own]이 참이다.
final class PowerLine {
  const PowerLine({
    required this.id,
    required this.band,
    required this.row,
    required this.x0,
    required this.x1,
    required this.holder,
    required this.color,
    required this.own,
    required this.holderUid,
  });

  /// 항목 번호.
  final int id;

  /// 빼앗긴 띠의 id(`ref` — 제 안의 실권자는 제 띠)와 줄.
  final int band, row;

  /// 실권의 기간(빼앗긴 띠의 구간 안으로 자름 · 타일 시작에서 잰 분).
  final double x0, x1;

  /// 쥔 쪽 이름(제 안의 실권자는 그 줄의 이름).
  final String holder;

  /// 쥔 쪽 색(0xRRGGBB — 제 안의 실권자는 0).
  final int color;

  /// 제 안의 실권자인가(`a == 1`).
  final bool own;

  /// 쥔 쪽 띠의 uid(`text2` — 제 안의 실권자는 빈 글).
  final String holderUid;

  @override
  bool operator ==(Object other) =>
      other is PowerLine &&
      other.id == id &&
      other.band == band &&
      other.row == row &&
      other.x0 == x0 &&
      other.x1 == x1 &&
      other.holder == holder &&
      other.color == color &&
      other.own == own &&
      other.holderUid == holderUid;

  @override
  int get hashCode => Object.hash(id, band, row, x0, x1, holder, color, own, holderUid);

  @override
  String toString() => 'PowerLine(id: $id, band: $band, row: $row, x: $x0 ~ $x1, holder: $holder, color: $color, own: $own, uid: $holderUid)';
}

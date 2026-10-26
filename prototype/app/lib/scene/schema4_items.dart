// 스키마 4(docs/계약-아카이브-3단계.md 1-1절)가 타일에 더하는 칸 종류 · 칸 비트 · 일반 구역을 **받기만** 하는 자리.
// 값을 짓는 쪽은 내보내기 JS(prototype/scripts/export/strips.mjs의 KIND_OFFICE · ST_BORROW · SECTION.borrow · officeName,
// export/power.mjs의 SECTION_POWER_LINE)와 그 거울인 엔진이다. 4단계가 이 값을 그릴 때 여기서 읽어 쓴다(계획 정한 것 #14).
//
// 그림판(paint/*)이 읽는 몫(리메이크 4단계 과제 5 걸음 2 · 과제 6 — 줄 높이를 바꾸지 않는 것만):
//   · 칸 27비트([Schema4.isBorrowed] — 타일 칸 종류 1 · 2): strips.dart가 빌린 지도자 · 내각 칸을 .72 · 윗변 1px 파선으로(`_measure` · `_borrowedTop`).
//   · 구역 54의 a = 1 · 2([Schema4.borrowHeads]): bands.dart가 머리 이름 뒤에 `· 지도자 ← 출처` · `· 내각 ← 출처`(`_placeBorrow`).
//   · 구역 56([Schema4.powerLines]): bands.dart가 빼앗긴 띠 머리에 2px 밑줄 · 끝에 쥔 쪽 이름(`_placePowers` — 제 안의 실권자는 먹),
//     strips.dart가 그 기간과 겹친 지도자 칸을 .55로(`_measure` — 띠 층의 `powerSpans`를 읽는다).
// 아직 그림이 읽지 않는 몫(이 줄 아래는 3단계 끝 무렵의 글 — 칸 종류 9의 줄은 이제 그린다: 아래 [Schema4.officeLinesDrawn]): 칸 종류 9(직위 줄 더 — strips.dart `_stripAt`이 (−1, 0)으로 버림 · layout.dart `RowGeo.strip`의 나머지 갈래)와
// 구역 54의 a = 9 · 구역 55, 그리고 배치 갈래(remake-4-lay — 계약 1-1 덧붙임)가 실은 새 값 — 구역 57 · 58(칸 · 소속 구간의 정통성 —
// [Schema4.cellLegits] · [Schema4.hostLegits]) · 띠 look 30 · sub 17 ~ 21 · sub 22 ~ 23([Schema4.hasOfficeFloor] · [Schema4.officeMoreOf] ·
// [Schema4.leaderLanesOf]) · 칸 종류 1의 lane(두 단 띠에서 그 칸의 단). 읽개는 칸 그림 갈래(remake-4-cells) 걸음 1이 두었고(줄 fig_wide 21 ~ 30은
// layout.dart `RowFlags`), 그림은 그 갈래의 뒤 걸음(스위치 legit · office · body — paint/paint_pick.dart)이 읽는다.
// `CellStyle.bandOf`(27 ~ 29비트를 단 갈래로)는 종류 8에서만 보므로 빌림과 섞이지 않는다.
// 이 파일은 그림판을 import하지 않는다(그림판이 이 파일을 읽는 한 방향).

import 'tile.dart';

/// 스키마 4의 상수와 타일 하나에서 읽어 주는 작은 읽개.
abstract final class Schema4 {
  /// 칸 종류 9 = **직위 줄 더**(셋째 직위 줄부터). 칸의 `lane`(아래 8비트) = 그 줄의 차례(0 ~).
  /// 8은 공용 칸 단(계약 6-9 가-D5)이 쓴다. 띠의 칸 층 셈 · 줄 높이에는 4단계 G7 가(배치 판 9 — 띠 look 30 · sub 17 ~ 21 · 줄 fig_wide 21 ~ 25)부터 든다.
  static const cellOfficeMore = 9;

  /// 칸 종류 9(직위 줄 더)의 줄을 앱이 **그리는가 — 참**(리메이크 4단계 칸 그림 갈래 걸음 4 · G7 가 · 스위치 `office`). 차례 걸음 16의 되돌릴 자리 가운데
  /// **앱 몫은 뒤집었다**: 쌓기(layout.dart `_bandOf` — 내각 다음 · 예속 앞에 줄 fig_wide 21 ~ 25 × 14 · `RowGeo.strip(9, 줄)`) · 그림(paint/strips.dart
  /// `_stripAt` — 지도자 칸 꼴 · 27비트면 빌림 꼴) · 출처 글(paint/bands.dart `_borrowsOf` — `· 재상 ← 출처`) · 왼쪽 칸 줄 이름(paint/gutter.dart `_officeLabels`),
  /// 앱 검사(strips_paint_test '종류 9가 빌림 꼴로 그려진다' · schema4_paint_same_test (가) · office_lines_test).
  /// **엔진 몫도 뒤집었다**(0.1.1 · 2026-10-25): query.rs `search_year` · `legend_kinds`(`cells_of`)의 `c.kind<>9` 두 곳을 걷어 종류 9 칸이
  /// 범례 · 필터 시트의 조건부 줄과 연도 검색에 나온다(연도 검색의 곁글은 `〈정권〉 〈그 줄의 직위 이름 — 구역 55〉` · 칸 참조는 없음) — 계약 2-1 '스키마 4의 값' ·
  /// 엔진 검사 tests/queries.rs `직위_줄_더_칸은_범례와_연도_검색에_나온다` · 앱 검사 schema4_real_engine_test 'f4-office3: … 범례 · 연도 검색에 나온다'(진짜 DLL).
  /// 범례 · 연도 검색 창(ui)은 엔진 답을 따르므로 창 코드는 그대로다.
  static const officeLinesDrawn = true;

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

  /// 일반 구역 번호(계약 1-1 덧붙임 — 4단계 배치 갈래): 57 칸의 정통성 · 58 소속 구간의 정통성. 두 구역 모두 a ~ d에 띠 번호가 없다
  /// (엔진은 `items`에 그대로 싣고 스키마도 그대로 — 구역이 없는 옛 저장소는 칸 · 소속의 정통성을 모름).
  static const secCellLegit = 57, secHostLegit = 58;

  /// 정통성 번호 — 띠 form 10 ~ 12와 같은 차례(`BandForm.legits` · 내보내기 export/bands.mjs `STATUS_NO` − 1 · `HT.F4` STATUSES).
  /// 구역 57 · 58의 `d`는 이 번호 + 1이다(0 = 싣지 않음이라 실린 항목에서는 늘 1 이상). −1은 모름.
  static const legitOfficial = 0, legitRival = 1, legitJoint = 2, legitRegent = 3, legitNominal = 4, legitClaim = 5;

  /// 띠 `look` 30 = **직위 줄 더 층이 있음**(G7 가 — 칸 층 비트 21 ~ 29에 이어 · 내보내기 export/tracks.mjs `contributeLate`).
  static const lookOfficeMore = 1 << 30;

  /// 그 띠에 직위 줄 더 층이 있는가(띠 `look` 30).
  static bool hasOfficeFloor(int look) => look & lookOfficeMore != 0;

  /// 그 띠의 직위 줄 더 수(띠 `sub` 17 ~ 21 · 0 ~ 31 — 구역 55 `lane`의 최댓값 + 1 · 빌린 줄 포함). 옛 저장소는 0.
  static int officeMoreOf(int sub) => (sub >> 17) & 31;

  /// 그 띠의 지도자 층 단 수(띠 `sub` 22 ~ 23 = 단 수 − 1 → 1 ~ 4). 두 단 띠(공동 · 주장 칸이 다른 칸과 겹침)만 2 이상, 옛 저장소는 1.
  static int leaderLanesOf(int sub) => ((sub >> 22) & 3) + 1;

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

  /// 구역 57(칸의 정통성 — 칸마다 하나)의 항목들 — 타일에 실린 차례 그대로. 구역이 없으면 빈 목록.
  /// 칸과의 짝은 (띠 [CellLegit.band] · 칸 종류 [CellLegit.kind] · 순번 [CellLegit.seq]) — 순번은 칸 `style` 15 ~ 26(`CellStyle.seqOf`)과 같은 번호.
  static List<CellLegit> cellLegits(Tile t) {
    final s = t.section(secCellLegit);
    if (s.count == 0) return const [];
    final x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1);
    final id = s.u(Tile.itemId), ref = s.u(Tile.itemRef), row = s.u(Tile.itemRow);
    final a = s.u(Tile.itemA), b = s.u(Tile.itemB), c = s.u(Tile.itemC), d = s.u(Tile.itemD);
    return List.unmodifiable([
      for (int i = 0; i < s.count; i++)
        CellLegit(id: id[i], band: ref[i], row: row[i], x0: x0[i], x1: x1[i], kind: a[i], lane: b[i], seq: c[i] - 1, legit: d[i] - 1),
    ]);
  }

  /// 구역 58(소속 구간의 정통성 — 소속 한 건에 하나)의 항목들 — 타일에 실린 차례 그대로. 구역이 없으면 빈 목록.
  /// 소속 순번 [HostLegit.seq]는 구역 47(상국 탭)의 `b`와 같은 번호(속국 `hosts` 차례)라 상국 탭과 짝이 된다.
  static List<HostLegit> hostLegits(Tile t) {
    final s = t.section(secHostLegit);
    if (s.count == 0) return const [];
    final x0 = s.f(Tile.itemX0), x1 = s.f(Tile.itemX1);
    final id = s.u(Tile.itemId), ref = s.u(Tile.itemRef), row = s.u(Tile.itemRow), name = s.u(Tile.itemName);
    final color = s.u(Tile.itemColor), a = s.u(Tile.itemA), b = s.u(Tile.itemB), d = s.u(Tile.itemD), text2 = s.u(Tile.itemText2);
    return List.unmodifiable([
      for (int i = 0; i < s.count; i++)
        HostLegit(
          id: id[i],
          band: ref[i],
          row: row[i],
          x0: x0[i],
          x1: x1[i],
          hostName: t.text(name[i]),
          hostColor: color[i],
          era: a[i] == 1,
          seq: b[i],
          legit: d[i] - 1,
          hostUid: t.text(text2[i]),
        ),
    ]);
  }
}

/// 구역 57 — 칸의 정통성(칸마다 하나 · 지도자 · 내각 · 직위 줄 더 칸에 status가 적힌 것만 — 계약 1-1 덧붙임).
final class CellLegit {
  const CellLegit({
    required this.id,
    required this.band,
    required this.row,
    required this.x0,
    required this.x1,
    required this.kind,
    required this.lane,
    required this.seq,
    required this.legit,
  });

  /// 항목 번호.
  final int id;

  /// 그 칸이 든 띠의 id(`ref`)와 그 칸의 줄.
  final int band, row;

  /// 그 칸의 구간(타일 시작에서 잰 분).
  final double x0, x1;

  /// 칸 종류(`a` — 1 지도자 · 2 내각 · 9 직위 줄 더)와 칸의 `lane`(`b` — 두 단 띠의 지도자 칸이면 그 단 · 직위 줄 더면 그 줄의 차례).
  final int kind, lane;

  /// 그 칸의 순번(`c` − 1 — 칸 `style` 15 ~ 26과 같은 번호 · −1 = 모름).
  final int seq;

  /// 정통성 번호(`d` − 1 — [Schema4.legitRival] … · −1 = 모름).
  final int legit;

  @override
  bool operator ==(Object other) =>
      other is CellLegit &&
      other.id == id &&
      other.band == band &&
      other.row == row &&
      other.x0 == x0 &&
      other.x1 == x1 &&
      other.kind == kind &&
      other.lane == lane &&
      other.seq == seq &&
      other.legit == legit;

  @override
  int get hashCode => Object.hash(id, band, row, x0, x1, kind, lane, seq, legit);

  @override
  String toString() => 'CellLegit(id: $id, band: $band, row: $row, x: $x0 ~ $x1, kind: $kind, lane: $lane, seq: $seq, legit: $legit)';
}

/// 구역 58 — 소속 구간의 정통성(소속 한 건에 하나 · status가 적힌 소속만 · 속국 띠에 실림 — 계약 1-1 덧붙임).
final class HostLegit {
  const HostLegit({
    required this.id,
    required this.band,
    required this.row,
    required this.x0,
    required this.x1,
    required this.hostName,
    required this.hostColor,
    required this.era,
    required this.seq,
    required this.legit,
    required this.hostUid,
  });

  /// 항목 번호.
  final int id;

  /// 속국 띠의 id(`ref`)와 줄.
  final int band, row;

  /// 그 소속의 구간(속국 띠의 구간으로 자름 · 타일 시작에서 잰 분).
  final double x0, x1;

  /// 상위 이름 · 색(0xRRGGBB — `name` · `color`).
  final String hostName;
  final int hostColor;

  /// 시대 그릇 소속의 몫인가(`a == 1` — 계약은 아직 싣지 않고 자리만 비워 둠).
  final bool era;

  /// 그 소속의 순번(`b` — 속국 `hosts` 차례 · 구역 47의 `b`와 같음).
  final int seq;

  /// 정통성 번호(`d` − 1 — [Schema4.legitRival] … · −1 = 모름).
  final int legit;

  /// 상위의 uid(`text2`).
  final String hostUid;

  @override
  bool operator ==(Object other) =>
      other is HostLegit &&
      other.id == id &&
      other.band == band &&
      other.row == row &&
      other.x0 == x0 &&
      other.x1 == x1 &&
      other.hostName == hostName &&
      other.hostColor == hostColor &&
      other.era == era &&
      other.seq == seq &&
      other.legit == legit &&
      other.hostUid == hostUid;

  @override
  int get hashCode => Object.hash(id, band, row, x0, x1, hostName, hostColor, era, seq, legit, hostUid);

  @override
  String toString() =>
      'HostLegit(id: $id, band: $band, row: $row, x: $x0 ~ $x1, host: $hostName, color: $hostColor, era: $era, seq: $seq, legit: $legit, uid: $hostUid)';
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

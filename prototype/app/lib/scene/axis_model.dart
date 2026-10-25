import 'aux_calendar.dart';
import 'layout.dart';
import 'ruler.dart' show minuteOfYear, yearAt;

// 날짜 칸(맨 위)의 줄 구성. 지금 연표의 `_buildAxis`(js/timeline.js 3781~3946줄)를 그대로 옮겼다 —
// 연도 30 · 공통 시대 구분 24×단 · 간지 20 · 보조 달력 20(접히면 1) · 나라별 시대 줄 24×단 · 연호 묶음 22 · 도읍 묶음 22,
// 묶음을 열면 나라마다 연호 줄 22×갈래 · 도읍 줄 22×갈래(+ 배도 16×단 + 2).
//
// 줄 상자의 높이는 지금 연표의 AXIS 값 그대로이고, 첫 줄 말고는 위 1px이 구분선의 몫이다(css의 box-sizing: border-box).
// 날짜 칸 전체 = 맨 위 1px(연표 상자의 테두리) + 줄들 + 맨 아래 1px(몸통과의 구분선) — 월흔해 견본에서 409px이다.
//
// 보조 달력 줄(`.tl-axis-row.is-cal`)은 접혀 있어도 **구분선 1px을 차지한다**(css 1115줄: `height: 0` + box-sizing
// border-box + 투명한 위 테두리). 그 1px이 빠지면 간지 줄 아래의 모든 줄과 몸통이 1px 위로 올라온다.

/// 날짜 칸 줄의 종류.
enum AxisRowKind {
  /// 연도 눈금.
  years,

  /// 시대 구분(공통 줄 또는 나라별 줄).
  epoch,

  /// 간지.
  ganji,

  /// 보조 달력(음력 …). 접혀 있으면 1px — 구분선의 자리만 차지한다.
  cal,

  /// 연호 · 도읍 묶음의 머리 줄(접혀 있으면 나라마다 가는 막대).
  group,

  /// 펼친 묶음 안의 나라별 연호 줄.
  era,

  /// 펼친 묶음 안의 나라별 도읍 줄(+ 배도 갈래).
  cap,
}

/// 한 나라의 연호(또는 도읍) 자료. 묶음이 접혀 있을 때는 [spans]의 가는 막대로만 보인다.
class AxisTrackData {
  const AxisTrackData(this.track, this.cells, this.sec, this.lanes, this.secLanes, this.spans);
  final TrackInfo track;

  /// 연호(kind 2) 또는 도읍(kind 3)의 칸. 시작 순.
  final List<AxisCell> cells;

  /// 배도(kind 4)의 칸. 도읍에만 있다.
  final List<AxisCell> sec;
  final int lanes, secLanes;

  /// 접힌 묶음의 가는 막대 — 겹치는 구간을 합친 [시작, 끝](분).
  final List<(double, double)> spans;
}

/// 날짜 칸의 줄 하나. [top] · [height]는 날짜 칸 안의 자리(줄 상자 전체)다.
class AxisRow {
  const AxisRow({
    required this.kind, required this.top, required this.height, required this.border,
    this.corner = '', this.mark = '', this.arrow = AxisArrow.none, this.track, this.data, this.epochs = const [], this.lanes = 1,
    this.groupKey = '', this.members = const [], this.folded = false, this.secOpen = false,
  });
  final AxisRowKind kind;
  final double top, height;

  /// 위 1px 구분선이 있는가(첫 줄만 없다).
  final bool border;

  /// 모서리 칸의 글과, 그 뒤에 붙는 작은 글(묶음 단추의 '12개 나라' · 접기 표시)과 여닫음 표시.
  final String corner, mark;
  final AxisArrow arrow;

  /// 그 줄의 나라(공통 줄 · 묶음 머리 줄은 없음).
  final TrackInfo? track;

  /// 연호 · 도읍 줄의 자료.
  final AxisTrackData? data;

  /// 시대 구분 칸(시작 순).
  final List<AxisCell> epochs;

  /// 그 줄 안의 단 수.
  final int lanes;

  /// 묶음 열쇠('eras' · 'capitals').
  final String groupKey;

  /// 묶음 머리 줄이 품은 나라들.
  final List<AxisTrackData> members;

  /// 연호 줄이 한 줄로 접혀 있는가 · 도읍 줄의 배도 갈래가 펼쳐져 있는가.
  final bool folded, secOpen;

  /// 구분선을 뺀 알맹이의 자리(지금 연표의 `.tl-axis-cells`).
  double get contentTop => top + (border ? 1 : 0);
  double get contentHeight => height - (border ? 1 : 0);
}

/// 모서리 칸의 여닫음 표시(지금 연표의 '▸' · '▾'). 글꼴에 없는 글자라 그리는 쪽이 조각으로 찍는다.
enum AxisArrow { none, right, down }

/// 누른 자리가 무엇인가.
///
/// **누를 것이 없어도 도움말만 있는 자리가 있다** — 보조 달력의 달 · 날 칸은 지금 연표에서도 `title`만 있는
/// `<i>`라 누름이 없다. 그런 자리는 [none]이면서 [AxisHit.tip]이 차 있다. 받는 쪽은 `kind`로 할 일을 고르고,
/// 도움말은 `tip`이 비지 않았는지로 가른다(갈래를 더 두면 `timeline_view.dart`의 switch가 다 못 받아 막힌다).
enum AxisHitKind { none, groupToggle, eraFold, capSec, calPick, epochCell, eraCell, capCell, secCell }

class AxisHit {
  const AxisHit(this.kind, {this.key = '', this.track = 0, this.cell, this.row = -1, this.tip = '', this.x = 0});
  final AxisHitKind kind;

  /// 묶음 열쇠('eras' · 'capitals').
  final String key;

  /// 그 줄의 나라(없으면 0).
  final int track;

  /// 누른 칸(칸이 아니면 없음).
  final AxisCell? cell;

  /// 누른 줄의 번호([AxisModel.rows]에서의 자리).
  final int row;

  /// 커서를 올렸을 때 띄울 도움말 글(지금 연표의 `title`). 없으면 빈 글 — 띄우는 것은 총괄이 한다.
  final String tip;

  /// 도움말을 띄울 가로 자리(배치 px) — 그 칸 · 단추의 왼쪽 끝이다.
  /// 화면 왼쪽으로 잘린 칸은 그림 영역의 왼쪽 끝이고, 자리를 알 수 없으면 누른 자리 그대로다.
  final double x;
  static const none = AxisHit(AxisHitKind.none);
}

/// 날짜 칸의 줄 구성과 여닫는 상태. 그리기는 `paint/axis.dart`가 한다.
class AxisModel {
  AxisModel(this.layout) {
    rebuild();
  }
  final SceneLayout layout;

  /// 줄 높이 — 지금 연표의 AXIS 값에서 연도 · 시대 줄만 목업(서고 dateHeader — 리메이크 2부)으로: 연도 24, 시대 줄은 위 3(구분선 1 + 2) + 단마다 17(이름 종이 15 + 틈 2).
  static const yearsHeight = 24.0, ganjiHeight = 20.0, epochHeight = 17.0, epochPad = 3.0, groupHeight = 22.0, eraHeight = 22.0, capHeight = 22.0, secHeight = 16.0;

  /// 보조 달력 줄: 펼치면 20, 접히면 구분선 1px만(css `.tl-axis-row.is-cal`).
  static const calHeight = 20.0, calFoldedHeight = 1.0;

  /// 날짜 칸의 위아래 1px(연표 상자의 테두리 · 몸통과의 구분선).
  static const topInset = 1.0, bottomLine = 1.0;

  /// 날짜 칸의 칸 종류(계약 6-3절).
  static const kindEpoch = 1, kindEra = 2, kindCapital = 3, kindSecondary = 4;

  /// 칸의 style 비트(계약 6-3절).
  static const styleStartUnknown = 1, styleEndUnknown = 2, styleTemporary = 4, styleExile = 8, styleShared = 16, styleVariant = 32;

  final rows = <AxisRow>[];

  /// 펼친 묶음('eras' · 'capitals') · 한 줄로 접은 나라의 연호 · 배도 갈래를 편 나라.
  final open = <String>{}, foldedEras = <int>{}, openCapSec = <int>{};

  /// 기본은 펼침이므로 이 열쇠가 있을 때 접힌다(웹 axisOpen과 같은 기억).
  static const epochFold = 'epochFold';

  /// 접힌 시대 구분 줄의 첫 가닥(공통 줄)이 쓰는 자리표 트랙 — 공통 줄은 트랙이 없다(가닥의 막대 색은 시대 구분마다 제 색).
  static const _commonTrack = TrackInfo(0, 0, '공통', 0, 0);
  YearCycle? yearCycle;
  bool setYearCycle(YearCycle? value) {
    if (identical(value, yearCycle)) return false;
    yearCycle = value;
    rebuild();
    return true;
  }

  /// 보조 달력(''이면 끔). 지금 연표의 `opts.altCal` 기본값은 음력이다.
  String altCal = AuxCalendar.defaultId;

  /// 보조 달력 줄이 펼쳐져 있는가(눈금이 한 달 18px을 넘을 때 — 그리는 쪽이 [Ruler]에서 받아 넣는다).
  bool calOpen = false;

  /// 보조 달력 줄이 날 눈금인가(하루가 20px을 넘을 때 — 그리는 쪽이 넣는다). 줄 높이와는 상관없고,
  /// 도움말을 만들 때 달 칸인지 날 칸인지를 가른다.
  bool calDay = false;

  /// 보조 달력 고르기 단추의 가로 자리(모서리 칸 안의 배치 px) — 그리는 쪽이 글을 재어 넣는다.
  /// 지금 연표의 `<select>`는 제 크기(100px 남짓)만큼만 커서를 받는다. 아직 재지 않았으면(둘이 같으면) 모서리 칸 전체로 본다.
  double calPickL = 0, calPickR = 0;

  /// 보조 달력 줄의 여닫음을 갈아 끼운다. 바뀌었으면 참.
  bool setCalOpen(bool open) {
    if (open == calOpen) return false;
    calOpen = open;
    rebuild();
    return true;
  }

  /// 보조 달력을 바꾸거나 끈다. 바뀌었으면 참.
  bool setAltCal(String id) {
    if (id == altCal) return false;
    altCal = id;
    stateVersion++;
    rebuild();
    return true;
  }

  // ---- 필터 시트의 '날짜 칸' 표시 체크 넷(명세 06의 6-2절 · 지금 연표의 `ui.show.*`) ----
  //
  // 끄면 그 줄(묶음)이 통째로 빠지고 날짜 칸이 그만큼 낮아진다 — 지금 연표의 `_buildAxis`(js/timeline.js 3800 ·
  // 3804 · 3814 · 3837 · 3853)와 같은 자리에서 같은 줄을 뺀다. `epochs`는 **공통 줄과 나라별 줄을 함께** 끈다.
  // 보조 달력 줄은 이 넷에 들지 않는다(고르기 단추로 따로 끈다).

  // 리메이크 2부(목업 서고 — 감독 2026-10-15 '최대한 목업 반영'): 목업 날짜 칸은 연도 · 시대뿐이라 간지 · 연호 · 도읍 줄은 처음에 끈다(보기 메뉴에서 켬).
  bool _showGanji = false, _showEras = false, _showCapitals = false, _showEpochs = true;

  bool get showGanji => _showGanji;
  bool get showEras => _showEras;
  bool get showCapitals => _showCapitals;
  bool get showEpochs => _showEpochs;

  /// 표시 열쇠('ganji' · 'eras' · 'capitals' · 'epochs')로 읽는다. 모르는 열쇠는 참.
  bool shown(String key) => switch (key) {
    'ganji' => _showGanji,
    'eras' => _showEras,
    'capitals' => _showCapitals,
    'epochs' => _showEpochs,
    _ => true,
  };

  /// 표시 체크를 갈아 끼운다(주지 않은 것은 그대로). 바뀌었으면 다시 쌓고 참을 돌려준다.
  bool setShown({bool? ganji, bool? eras, bool? capitals, bool? epochs}) {
    if ((ganji ?? _showGanji) == _showGanji &&
        (eras ?? _showEras) == _showEras &&
        (capitals ?? _showCapitals) == _showCapitals &&
        (epochs ?? _showEpochs) == _showEpochs) {
      return false;
    }
    _showGanji = ganji ?? _showGanji;
    _showEras = eras ?? _showEras;
    _showCapitals = capitals ?? _showCapitals;
    _showEpochs = epochs ?? _showEpochs;
    stateVersion++;
    rebuild();
    return true;
  }

  // ---- 열어 둔 상태의 기억(`AppMemory.parts['axis']`) ----

  /// 사람이 정한 것(여닫음 · 접기 · 보조 달력 · 표시 넷)이 바뀔 때마다 오른다 — 총괄이 이 값이 달라졌을 때 기억에 적는다.
  /// [restoreState]로 되돌릴 때도 오른다(되돌린 값을 그대로 다시 적어도 해가 없다).
  int stateVersion = 0;

  /// 기억에 적을 것. 열쇠 이름은 지금 연표의 기억(js/viewer.js 166~204)과 같다.
  Map<String, dynamic> stateJson() => {
    'axisOpen': open.toList()..sort(),
    'foldedEras': foldedEras.toList()..sort(),
    'openCapSec': openCapSec.toList()..sort(),
    'altCal': altCal,
    'show': {'ganji': _showGanji, 'eras': _showEras, 'capitals': _showCapitals, 'epochs': _showEpochs},
  };

  /// 기억을 되돌린다. 적히지 않은 열쇠는 건드리지 않고, 꼴이 어긋난 값은 버린다
  /// (뒤에 생긴 표시가 옛 기억을 쓰는 사람에게 꺼진 채로 나오지 않게 — 명세 8-4의 규칙).
  /// 무엇이든 달라졌으면 다시 쌓고 참을 돌려준다.
  bool restoreState(Map<dynamic, dynamic> json) {
    var changed = false;
    Set<String>? texts(Object? raw) => raw is List ? {for (final one in raw) if (one is String) one} : null;
    Set<int>? numbers(Object? raw) => raw is List ? {for (final one in raw) if (one is num) one.toInt()} : null;
    bool swap<T>(Set<T> now, Set<T>? next) {
      if (next == null || (now.length == next.length && now.containsAll(next))) return false;
      now
        ..clear()
        ..addAll(next);
      return true;
    }

    changed = swap(open, texts(json['axisOpen'])) || changed;
    changed = swap(foldedEras, numbers(json['foldedEras'])) || changed;
    changed = swap(openCapSec, numbers(json['openCapSec'])) || changed;
    final cal = json['altCal'];
    if (cal is String && cal != altCal && (cal.isEmpty || AuxCalendar.of(cal) != null)) {
      altCal = cal;
      changed = true;
    }
    final show = json['show'];
    if (show is Map) {
      bool? on(String key) => show[key] is bool ? show[key] as bool : null;
      final before = [_showGanji, _showEras, _showCapitals, _showEpochs];
      _showGanji = on('ganji') ?? _showGanji;
      _showEras = on('eras') ?? _showEras;
      _showCapitals = on('capitals') ?? _showCapitals;
      _showEpochs = on('epochs') ?? _showEpochs;
      if (before[0] != _showGanji || before[1] != _showEras || before[2] != _showCapitals || before[3] != _showEpochs) changed = true;
    }
    if (!changed) return false;
    stateVersion++;
    rebuild();
    return true;
  }

  double _height = 0;
  int _stackVersion = -1;

  /// 날짜 칸 전체의 높이(몸통이 시작하는 자리).
  double get height => _height;

  /// 줄 구성이 바뀔 때마다 오른다 — 그리는 쪽이 장면마다 다시 쌓을지 볼 때.
  int version = 0;

  /// 자료집이 바뀌었으면 다시 쌓는다. 바뀌었으면 참.
  bool sync() {
    if (_stackVersion == layout.stackVersion) return false;
    rebuild();
    return true;
  }

  /// 묶음을 여닫는다. 바뀌었으면 참.
  bool toggleGroup(String key) {
    if (!open.remove(key)) open.add(key);
    stateVersion++;
    rebuild();
    return true;
  }

  /// 한 나라의 연호 줄을 한 줄로 접거나 편다.
  bool toggleEraFold(int track) {
    if (!foldedEras.remove(track)) foldedEras.add(track);
    stateVersion++;
    rebuild();
    return true;
  }

  /// 한 나라의 배도 갈래를 여닫는다.
  bool toggleCapSec(int track) {
    if (!openCapSec.remove(track)) openCapSec.add(track);
    stateVersion++;
    rebuild();
    return true;
  }

  void rebuild() {
    _stackVersion = layout.stackVersion;
    version++;
    rows.clear();
    double y = topInset;
    bool first = true;
    void add(AxisRow Function(double top, bool border) make, double h) {
      rows.add(make(y, !first));
      y += h;
      first = false;
    }

    final tracks = [for (final t in layout.tracks) if (layout.isPackEnabled(t.pack)) t];
    final byTrack = <int, List<AxisCell>>{};
    for (final cell in layout.axis) {
      (byTrack[cell.track * 8 + cell.kind] ??= []).add(cell);
    }
    List<AxisCell> cellsOf(int track, int kind) => byTrack[track * 8 + kind] ?? const [];

    // 1) 연도
    add((top, border) => AxisRow(kind: AxisRowKind.years, top: top, height: yearsHeight, border: border), yearsHeight);

    // 2) 공통 시대 구분 — 한 줄에 겹치는 것은 단을 나눈다(칸에 실려 온 lane 그대로).
    // 공통 줄의 시대 구분은 `axis`(kind 1 · 공통)와 `epochs` 둘 다에 실려 온다(계약 6-3절). 날짜 칸의 칸이 없는
    // 2판 저장소에서도 줄이 나오도록 `epochs`로 갈음한다.
    // DLC를 다 껐으면(저장소는 그대로 두고 화면에서만 끈 때 — DLC 관리) 공통 줄의 시대도 없다.
    final common = !_showEpochs || layout.enabledPacks.isEmpty
        ? const <AxisCell>[]
        : cellsOf(0, kindEpoch).isNotEmpty
            ? cellsOf(0, kindEpoch)
            : [for (final e in layout.epochs) AxisCell(kindEpoch, 0, 0, e.start, e.end, e.name, e.color, 0, 0, 0)];
    // 시대 접기(설계 6 결정 7 A → 감독 건의 2026-10-14 2번): 공통 줄까지 모든 시대 구분 줄을 한 줄 '시대 구분 n줄 ▸'로 접는다.
    // 접힌 줄은 맨 처음 시대 구분 줄의 자리(공통 줄이 있으면 여기 — 연도 바로 아래, 없으면 아래 4)의 나라별 자리). 펼친 줄은 어느 것이든
    // 왼쪽 이름을 누르면 모두 접히고, 맨 처음 줄의 이름 끝에 ▾(웹 `.tl-fold-mark`)가 붙는다. 기억 열쇠는 그대로 [epochFold](있으면 접힘).
    final epochData = <AxisTrackData>[];
    if (common.isNotEmpty) epochData.add(AxisTrackData(_commonTrack, common, const [], _lanesOf(common), 0, const []));
    for (final t in _showEpochs ? tracks : const <TrackInfo>[]) {
      final list = cellsOf(t.id, kindEpoch);
      if (list.isEmpty) continue;
      epochData.add(AxisTrackData(t, list, const [], _lanesOf(list), 0, const []));
    }
    final epochFolded = epochData.isNotEmpty && open.contains(epochFold);
    void epochFoldRow() => add((top, border) => AxisRow(
      kind: AxisRowKind.group, top: top, height: groupHeight, border: border, corner: '시대 구분',
      mark: '${epochData.length}줄', arrow: AxisArrow.right, groupKey: epochFold, members: epochData,
    ), groupHeight);
    void epochRow(AxisTrackData d, bool first) {
      final track = identical(d.track, _commonTrack) ? null : d.track;
      add((top, border) => AxisRow(
        kind: AxisRowKind.epoch, top: top, height: epochPad + epochHeight * d.lanes, border: border,
        corner: track == null ? '시대' : '${track.name} 시대', track: track, epochs: d.cells, lanes: d.lanes,
        arrow: first ? AxisArrow.down : AxisArrow.none,
      ), epochPad + epochHeight * d.lanes);
    }
    if (common.isNotEmpty) {
      if (epochFolded) {
        epochFoldRow();
      } else {
        epochRow(epochData.first, true);
      }
    }

    // 3) 간지
    if (_showGanji) add((top, border) => AxisRow(kind: AxisRowKind.ganji, top: top, height: ganjiHeight, border: border, corner: yearCycle?.title ?? '간지'), ganjiHeight);

    // 3-1) 보조 달력 — 접혀 있어도 구분선 1px을 차지한다(그 1px이 빠지면 아래 줄과 몸통이 통째로 1px 올라온다).
    if (AuxCalendar.of(altCal) != null) {
      final h = calOpen ? calHeight : calFoldedHeight;
      add((top, border) => AxisRow(
        kind: AxisRowKind.cal, top: top, height: h, border: border,
        corner: AuxCalendar.of(altCal)!.name, arrow: calOpen ? AxisArrow.down : AxisArrow.none,
      ), h);
    }

    // 4) 나라별 시대 구분 — 접혀 있으면 공통 줄이 없을 때만 여기에 접힌 줄 하나
    final epochByTrack = common.isEmpty ? epochData : epochData.skip(1).toList();
    if (!epochFolded) {
      for (final (i, d) in epochByTrack.indexed) {
        epochRow(d, common.isEmpty && i == 0);
      }
    } else if (common.isEmpty) {
      epochFoldRow();
    }

    // 5) 연호 묶음
    final eraData = <AxisTrackData>[];
    for (final t in _showEras ? tracks : const <TrackInfo>[]) {
      final list = cellsOf(t.id, kindEra);
      if (list.isEmpty) continue;
      eraData.add(AxisTrackData(t, list, const [], _lanesOf(list), 0, _spansOf([list])));
    }
    if (eraData.isNotEmpty) {
      final isOpen = open.contains('eras');
      add((top, border) => AxisRow(
        kind: AxisRowKind.group, top: top, height: groupHeight, border: border, corner: '연호',
        mark: isOpen ? '' : '${eraData.length}개 나라', arrow: isOpen ? AxisArrow.down : AxisArrow.right, groupKey: 'eras', members: eraData,
      ), groupHeight);
      if (isOpen) {
        for (final d in eraData) {
          final folded = d.lanes > 1 && foldedEras.contains(d.track.id);
          final h = eraHeight * (folded ? 1 : d.lanes);
          add((top, border) => AxisRow(
            kind: AxisRowKind.era, top: top, height: h, border: border, corner: d.track.name,
            mark: d.lanes > 1 && folded ? '${d.lanes}갈래' : '', arrow: d.lanes > 1 ? (folded ? AxisArrow.right : AxisArrow.down) : AxisArrow.none,
            track: d.track, data: d, lanes: folded ? 1 : d.lanes, folded: folded,
          ), h);
        }
      }
    }

    // 6) 도읍 묶음(배도 갈래는 나라마다 따로 연다)
    final capData = <AxisTrackData>[];
    for (final t in _showCapitals ? tracks : const <TrackInfo>[]) {
      final list = cellsOf(t.id, kindCapital), sec = cellsOf(t.id, kindSecondary);
      if (list.isEmpty && sec.isEmpty) continue;
      capData.add(AxisTrackData(t, list, sec, list.isEmpty ? 1 : _lanesOf(list), sec.isEmpty ? 0 : _lanesOf(sec), _spansOf([list, sec])));
    }
    if (capData.isNotEmpty) {
      final isOpen = open.contains('capitals');
      add((top, border) => AxisRow(
        kind: AxisRowKind.group, top: top, height: groupHeight, border: border, corner: '도읍',
        mark: isOpen ? '' : '${capData.length}개 나라', arrow: isOpen ? AxisArrow.down : AxisArrow.right, groupKey: 'capitals', members: capData,
      ), groupHeight);
      if (isOpen) {
        for (final d in capData) {
          final secOpen = d.secLanes > 0 && openCapSec.contains(d.track.id);
          final h = capHeight * d.lanes + (secOpen ? d.secLanes * secHeight + 2 : 0);
          add((top, border) => AxisRow(
            kind: AxisRowKind.cap, top: top, height: h, border: border, corner: d.track.name,
            mark: d.secLanes == 0 ? '' : (secOpen ? '배도' : '배도 ${_secGroups(d.sec)}'),
            arrow: d.secLanes == 0 ? AxisArrow.none : (secOpen ? AxisArrow.down : AxisArrow.right),
            track: d.track, data: d, lanes: d.lanes, secOpen: secOpen,
          ), h);
        }
      }
    }
    _height = y + bottomLine;
  }

  /// 그 줄의 단 수(칸에 실려 온 lane의 가장 큰 값 + 1).
  static int _lanesOf(List<AxisCell> cells) {
    int lanes = 1;
    for (final c in cells) {
      if (c.lane + 1 > lanes) lanes = c.lane + 1;
    }
    return lanes;
  }

  /// 배도 묶음의 수(strip이 다르면 다른 묶음).
  static int _secGroups(List<AxisCell> sec) {
    final keys = <int>{};
    for (final c in sec) {
      keys.add(c.strip == 0 ? -c.start : c.strip);
    }
    return keys.length;
  }

  /// 접힌 묶음의 가는 막대: 이어진 칸 무리(strip)마다 한 구간으로 묶고, 겹치는 구간을 합친다.
  static List<(double, double)> _spansOf(List<List<AxisCell>> lists) {
    final byStrip = <int, (double, double)>{};
    final raw = <(double, double)>[];
    for (final list in lists) {
      for (final c in list) {
        final span = (c.start.toDouble(), c.end.toDouble());
        if (c.strip == 0) {
          raw.add(span);
          continue;
        }
        final cur = byStrip[c.strip];
        byStrip[c.strip] = cur == null ? span : (cur.$1 < span.$1 ? cur.$1 : span.$1, cur.$2 > span.$2 ? cur.$2 : span.$2);
      }
    }
    raw.addAll(byStrip.values);
    raw.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(double, double)>[];
    for (final s in raw) {
      if (merged.isNotEmpty && s.$1 <= merged.last.$2) {
        final last = merged.last;
        if (s.$2 > last.$2) merged[merged.length - 1] = (last.$1, s.$2);
      } else {
        merged.add(s);
      }
    }
    return merged;
  }

  /// 날짜 칸 안의 세로 자리에 있는 줄 번호. 없으면 −1.
  int rowAt(double y) {
    for (int i = 0; i < rows.length; i++) {
      if (y >= rows[i].top && y < rows[i].top + rows[i].height) return i;
    }
    return -1;
  }

  /// 누른 자리가 무엇인가. [x] · [y]는 배치 px(날짜 칸의 왼쪽 위가 0,0), [left]는 왼쪽 모서리 칸의 폭,
  /// [minuteAt]은 그림 영역의 x를 분으로 바꾸는 길이다. [xOf]를 주면 답에 그 칸의 왼쪽 끝([AxisHit.x])이 실린다 —
  /// 도움말을 칸 자리에 띄울 때 쓴다(주지 않으면 누른 자리 그대로).
  AxisHit hitTest(double x, double y, double left, double Function(double x) minuteAt, {double Function(double minute)? xOf}) {
    final index = rowAt(y);
    if (index < 0) return AxisHit.none;
    final row = rows[index];
    // 칸의 왼쪽 끝(화면 왼쪽으로 잘렸으면 그림 영역의 왼쪽 끝).
    double leftOf(AxisCell cell) => xOf == null ? x : (xOf(cell.start.toDouble()) < left ? left : xOf(cell.start.toDouble()));
    // 모서리 칸: 묶음 단추 · 연호 접기 · 배도 갈래 · 보조 달력 고르기
    if (x < left) {
      return switch (row.kind) {
        AxisRowKind.group => AxisHit(AxisHitKind.groupToggle, key: row.groupKey, row: index, tip: _groupTip(row), x: 0),
        AxisRowKind.epoch => AxisHit(AxisHitKind.groupToggle, key: epochFold, row: index, tip: '${row.corner} — 눌러서 시대 구분 줄을 모두 한 줄로 접기', x: 0),
        AxisRowKind.era when row.data!.lanes > 1 => AxisHit(
            AxisHitKind.eraFold, track: row.track!.id, row: index, x: 0,
            tip: '${row.track!.name} 연호 · ${row.folded ? '${row.data!.lanes}갈래로 펼치기' : '한 줄로 접기'}',
          ),
        AxisRowKind.cap when row.data!.secLanes > 0 => AxisHit(
            AxisHitKind.capSec, track: row.track!.id, row: index, x: 0,
            tip: '${row.track!.name} 도읍 · ${row.secOpen ? '배도 갈래 접기' : '배도(별도·5경·소경) 갈래 펼치기'}',
          ),
        // 고르기 단추는 지금 연표에서 `<select>` 제 크기(100px 남짓)만큼만 커서를 받는다 — 모서리 칸 어디서나가 아니다.
        AxisRowKind.cal when calOpen && _inCalPick(x, left) =>
          AxisHit(AxisHitKind.calPick, key: altCal, row: index, tip: '보조 달력 — 바꾸거나 끌 수 있습니다', x: calPickR > calPickL ? calPickL : 0),
        // 갈래가 하나인 연호 줄 · 배도가 없는 도읍 줄의 모서리는 단추가 아니라 그냥 칸이지만 도움말은 있다
        // (js/timeline.js 3929 `<div class="tl-corner" title="… 연호">` · 3940 `… 도읍`). 누를 것이 없으니
        // 갈래는 [AxisHitKind.none]이고 [AxisHit.tip]만 찬다 — 보조 달력 칸과 같은 꼴이다.
        // 단추가 먼저 잡히도록 `when`이 붙은 두 줄보다 뒤에 둔다.
        AxisRowKind.era => AxisHit(AxisHitKind.none, track: row.track!.id, row: index, tip: '${row.track!.name} 연호', x: 0),
        AxisRowKind.cap => AxisHit(AxisHitKind.none, track: row.track!.id, row: index, tip: '${row.track!.name} 도읍', x: 0),
        _ => AxisHit.none,
      };
    }
    // 접힌 묶음 줄은 어디를 눌러도 펼친다.
    if (row.kind == AxisRowKind.group) {
      return row.groupKey != epochFold && open.contains(row.groupKey) ? AxisHit.none : AxisHit(AxisHitKind.groupToggle, key: row.groupKey, row: index, tip: _groupTip(row), x: x);
    }
    final at = minuteAt(x);
    if (row.kind == AxisRowKind.cal) return calOpen ? _calHit(at, index, x, left, xOf) : AxisHit.none;
    final lane = ((y - row.contentTop - (row.kind == AxisRowKind.epoch ? epochPad - 1 : 0)) / _laneHeight(row.kind)).floor();
    AxisHit? pick(List<AxisCell> cells, AxisHitKind kind, int inLane) {
      for (final c in cells) {
        if (c.lane != inLane || at < c.start || at > c.end) continue;
        return AxisHit(kind, track: row.track?.id ?? 0, cell: c, row: index, x: leftOf(c));
      }
      return null;
    }

    return switch (row.kind) {
      AxisRowKind.epoch => pick(row.epochs, AxisHitKind.epochCell, lane) ?? AxisHit.none,
      AxisRowKind.era => pick(row.data!.cells, AxisHitKind.eraCell, row.folded ? -1 : lane) ?? (row.folded ? _anyLane(row, at, index, leftOf) : AxisHit.none),
      AxisRowKind.cap => _capHit(row, index, y, at, lane, leftOf),
      _ => AxisHit.none,
    };
  }

  /// 커서가 보조 달력 고르기 단추 안에 있는가. 그리는 쪽이 아직 자리를 재지 않았으면 모서리 칸 전체로 본다.
  bool _inCalPick(double x, double left) => calPickR > calPickL ? (x >= calPickL && x <= calPickR) : true;

  /// 묶음 단추의 도움말(지금 연표의 `tip` — js/timeline.js 3897).
  String _groupTip(AxisRow row) {
    final name = row.corner;
    if (row.groupKey != epochFold && open.contains(row.groupKey)) return '$name 접기';
    if (row.groupKey == epochFold) return '$name — ${[for (final d in row.members) identical(d.track, _commonTrack) ? '공통' : d.track.name].join(' · ')} · 눌러서 펼치기';
    return '$name — ${[for (final d in row.members) d.track.name].join(' · ')} · 눌러서 나라별로 펼치기';
  }

  /// 보조 달력 칸의 도움말(지금 연표의 `title` — 달 칸 js/timeline.js 5865 · 날 칸 5850).
  /// 누를 것은 없으므로 갈래는 [AxisHitKind.none]이고 [AxisHit.tip]만 찬다([key]에 달력, [row]에 줄 번호).
  /// 표가 없거나 그 날을 덮지 않으면 도움말도 없다.
  AxisHit _calHit(double at, int index, double x, double left, double Function(double minute)? xOf) {
    final table = AuxCalendarStore.shared?.table(altCal);
    if (table == null) return AxisHit.none;
    final j = dayAt(yearAt(at)).j;
    if (calDay) {
      final date = table.dateOfJdn(j);
      if (date == null) return AxisHit.none;
      final start = xOf == null ? x : xOf(minuteOfYear(tOfJdn(j)));
      return AxisHit(
        AxisHitKind.none, key: altCal, row: index,
        tip: '${table.dayText(j)} = ${_civilDayText(j)}',
        x: start < left ? left : start,
      );
    }
    final month = table.monthOfJdn(j);
    if (month == null) return AxisHit.none;
    final start = xOf == null ? x : xOf(minuteOfYear(tOfJdn(month.startJdn)));
    return AxisHit(
      AxisHitKind.none, key: altCal, row: index,
      tip: '${table.name} ${table.yearName(month.year)} ${table.monthName(month)} — ${_civilDayText(month.startJdn)}부터',
      x: start < left ? left : start,
    );
  }

  /// 날 번호 → 서력 날짜 글(지금 연표의 `HT.cal.formatT(t, 'd')`). 1582-10-15 앞은 율리우스력이다.
  static String _civilDayText(int jdn) {
    final c = civilOf(jdn);
    final year = fromAstro(c.y);
    return '${year < 0 ? '기원전 ${-year}년' : '$year년'} ${c.m}월 ${c.d}일';
  }

  AxisHit _anyLane(AxisRow row, double at, int index, double Function(AxisCell) leftOf) {
    for (final c in row.data!.cells) {
      if (at >= c.start && at <= c.end) return AxisHit(AxisHitKind.eraCell, track: row.track!.id, cell: c, row: index, x: leftOf(c));
    }
    return AxisHit.none;
  }

  AxisHit _capHit(AxisRow row, int index, double y, double at, int lane, double Function(AxisCell) leftOf) {
    final base = row.contentTop + row.lanes * capHeight + 1;
    if (row.secOpen && y >= base) {
      final secLane = ((y - base) / secHeight).floor();
      for (final c in row.data!.sec) {
        if (c.lane != secLane || at < c.start || at > c.end) continue;
        return AxisHit(AxisHitKind.secCell, track: row.track!.id, cell: c, row: index, x: leftOf(c));
      }
      return AxisHit.none;
    }
    for (final c in row.data!.cells) {
      if (c.lane != lane || at < c.start || at > c.end) continue;
      return AxisHit(AxisHitKind.capCell, track: row.track!.id, cell: c, row: index, x: leftOf(c));
    }
    return AxisHit.none;
  }

  static double _laneHeight(AxisRowKind kind) => switch (kind) {
    AxisRowKind.epoch => epochHeight,
    AxisRowKind.era => eraHeight,
    AxisRowKind.cap => capHeight,
    _ => 1,
  };
}

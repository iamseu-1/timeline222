import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scene/color_mix.dart';
import '../scene/fonts.dart';
import '../scene/marks.dart';
import '../scene/viewport.dart';
import '../shell/line_icon.dart';
import '../shell/look.dart';
import '../shell/motion_widgets.dart';
import 'app_bus.dart';
import 'date_text.dart';
import 'shell_keys.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  도읍 노선도 카드 — 지금 연표의 `js/timeline.js` 5326~5622(`_metroHTML` · `showMetro` · `hideMetro` · `_bindMetro`)
//  와 `css/common.css` 1008~1082 · 1468~1470. 명세 `docs/명세-3단계/06-상세-검색-필터-도구.md`의 4-2 · 7-19.
//
//  도읍이 여럿인 정권의 도읍 내력을 지하철 노선도처럼 보인다:
//    · 본선   = 정도(같은 도시로 돌아오면 한 역에 합친다)
//    · 위 지선 = 배도(같은 도시 · 같은 묶음은 하나로, 넷까지)
//    · 아래 점선 우회 = 임시 도읍
//    · 겹고리 = 다른 나라와 같은 도시(환승)
//  가로는 **시간이 아니라 차례**다(역 사이 최소 60px · 이름 폭을 먼저 재서 넓힌다).
//
//  ── 혼자 서는 부품이다(AppBus 하나만 받는다) ──────────────────────────────────────────────────
//    bus.slot('metro')  = 정권 uid(글) 또는 [MetroRequest](uid + 줄 이름의 자리 + 고정 여부).
//                         상세 창의 `🚇 노선도`가 이미 uid를 싣는다(`detail_item.dart`).
//                         null이면 닫힌다.
//    bus.slot('command') = [Cmd.close](Esc)로 닫힌다.
//    bus.selection       ← 다른 항목을 고르면 닫힌다.
//    bus.ask({'op':'entity','uid':…})  — 정권 기록의 `capitals`와 `x_metro`(계약 6-9 가 · `scripts/export/metro.mjs`)
//    bus.goTo            — 역을 누르면 그 도읍 기간으로(앞뒤로 기간의 20% · 적어도 6년을 두고)
//    SceneMarks.of(bus.scene).hotCity — 도시에 손을 올리면 날짜 칸의 같은 이름 도읍 칸만 밝다
//
//  ── 앱에 끼우는 법 ───────────────────────────────────────────────────────────────────────────
//    Stack(children: [ …연표…, MetroCard(bus: bus, gutter: SceneView.gutter, head: v.head) ])
//    닫혀 있으면 아무 자리도 차지하지 않는다(`SizedBox.shrink`). 열리면 그 Stack 안에서 스스로 자리를 잡는다.
//
//  ── 자료가 모자랄 때 ─────────────────────────────────────────────────────────────────────────
//    `x_metro`가 없는 저장소(아직 `export-layout.mjs`의 MODULES에 'metro'를 더하지 않은 것)에서도
//    **조용히 비지 않는다**: 도읍 칸만으로 본선 · 지선 · 우회를 그리고 날짜 글은 `date_text.dart`로 만든다.
//    x_metro가 있으면 환승(겹고리 · `⇄` 칩) · 발의 다른 정권 단추 · 지금 연표와 똑같은 날짜 글이 더해진다.
//    기록조차 읽지 못하면 카드를 열지 않고 `bus.slot('notice')`에 한 줄을 남긴다(빈 카드를 띄우지 않는다).
// ════════════════════════════════════════════════════════════════════════════════════════════

/// [AppBus.slot]에 쓰는 이름 — `detail_item.dart`의 `🚇 노선도`가 쓰는 이름과 같아야 한다.
const metroSlot = 'metro';

/// 카드 한 장만 그림으로 뜰 때 붙잡는 열쇠(검사의 그림 뜨기 · 지금 연표의 카드와 1배로 맞대기).
const metroCardKey = ValueKey('노선도 카드');

/// 노선도를 열어 달라는 부탁. 슬롯에는 글(uid)만 실어도 된다 — 자리를 함께 주면 그 옆에 선다.
@immutable
class MetroRequest {
  const MetroRequest(this.uid, {this.anchor, this.pinned = false});

  final String uid;

  /// 카드가 가리킬 것의 자리(연표 영역 안의 좌표) — 왼쪽 칸의 노선 표시. 없으면 왼쪽 칸 오른쪽에 선다.
  final Rect? anchor;

  /// 처음부터 고정으로 열까(손을 떼도 닫히지 않는다).
  final bool pinned;

  @override
  bool operator ==(Object other) => other is MetroRequest && other.uid == uid && other.anchor == anchor && other.pinned == pinned;
  @override
  int get hashCode => Object.hash(uid, anchor, pinned);
}

/// 슬롯에 실린 값에서 정권 uid를 읽는다(글 · [MetroRequest] 둘 다 받는다). 없으면 빈 글.
String metroUidOf(Object? value) {
  if (value is MetroRequest) return value.uid;
  if (value is String) return value.trim();
  return '';
}

/// 카드의 색 · 치수 · 시간 — css의 `.tl-metro`와 `.m-*`. 앱 틀과 함께 쓰는 값은 [Ui]에 있다.
abstract final class MetroLook {
  /// 연표 안쪽의 종이색(css `.tl` 안의 `--paper` 무리). 카드는 연표 위에 뜨므로 이 무리를 쓴다.
  static const paperInt = 0xffffffff, paper2Int = 0xfff5f5f5, inkInt = 0xff000000, mutedInt = 0xff666666, lineInt = 0xffcccccc;
  static const paper = Color(paperInt), paper2 = Color(paper2Int), ink = Color(inkInt), muted = Color(mutedInt), line = Color(lineInt);

  /// 카드: 폭 300부터 · 안쪽 여백 12/14/10 · 둥근 12 · 뒤 흐림 없음 · 바탕은 `--paper` 90%.
  static const minWidth = 300.0, radius = Ui.menuRadius, blur = 0.0;
  static const padding = EdgeInsets.fromLTRB(14, 12, 14, 10);
  static const back = Color(0xe6ffffff);

  /// 줄 이름을 가리키는 꼭지(`.has-tip::before`) — 11×11 마름모가 왼쪽 −6에.
  static const nub = 11.0, nubLeft = -6.0, nubInset = 18.0;

  /// 머리: 사이 8 · 아래 8 · 색 점 10(둘레 1.5) · 이름 15/700 · 곁글 11.5 · 단추 28(둥근 9 · 12px).
  static const headGap = 8.0, headBelow = 8.0, dot = 10.0, dotRing = 1.5;
  static const nameSize = 15.0, sumSize = 11.5, button = 28.0, buttonRadius = 9.0, buttonSize = 12.0;

  /// 범례: 위 2 · 사이 4/12 · 10px · 표시 폭 16.
  static const legendTop = 2.0, legendGapX = 12.0, legendGapY = 4.0, legendSize = 10.0, legendMark = 16.0, legendInner = 5.0;

  /// 발: 위 8 · 위 여백 8 · 사이 5 · 단추 11px(위아래 2 · 좌우 9) · 안내 10px.
  static const footTop = 8.0, footGap = 5.0, peerSize = 11.0, hintSize = 10.0;
  static const peerPadding = EdgeInsets.symmetric(horizontal: 9, vertical: 2);

  /// 글줄 사이(css `.tl-metro { line-height: 1.3 }`).
  static const lineHeight = 1.3;

  /// 이름표: 역 이름 12/700 · 배도 11.5/700 · 작은 글 10 · 환승 칩 9.5/600(줄 높이 16 · 좌우 6).
  static const labelSize = 12.0, secLabelSize = 11.5, subSize = 10.0, chipSize = 9.5, chipHeight = 16.0, chipPad = 6.0;

  /// 도형: 본선 6 · 우회 3.5(점선 6/5) · 지선 3 · 역 테두리 3(가장 오래 머문 역 3.5 · 임시 2.5 점선 3/2 · 배도 2.5) ·
  /// 빈 자리 2.4(점선 4/4) · 환승 고리 1.5 · 미정 구간 6(점선 6/5)과 그 아래 덮개 8.
  static const mainWidth = 6.0, detourWidth = 3.5, branchWidth = 3.0;
  static const stopWidth = 3.0, stopMainWidth = 3.5, stopTempWidth = 2.5, stopSecWidth = 2.5;
  static const vacantWidth = 2.4, xferWidth = 1.5, unknownWidth = 6.0, gapWidth = 8.0;
  static const stopRadius = 6.0, stopMainRadius = 7.5, stopSecRadius = 4.5, endRadius = 4.5;
  static const xferStation = 11.0, xferDetour = 10.0, xferBranch = 8.5;

  /// 자리 잡기: 줄 이름에서 오른쪽 12 · 그 가운데보다 34 위 · 가장자리 8.
  static const anchorGap = 12.0, anchorRise = 34.0, edgeGap = 8.0;

  /// 카드가 없는 자리에서 열릴 때(상세 창의 `🚇`): 왼쪽 칸 오른쪽 16 · 날짜 칸 아래 12.
  static const looseLeft = 16.0, looseTop = 12.0;

  /// 뜨는 시간 200 · 지는 시간 160(`docs/움직임-원칙.md`) — 4px 떠오르며 .985배에서 제 크기로.
  static const enter = Duration(milliseconds: 200), leave = Duration(milliseconds: 160);
  static const rise = 4.0, scaleFrom = .985;
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 값 — 정권 기록 하나를 카드가 읽는 꼴로
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 같은 도시를 쓴 다른 정권 하나(환승). [all]은 잘려 실렸을 때의 전체 수(첫 칸에만 있다).
@immutable
class MetroXfer {
  const MetroXfer({required this.uid, required this.name, required this.color, this.cell = '', this.year = '', this.all = 0});
  final String uid, name, cell, year;
  final Color color;
  final int all;
}

/// 발의 다른 정권 단추 하나.
@immutable
class MetroPeer {
  const MetroPeer(this.uid, this.name, this.color);
  final String uid, name;
  final Color color;
}

/// 도읍 칸 하나.
@immutable
class MetroCapital {
  const MetroCapital({
    required this.index,
    required this.city,
    required this.name,
    required this.start,
    required this.endY,
    this.label = '',
    this.role = 'main',
    this.group = '',
    this.note = '',
    this.when = '',
    this.alts = const [],
    this.startUnknown = false,
    this.endUnknown = false,
  });

  /// 기록의 `capitals` 안 차례(칸 참조 `capital:<index>`와 같은 번호).
  final int index;

  /// 도시 이름(환승을 가리는 열쇠) · 그때의 이름(`as` 또는 도시) · 칸에 적는 딴이름.
  final String city, name, label;

  /// `main` · `secondary` · `temporary` · `exile` · `co`.
  final String role;

  /// 배도 묶음 이름(같은 묶음의 배도는 지선 하나).
  final String group, note;

  /// 역 설명글의 기간 글 · 다른 견해 글(x_metro가 미리 푼 것).
  final String when;
  final List<String> alts;

  /// 해 좌표(모델의 값 그대로 — `bus.goTo`에 넘길 때만 분으로 옮긴다).
  final double start, endY;
  final bool startUnknown, endUnknown;

  bool get secondary => role == 'secondary';
  bool get temporary => role == 'temporary';

  /// 날짜 칸의 도읍 칸에 적히는 이름(`scripts/export/axis.mjs`의 `c.label || c.name`) — 같은 이름을 비출 때 쓴다.
  String get axisName => label.isNotEmpty ? label : name;
}

/// 카드 하나가 읽는 정권.
@immutable
class MetroData {
  const MetroData({
    required this.uid,
    required this.name,
    required this.color,
    required this.start,
    required this.endY,
    required this.capitals,
    this.ongoing = false,
    this.range = '',
    this.endLabel = '',
    this.xfer = const {},
    this.peers = const [],
  });

  final String uid, name;
  final Color color;
  final double start, endY;
  final bool ongoing;

  /// 머리의 기간 글 · 끝 역 아래의 해.
  final String range, endLabel;

  final List<MetroCapital> capitals;

  /// 도시 → 그 도시를 쓴 다른 정권들(x_metro가 없으면 빈 표).
  final Map<String, List<MetroXfer>> xfer;
  final List<MetroPeer> peers;

  /// 도읍이 하나도 없으면 카드를 열지 않는다.
  bool get empty => capitals.isEmpty;

  /// 답 `{uid, kind, json}`을 푼다. 정권 기록이 아니거나 도읍이 없으면 null.
  static MetroData? fromAnswer(Map<String, dynamic> answer) {
    final json = _jsonOf(answer['json']);
    if (json == null) return null;
    final uid = _string(json['uid']).isNotEmpty ? _string(json['uid']) : _string(answer['uid']);
    final raw = json['capitals'];
    if (raw is! List || raw.isEmpty) return null;
    final x = json['x_metro'] is Map ? (json['x_metro'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final when = x['when'] is List ? (x['when'] as List).map(_string).toList() : const <String>[];
    final alts = x['alts'] is Map ? (x['alts'] as Map) : const {};

    final capitals = <MetroCapital>[];
    for (int i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (c is! Map) continue;
      final cell = c.cast<String, dynamic>();
      final start = _number(cell['start']);
      if (start == null) continue;
      final city = _string(cell['city']);
      final name = _string(cell['name']).isNotEmpty ? _string(cell['name']) : city;
      final altList = alts['$i'];
      capitals.add(
        MetroCapital(
          index: i,
          city: city,
          name: name,
          label: _string(cell['label']),
          role: _string(cell['role']).isEmpty ? 'main' : _string(cell['role']),
          group: _string(cell['group']),
          note: _string(cell['note']),
          start: start,
          endY: _number(cell['endY']) ?? _number(cell['end']) ?? start,
          startUnknown: cell['startUnknown'] == true,
          endUnknown: cell['endUnknown'] == true || cell['endYAuto'] == true,
          when: i < when.length ? when[i] : _rangeOf(cell, start, json['ongoing'] == true || x['ongoing'] == 1),
          alts: altList is List ? [for (final a in altList) _string(a)] : const [],
        ),
      );
    }
    if (capitals.isEmpty) return null;

    final xfer = <String, List<MetroXfer>>{};
    final rawXfer = x['xfer'];
    if (rawXfer is Map) {
      for (final entry in rawXfer.entries) {
        final list = entry.value;
        if (list is! List || list.isEmpty) continue;
        xfer['${entry.key}'] = [
          for (final one in list)
            if (one is Map)
              MetroXfer(
                uid: _string(one['uid']),
                name: _string(one['name']),
                color: _color(_string(one['color'])) ?? Ui.text3,
                cell: _string(one['cell']),
                year: _string(one['year']),
                all: (_number(one['all']) ?? 0).round(),
              ),
        ];
      }
    }

    final peers = <MetroPeer>[];
    final rawPeers = x['peers'];
    if (rawPeers is List) {
      for (final one in rawPeers) {
        if (one is! Map) continue;
        final id = _string(one['uid']);
        if (id.isEmpty) continue;
        peers.add(MetroPeer(id, _string(one['name']), _color(_string(one['color'])) ?? Ui.text3));
      }
    }

    final start = _number(json['start']) ?? capitals.first.start;
    final endY = _number(json['endY']) ?? _number(json['end']) ?? capitals.last.endY;
    final ongoing = json['ongoing'] == true || x['ongoing'] == 1;
    return MetroData(
      uid: uid,
      name: _string(json['name']),
      color: _color(_string(json['color'])) ?? Ui.text3,
      start: start,
      endY: endY,
      ongoing: ongoing,
      range: _string(x['range']).isNotEmpty
          ? _string(x['range'])
          : rangeText(start: start, end: endY, ongoing: ongoing, startUnknown: json['startUnknown'] == true, endUnknown: json['endUnknown'] == true),
      endLabel: _string(x['end']).isNotEmpty ? _string(x['end']) : bcYearText(endY),
      capitals: capitals,
      xfer: xfer,
      peers: peers,
    );
  }

  /// x_metro가 없을 때의 칸 기간 글 — 지금 연표의 `cellRange(c, 'endY', null, p)`와 같은 규칙.
  static String _rangeOf(Map<String, dynamic> cell, double start, bool ongoing) {
    final s = cell['startUnknown'] == true ? '미정' : whenText(start, at: _string(cell['startAt']).isEmpty ? null : _string(cell['startAt']));
    if (cell['endUnknown'] == true || cell['endYAuto'] == true) return '$s ~ 미정';
    // 끝을 비운 칸이 진행 중인 정권의 끝까지 간다(HT.cellToNow).
    if (cell['toNow'] == true || (ongoing && (cell['endPolity'] == true || (cell['end'] == null && cell['endYNext'] != true)))) return '$s ~ 현재';
    final end = _number(cell['endY']);
    if (end == null) return '$s ~';
    final at = _string(cell['endYAt']).isNotEmpty ? _string(cell['endYAt']) : _string(cell['endAt']);
    return '$s ~ ${whenText(end, at: at.isEmpty ? null : at)}';
  }
}

/// 지금 연표의 `bcYear` — 역 이름 아래의 해(기원전은 `BC 960`).
String bcYearText(double t) {
  final year = civilAt(t).year;
  return year < 0 ? 'BC ${-year}' : '$year';
}

Map<String, dynamic>? _jsonOf(Object? raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is String && raw.isNotEmpty) {
    try {
      final v = jsonDecode(raw);
      if (v is Map) return v.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
  return null;
}

String _string(Object? v) => v == null ? '' : '$v';
double? _number(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
Color? _color(String text) {
  if (text.length != 7 || !text.startsWith('#')) return null;
  final v = int.tryParse(text.substring(1), radix: 16);
  return v == null ? null : Color(0xff000000 | v);
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 도형 셈 — 지금 연표의 `_metroHTML`을 숫자 그대로
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 글자 폭을 재는 길. 검사에서 갈아 끼울 수 있게 함수로 받는다(브라우저의 `measureText`에 해당).
typedef MetroMeasure = double Function(String text, double size, int weight);

/// 환승 칩 하나(`.m-x`).
@immutable
class MetroChip {
  const MetroChip({required this.uid, required this.color, required this.text, required this.tip});
  final String uid, text, tip;
  final Color color;
}

/// 본선의 역 하나. [detour]면 아래 점선 우회(임시 도읍)다.
class MetroNode {
  MetroNode({required this.detour, required this.head}) : periods = [head], names = [head.name];

  final bool detour;

  /// 이 역을 만든 첫 칸(지금 연표의 `n.c`) · 합쳐진 칸들 · 합쳐진 이름들.
  final MetroCapital head;
  final List<MetroCapital> periods;
  final List<String> names;

  String labelName = '', labelSub = '';
  double labelWidth = 0, x = 0;
  MetroChip? chip;

  /// 이 역이 품는 기간(해 좌표) — 누르면 갈 곳.
  double get from => periods.first.start;
  double get to => periods.last.endY;

  /// 머문 기간의 합(가장 오래 머문 역을 가린다).
  double get stay => periods.fold(0.0, (sum, c) => sum + (c.endY - c.start));
}

/// 배도 지선 하나 — 같은 도시 · 같은 묶음은 하나로 묶는다.
class MetroBranch {
  MetroBranch({required this.name, required this.city, required this.head, required this.start, required this.endY, required this.startUnknown, required this.endUnknown});

  final String name, city;

  /// 묶음의 첫 칸(설명글과 비출 이름에 쓴다).
  final MetroCapital head;
  double start, endY;
  bool startUnknown, endUnknown;

  double x = 0, y = 0, width = 0;
  String text = '';
  MetroChip? chip;
}

/// 카드 하나의 도형. 값은 모두 지금 연표의 `_metroHTML`에서 그대로 옮겼다.
class MetroPlan {
  MetroPlan._({
    required this.nodes,
    required this.branches,
    required this.hiddenBranches,
    required this.dashes,
    required this.mainY,
    required this.mainFrom,
    required this.xEnd,
    required this.mapWidth,
    required this.mapHeight,
    required this.longest,
    required this.endName,
    required this.endSub,
    required this.seats,
    required this.secondaries,
    required this.moves,
    required this.hasXfer,
  });

  /// 우회선의 반폭 · 역 사이 최소 · 첫 역의 자리.
  static const detourHalf = 28.0, minGap = 60.0, firstX = 28.0;

  /// 지선은 넷까지만 보인다.
  static const maxBranches = 4;

  final List<MetroNode> nodes;
  final List<MetroBranch> branches;
  final int hiddenBranches;

  /// 경계가 미정이라 점선으로 긋는 본선 구간들.
  final List<(double, double)> dashes;

  final double mainY, mainFrom, xEnd, mapWidth, mapHeight;
  final MetroNode? longest;
  final String endName, endSub;

  /// 머리의 곁글에 적는 수.
  final int seats, secondaries, moves;
  final bool hasXfer;

  bool get hasDetour => nodes.any((n) => n.detour);

  /// [data]의 도읍 칸에서 노선도를 셈한다. [measure]는 글자 폭을 재는 길.
  static MetroPlan of(MetroData data, MetroMeasure measure) {
    final caps = [...data.capitals]
      ..sort((a, b) {
        final by = a.start.compareTo(b.start);
        return by != 0 ? by : a.endY.compareTo(b.endY);
      });
    List<MetroXfer> others(String city) => city.isEmpty ? const [] : (data.xfer[city] ?? const []);

    // 본선의 역: 같은 도시로 돌아오면 한 역에 합친다(임시 도읍 하나는 건너뛰고 본다).
    final nodes = <MetroNode>[];
    for (final c in caps) {
      if (c.secondary) continue;
      if (c.temporary) {
        nodes.add(MetroNode(detour: true, head: c));
        continue;
      }
      final prev = nodes.isEmpty ? null : nodes.last;
      final back = prev != null && prev.detour ? (nodes.length >= 2 ? nodes[nodes.length - 2] : null) : prev;
      if (back != null && !back.detour && back.head.city == c.city) {
        back.periods.add(c);
        if (!back.names.contains(c.name)) back.names.add(c.name);
        continue;
      }
      nodes.add(MetroNode(detour: false, head: c));
    }

    // 배도 지선: 같은 도시 · 같은 묶음은 하나로.
    final branches = <MetroBranch>[];
    final byKey = <String, MetroBranch>{};
    for (final c in caps.where((c) => c.secondary)) {
      final key = c.group.isNotEmpty ? c.group : c.city;
      final had = byKey[key];
      if (had != null) {
        if (c.start < had.start) had.startUnknown = c.startUnknown;
        if (c.endY > had.endY) had.endUnknown = c.endUnknown;
        had.start = math.min(had.start, c.start);
        had.endY = math.max(had.endY, c.endY);
        continue;
      }
      final made = MetroBranch(
        name: c.group.isNotEmpty ? c.group : c.name,
        city: c.group.isNotEmpty ? '' : c.city,
        head: c,
        start: c.start,
        endY: c.endY,
        startUnknown: c.startUnknown,
        endUnknown: c.endUnknown,
      );
      byKey[key] = made;
      branches.add(made);
    }
    final shown = branches.length > maxBranches ? branches.sublist(0, maxBranches) : branches;

    final seatCities = {for (final c in caps.where((c) => !c.secondary)) c.city};
    final secCities = {for (final c in caps.where((c) => c.secondary && !seatCities.contains(c.city))) c.city};
    int moves = 0;
    final seats = caps.where((c) => !c.secondary).toList();
    for (int i = 1; i < seats.length; i++) {
      if (seats[i - 1].city != seats[i].city) moves++;
    }

    double chipWidth(MetroChip? chip) => chip == null ? 0 : measure(chip.text, MetroLook.chipSize, 600) + 14;
    MetroChip? chipOf(List<MetroXfer> ex) {
      if (ex.isEmpty) return null;
      final all = ex.first.all > ex.length ? ex.first.all : ex.length;
      return MetroChip(
        uid: ex.first.uid,
        color: ex.first.color,
        text: '⇄ ${ex.first.name}${all > 1 ? ' 외 ${all - 1}' : ''}',
        tip: '같은 도시 · ${ex.map((u) => '${u.name} ${u.cell} ${u.year}–').join(' · ')}',
      );
    }

    String startYear(MetroCapital c) => c.startUnknown ? '미정' : bcYearText(c.start);

    for (final n in nodes) {
      final chip = chipOf(others(n.head.city));
      final name = n.names.join('·') + (n.head.label.isNotEmpty && !n.names.contains(n.head.label) ? ' (${n.head.label})' : '');
      final sub = n.detour
          ? '${startYear(n.head)}–${n.head.endUnknown ? '미정' : bcYearText(n.head.endY)} · 임시'
          : n.periods.map(startYear).join(' · ') + (n.head.role == 'exile' ? ' · 망명' : (n.head.role == 'co' ? ' · 공동' : ''));
      n.chip = chip;
      n.labelName = name;
      n.labelSub = sub;
      n.labelWidth = math.max(measure(name, MetroLook.labelSize, 700), measure(sub, MetroLook.subSize, 500)) + (chip == null ? 0 : chipWidth(chip) + 4) + 2;
    }

    // 역의 가로 자리: 시간이 아니라 차례. 앞 역의 이름 폭만큼 띄운다.
    double x = firstX;
    double lowRight = double.negativeInfinity; // 아래 줄(임시 도읍 이름표)의 오른쪽 끝
    for (int i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (i == 0) {
        x = n.detour ? math.max(firstX + detourHalf, n.labelWidth / 2 + 10) : firstX;
      } else {
        final prev = nodes[i - 1];
        if (!prev.detour) {
          x += math.max(minGap, prev.labelWidth + (n.detour ? detourHalf + 4 : 14));
        } else {
          x += math.max(minGap, math.max(detourHalf + 16, n.detour ? 2 * detourHalf + 16 : 0));
        }
      }
      if (n.detour) {
        x = math.max(x, lowRight + 14 + n.labelWidth / 2);
        lowRight = x + n.labelWidth / 2;
      }
      n.x = x;
    }

    final last = nodes.isEmpty ? null : nodes.last;
    final endName = data.ongoing ? '지금' : '끝';
    final endSub = data.ongoing ? '' : data.endLabel;
    final endWidth = math.max(measure(endName, MetroLook.labelSize, 700), measure(endSub, MetroLook.subSize, 500)) + 4;
    final xEnd = last == null ? firstX + minGap : x + math.max(minGap - 8, last.detour ? detourHalf + 16 : last.labelWidth + 14);

    // 지선은 그 해에 있던 본선 역에서 위로. 왼쪽 지선일수록 높이 올려 이름표와 세로선이 엇갈리지 않게.
    double anchorOf(double y) {
      int k = nodes.indexWhere((n) => !n.detour && n.periods.any((c) => c.start <= y && y < c.endY));
      if (k < 0) {
        for (int i = 0; i < nodes.length; i++) {
          if (!nodes[i].detour && nodes[i].head.start <= y) k = i;
        }
      }
      if (k < 0) k = math.max(0, nodes.indexWhere((n) => !n.detour));
      return nodes.isEmpty ? firstX : nodes[k].x;
    }

    final perAnchor = <double, int>{};
    for (final b in shown) {
      final ax = anchorOf(b.start);
      final j = perAnchor[ax] ?? 0;
      perAnchor[ax] = j + 1;
      final chip = chipOf(others(b.city));
      b.chip = chip;
      b.text = '${b.startUnknown ? '미정' : bcYearText(b.start)}–';
      b.x = ax + 13 + j * 11;
      b.width = measure(b.name, MetroLook.secLabelSize, 700) + 4 + measure(b.text, MetroLook.subSize, 500) + (chip == null ? 0 : chipWidth(chip) + 6) + 4;
    }
    shown.sort((a, b) => a.x.compareTo(b.x));
    final levels = shown.length;
    final mainY = levels > 0 ? 45 + (levels - 1) * 26.0 : 20.0;
    for (int i = 0; i < levels; i++) {
      shown[i].y = mainY - 28 - (levels - 1 - i) * 26;
    }

    final hasDetour = nodes.any((n) => n.detour);
    final mapHeight = mainY + (hasDetour ? 76 : 46);
    double width = math.max(xEnd - 8 + endWidth + 10, 260);
    if (lowRight.isFinite) width = math.max(width, lowRight + 10);
    for (final b in shown) {
      width = math.max(width, b.x + 30 + b.width + 8);
    }

    // 경계(뒤 역의 시작이나 앞 역의 끝)가 미정이면 그 사이 본선이 점선 — 역 동그라미 · 우회선 자리는 피해서.
    bool unknownBefore(MetroNode n) => !n.detour && n.periods.first.startUnknown;
    bool unknownAfter(MetroNode n) => !n.detour && n.periods.last.endUnknown;
    double rightOf(MetroNode n) => n.x + (n.detour ? detourHalf : 12);
    final dashes = <(double, double)>[];
    void dash(double a, double b) {
      if (b - a >= 8) dashes.add((a, b));
    }

    for (int i = 1; i < nodes.length; i++) {
      final n = nodes[i];
      if (unknownBefore(n) || unknownAfter(nodes[i - 1])) dash(rightOf(nodes[i - 1]), n.x - (n.detour ? detourHalf : 12));
    }
    if (last != null && unknownAfter(last)) dash(rightOf(last), xEnd - 7);

    MetroNode? longest;
    for (final n in nodes) {
      if (n.detour) continue;
      if (longest == null || n.stay > longest.stay) longest = n;
    }

    return MetroPlan._(
      nodes: nodes,
      branches: shown,
      hiddenBranches: branches.length - shown.length,
      dashes: dashes,
      mainY: mainY,
      mainFrom: nodes.isEmpty ? firstX : (nodes.first.detour ? nodes.first.x - detourHalf : nodes.first.x),
      xEnd: xEnd,
      mapWidth: width.ceilToDouble(),
      mapHeight: mapHeight,
      longest: longest,
      endName: endName,
      endSub: endSub,
      seats: seatCities.length,
      secondaries: secCities.length,
      moves: moves,
      hasXfer: caps.any((c) => others(c.city).isNotEmpty),
    );
  }

  /// 머리의 곁글 — `도읍 3곳 · 배도 2곳 · 천도 3번 · 720년 ~ 960년`.
  String summary(String range) => '도읍 $seats곳${secondaries > 0 ? ' · 배도 $secondaries곳' : ''} · 천도 $moves번${range.isEmpty ? '' : ' · $range'}';

  /// 카드의 폭 — css의 `width: max-content`를 그대로 셈한다(머리 · 노선도 · 범례 · 발 가운데 가장 넓은 것).
  /// `min-width: 300` 아래로는 줄지 않고 [maxWidth]를 넘지 않는다(넘치면 노선도가 옆으로 굴러간다).
  double cardWidth(MetroData data, MetroMeasure measure, double maxWidth) {
    final head = MetroLook.dot + MetroLook.headGap * 4 + measure(data.name, MetroLook.nameSize, 700) + measure(summary(data.range), MetroLook.sumSize, 400) + MetroLook.button * 2;
    final legendText = <String>['정도', if (branches.isNotEmpty) '배도(지선)', if (hasDetour) '임시(우회)', if (hasXfer) '같은 도시(환승)'];
    double legend = 0;
    for (final one in legendText) {
      legend += MetroLook.legendMark + MetroLook.legendInner + measure(one, MetroLook.legendSize, 400) + MetroLook.legendGapX;
    }
    if (hiddenBranches > 0) legend += measure('배도 외 $hiddenBranches곳', MetroLook.legendSize, 400) + MetroLook.legendGapX;
    if (legend > 0) legend -= MetroLook.legendGapX;
    double foot = measure('역을 누르면 그 시기로${data.peers.length > 1 ? ' · ← → 다른 정권' : ''}', MetroLook.hintSize, 400) + MetroLook.footTop;
    if (data.peers.length > 1) {
      for (final q in data.peers) {
        foot += measure(q.name, MetroLook.peerSize, q.uid == data.uid ? 700 : 400) + MetroLook.peerPadding.horizontal + MetroLook.footGap;
      }
      foot -= MetroLook.footGap;
    }
    final inner = math.max(math.max(head, mapWidth), math.max(legend, foot));
    return (inner + MetroLook.padding.horizontal).clamp(MetroLook.minWidth, math.max(MetroLook.minWidth, maxWidth));
  }
}

/// 누르면 갈 기간(분) — 지금 연표의 `setView(a - pad, b + pad)`와 같은 값(앞뒤로 기간의 20% · 적어도 6년).
(double, double) metroViewOf(double from, double to) {
  final b = math.max(to, from + 1);
  final pad = math.max(6.0, (b - from) * .2);
  return (minutesOfT(from - pad), minutesOfT(b + pad));
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 부품 — 슬롯을 듣고 뜨고 지는 카드
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 도읍 노선도 카드. `bus.slot('metro')`에 실린 정권을 듣고 열리고 닫힌다.
/// Stack의 자식으로 놓는다 — 닫혀 있으면 아무 자리도 차지하지 않는다.
class MetroCard extends StatefulWidget {
  const MetroCard({super.key, required this.bus, this.gutter = SceneView.gutter, this.head = SceneView.rulerHeight});

  final AppBus bus;

  /// 왼쪽 칸의 폭 · 날짜 칸의 높이 — 가리킬 것이 없을 때 카드가 설 자리를 정한다.
  final double gutter, head;

  @override
  State<MetroCard> createState() => MetroCardState();
}

class MetroCardState extends State<MetroCard> with SingleTickerProviderStateMixin {
  late final SurfaceMotion _enter = SurfaceMotion();

  String _uid = '';
  MetroData? _data;
  Rect? _anchor;
  bool _pinned = false;
  Selection? _picked;
  int _turn = 0;

  /// 지는 중인가 — 닫아도 곧바로 털지 않고 160ms 되감고 나서 턴다. 그동안 카드는 서 있되 손길은 받지 않는다.
  bool _leaving = false;

  /// 지난번에 잡아 둔 자리(가리킬 것 없이 다시 그릴 때 제자리를 지킨다).
  Offset? _kept;

  AppBus get _bus => widget.bus;

  /// 지금 열려 있는 정권(닫혀 있거나 지는 중이면 빈 글) — 검사와 앱 틀이 본다.
  String get openUid => _data == null || _leaving ? '' : _uid;
  bool get pinned => _pinned;

  /// 지는 중인가 · 뜨고 진 정도(0~1) — 움직임(나타남 200 · 사라짐 160)을 재는 검사가 본다.
  bool get leaving => _leaving;
  double get enterValue => _enter.value;

  @override
  void initState() {
    super.initState();
    _bus.slot(metroSlot).addListener(_onSlot);
    _bus.slot(slotCommand).addListener(_onCommand);
    _bus.selection.addListener(_onSelection);
    _onSlot();
  }

  @override
  void didUpdateWidget(MetroCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bus != widget.bus) {
      oldWidget.bus.slot(metroSlot).removeListener(_onSlot);
      oldWidget.bus.slot(slotCommand).removeListener(_onCommand);
      oldWidget.bus.selection.removeListener(_onSelection);
      _bus.slot(metroSlot).addListener(_onSlot);
      _bus.slot(slotCommand).addListener(_onCommand);
      _bus.selection.addListener(_onSelection);
      _onSlot();
    }
  }

  @override
  void dispose() {
    _bus.slot(metroSlot).removeListener(_onSlot);
    _bus.slot(slotCommand).removeListener(_onCommand);
    _bus.selection.removeListener(_onSelection);
    _lightCity(null);
    _enter.dispose();
    super.dispose();
  }

  // ── 여닫기 ────────────────────────────────────────────────────────────────────────────────

  void _onSlot() {
    final value = _bus.slot(metroSlot).value;
    final uid = metroUidOf(value);
    if (uid.isEmpty) {
      if (_uid.isEmpty && _data == null) return;
      _shut();
      return;
    }
    if (value is MetroRequest) {
      if (value.anchor != null) _anchor = value.anchor;
      _pinned = value.pinned;
    }
    if (uid == _uid && _data != null) {
      // 지는 도중에 같은 것을 다시 열었다 — 뒷정리를 취소하고(_turn) 그 자리에서 되올린다.
      if (_leaving) _turn++;
      _rise();
      setState(() {});
      return;
    }
    _load(uid);
  }

  void _onCommand() {
    final command = _bus.slot(slotCommand).value;
    if (command is AppCommand && command.name == Cmd.close && _data != null) close();
  }

  /// 다른 항목을 고르면 닫힌다(그 정권을 고른 것이면 그대로 둔다).
  void _onSelection() {
    if (_data == null) return;
    final now = _bus.selection.value;
    if (now == _picked) return;
    if (now != null && now.uid == _uid) {
      _picked = now;
      return;
    }
    close();
  }

  /// 노선도를 연다(바깥에서도 부를 수 있다).
  void open(String uid, {Rect? anchor, bool pinned = false}) {
    if (uid.isEmpty) return;
    _bus.slot(metroSlot).value = MetroRequest(uid, anchor: anchor, pinned: pinned);
  }

  void close() {
    if (_bus.slot(metroSlot).value == null) {
      _shut();
      return;
    }
    _bus.slot(metroSlot).value = null;
  }

  /// 닫기 — 160ms 되감고 나서 털어 낸다(`docs/움직임-원칙.md`의 사라짐 160).
  /// 되감는 동안 다시 열리면 [_turn]이 어긋나 아래의 뒷정리가 취소되고 [_rise]가 그 자리에서 되올린다.
  /// 움직임을 끄면(`MediaQuery.disableAnimations`) 지금 연표처럼 그 자리에서 곧바로 감춘다.
  void _shut() {
    _lightCity(null);
    _turn++;
    _pinned = false;
    if (_data == null || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _leaving = false;
      _clear();
      return;
    }
    final turn = _turn;
    setState(() => _leaving = true);
    void afterClose(AnimationStatus status) {
      if (status != AnimationStatus.dismissed) return;
      _enter.removeStatusListener(afterClose);
      if (!mounted || turn != _turn) return;
      _leaving = false;
      _clear();
    }

    _enter.addStatusListener(afterClose);
    _enter.reverse();
  }

  /// 다 진 카드를 털어 낸다.
  void _clear() {
    _anchor = null;
    _kept = null;
    _enter.value = 0;
    if (!mounted) {
      _uid = '';
      _data = null;
      return;
    }
    setState(() {
      _uid = '';
      _data = null;
    });
  }

  /// 뜨는 움직임 200 — 지는 중이었으면 그 자리에서 이어 올린다.
  void _rise() {
    _leaving = false;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _enter.value = 1;
    } else if (_enter.value == 0) {
      _enter.forward(from: 0);
    } else {
      _enter.forward();
    }
  }

  Future<void> _load(String uid) async {
    final turn = ++_turn;
    Map<String, dynamic>? answer;
    try {
      answer = await _bus.ask({'op': 'entity', 'uid': uid});
    } catch (_) {
      answer = null;
    }
    if (!mounted || turn != _turn) return;
    final data = answer == null ? null : MetroData.fromAnswer(answer);
    if (data == null || data.empty) {
      // 지금 연표와 같이 — 도읍이 없으면 카드를 열지 않는다(빈 카드를 띄우지 않는다).
      _bus.slot(slotNotice).value = '도읍 내력이 없어 노선도를 열 수 없습니다.';
      _bus.slot(metroSlot).value = null;
      _shut();
      return;
    }
    _picked = _bus.selection.value;
    _rise();
    setState(() {
      _uid = uid;
      _data = data;
    });
  }

  // ── 날짜 칸의 같은 이름 도읍 칸 비추기 ──────────────────────────────────────────────────────

  String? _hot;

  /// 도시 하나를 비춘다(벗어나면 null). 날짜 칸이 읽는 것은 **칸에 적힌 이름**이므로 그 이름을 싣는다
  /// (`scripts/export/axis.mjs`의 `c.label || c.name` · 배도는 묶음 이름).
  void _lightCity(String? name) {
    if (_hot == name) return;
    _hot = name;
    final scene = _bus.scene;
    final marks = SceneMarks.of(scene);
    marks.hotCity = name;
    marks.version++;
    scene.requestFrame();
  }

  // ── 누르기 ────────────────────────────────────────────────────────────────────────────────

  void _goTo(double from, double to) {
    final (lo, hi) = metroViewOf(from, to);
    _bus.goTo(lo, hi);
  }

  /// 📌 — 고정하면 손을 떼도 닫히지 않는다. 고정 여부는 슬롯에도 적어, 손 올리기로 여는 쪽(왼쪽 칸)이 읽을 수 있게 한다.
  void _togglePin() {
    _pinned = !_pinned;
    _bus.slot(metroSlot).value = MetroRequest(_uid, anchor: _anchor, pinned: _pinned);
    setState(() {});
  }

  void _switchTo(String uid) {
    if (uid.isEmpty || uid == _uid) return;
    _lightCity(null);
    _bus.slot(metroSlot).value = MetroRequest(uid, anchor: null, pinned: true);
  }

  void _step(int by) {
    final peers = _data?.peers ?? const <MetroPeer>[];
    if (peers.length < 2) return;
    final at = peers.indexWhere((q) => q.uid == _uid);
    if (at < 0) return;
    _switchTo(peers[(at + by + peers.length) % peers.length].uid);
  }

  // ── 그리기 ────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final plan = MetroPlan.of(data, measureMetroText);
    final mLine = Color(mixOklab(data.color.toARGB32(), MetroLook.inkInt, .72));
    final mSoft = Color(mixOklab(data.color.toARGB32(), MetroLook.paperInt, .48));

    return LayoutBuilder(
      builder: (context, box) {
        final maxWidth = math.max(260.0, box.maxWidth - 16);
        // 지는 동안(160ms)에는 손길을 받지 않는다 — 다 닫힌 카드에 손이 얹혀 날짜 칸이 다시 밝아지지 않게.
        final body = IgnorePointer(ignoring: _leaving, child: _card(data, plan, mLine, mSoft, maxWidth));
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _Placed(
              anchor: _anchor,
              area: Size(box.maxWidth, box.maxHeight),
              loose: _kept ?? Offset(widget.gutter + MetroLook.looseLeft, widget.head + MetroLook.looseTop),
              onPlaced: (at) => _kept = at,
              enter: _enter,
              child: body,
            ),
          ],
        );
      },
    );
  }

  Widget _card(MetroData data, MetroPlan plan, Color mLine, Color mSoft, double maxWidth) {
    final width = plan.cardWidth(data, measureMetroText, maxWidth);
    return RepaintBoundary(
      key: metroCardKey,
      child: SizedBox(
        width: width,
        child: Container(
          decoration: BoxDecoration(
            color: MetroLook.back,
            borderRadius: BorderRadius.circular(MetroLook.radius),
            boxShadow: _pinned ? const [BoxShadow(color: Color(0x8c000000), spreadRadius: 1.5)] : Ui.shadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(MetroLook.radius),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: MetroLook.blur / 2, sigmaY: MetroLook.blur / 2),
              child: Padding(
                padding: MetroLook.padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [_head(data, plan, mLine), _map(data, plan, mLine, mSoft), _legend(plan, mLine, mSoft), _foot(data, width - MetroLook.padding.horizontal)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 머리: `[색 점] 이름 [도읍 n곳 · 배도 n곳 · 천도 n번 · 기간] [📌] [✕]`.
  Widget _head(MetroData data, MetroPlan plan, Color mLine) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MetroLook.headBelow),
      child: Row(
        children: [
          Container(
            width: MetroLook.dot,
            height: MetroLook.dot,
            decoration: BoxDecoration(
              color: data.color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: mLine, spreadRadius: MetroLook.dotRing)],
            ),
          ),
          const SizedBox(width: MetroLook.headGap),
          Text(
            data.name,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontFamily: sceneFontFamily,
              fontFamilyFallback: sceneFontFallback,
              letterSpacing: 0,
              fontSize: MetroLook.nameSize,
              height: MetroLook.lineHeight,
              fontWeight: FontWeight.w700,
              color: MetroLook.ink,
            ),
          ),
          const SizedBox(width: MetroLook.headGap),
          Expanded(
            child: Text(
              plan.summary(data.range),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: sceneFontFamily,
                fontFamilyFallback: sceneFontFallback,
                letterSpacing: 0,
                fontSize: MetroLook.sumSize,
                height: MetroLook.lineHeight,
                color: MetroLook.muted,
              ),
            ),
          ),
          const SizedBox(width: MetroLook.headGap),
          _HeadButton(
            label: _pinned ? '고정 풀기' : '카드 고정',
            on: _pinned,
            onPressed: _togglePin,
            child: const LineIcon(LineGlyph.pushPin, size: MetroLook.buttonSize + 2, color: Ui.ink),
          ),
          const SizedBox(width: MetroLook.headGap),
          _HeadButton(
            label: '닫기 (Esc)',
            onPressed: close,
            child: const Text(
              '✕',
              style: TextStyle(fontSize: MetroLook.buttonSize, height: 1, color: MetroLook.muted),
            ),
          ),
        ],
      ),
    );
  }

  /// 노선도 자체 — 도형은 그림판 하나로, 이름표는 그 위에 얹는다(지금 연표의 svg + 절대 자리 span과 같은 꼴).
  Widget _map(MetroData data, MetroPlan plan, Color mLine, Color mSoft) {
    final labels = <Widget>[];
    for (final n in plan.nodes) {
      final boxWidth = metroLabelBox(n.labelName, n.labelSub, n.chip);
      labels.add(
        Positioned(
          left: n.detour ? n.x - n.labelWidth / 2 : n.x - 8,
          top: plan.mainY + (n.detour ? 44 : 14),
          width: boxWidth,
          child: _MetroLabel(
            name: n.labelName,
            sub: n.labelSub,
            chip: n.chip,
            center: n.detour,
            tip: _stationTip(n),
            onTap: () => _goTo(n.from, n.to),
            onHover: (on) => _lightCity(on ? n.head.axisName : null),
            onChip: _switchTo,
          ),
        ),
      );
    }
    labels.add(
      Positioned(
        left: plan.xEnd - 8,
        top: plan.mainY + 14,
        width: metroLabelBox(plan.endName, plan.endSub, null, muted: true),
        child: _MetroLabel(name: plan.endName, sub: plan.endSub, muted: true, tip: ''),
      ),
    );
    for (final b in plan.branches) {
      labels.add(
        Positioned(
          left: b.x + 30,
          top: b.y - 9,
          width: metroLabelBox(b.name, b.text, b.chip, inline: true),
          child: _MetroLabel(
            name: b.name,
            sub: b.text,
            chip: b.chip,
            inline: true,
            tip: '${b.name} 배도 · ${b.head.when}${b.head.alts.map((a) => '\n  다른 견해 — $a').join()}\n누르면 이 시기로',
            onTap: () => _goTo(b.start, b.endY),
            onHover: (on) => _lightCity(on ? b.name : null),
            onChip: _switchTo,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: plan.mapWidth,
        height: plan.mapHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _MetroPainter(plan: plan, line: mLine, soft: mSoft),
              ),
            ),
            ...labels,
          ],
        ),
      ),
    );
  }

  /// 역의 설명글 — 칸마다 `이름 기간 · 메모`와 다른 견해, 마지막에 `누르면 이 시기로`.
  String _stationTip(MetroNode n) {
    final lines = n.periods.map((c) => '${c.name} ${c.when}${c.note.isEmpty ? '' : ' · ${c.note}'}${c.alts.map((a) => '\n  다른 견해 — $a').join()}').join('\n');
    return '$lines\n누르면 이 시기로';
  }

  /// 범례 — 있는 갈래만.
  Widget _legend(MetroPlan plan, Color mLine, Color mSoft) {
    final items = <Widget>[
      _LegendItem(
        mark: _LegendBar(color: mLine, height: 4),
        text: '정도',
      ),
    ];
    if (plan.branches.isNotEmpty) {
      items.add(
        _LegendItem(
          mark: _LegendBar(color: mSoft, height: 3),
          text: '배도(지선)',
        ),
      );
    }
    if (plan.hasDetour) {
      items.add(
        _LegendItem(
          mark: _LegendDash(color: mLine),
          text: '임시(우회)',
        ),
      );
    }
    if (plan.hasXfer) items.add(const _LegendItem(mark: _LegendRing(), text: '같은 도시(환승)'));
    if (plan.hiddenBranches > 0) {
      items.add(
        Text(
          '배도 외 ${plan.hiddenBranches}곳',
          style: const TextStyle(
            fontFamily: sceneFontFamily,
            fontFamilyFallback: sceneFontFallback,
            letterSpacing: 0,
            fontSize: MetroLook.legendSize,
            height: MetroLook.lineHeight,
            fontStyle: FontStyle.italic,
            color: MetroLook.muted,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: MetroLook.legendTop),
      child: Wrap(spacing: MetroLook.legendGapX, runSpacing: MetroLook.legendGapY, crossAxisAlignment: WrapCrossAlignment.center, children: items),
    );
  }

  /// 발: 같은 트랙의 다른 정권 단추 + 안내 한 줄.
  /// 줄 나눔은 css의 `flex-wrap`을 그대로 손수 셈한다 — 안내는 `margin-left:auto`라 늘 제 줄의 오른쪽 끝이고,
  /// 자리가 모자라면 안내만 다음 줄로 내려간다(Wrap 부품으로는 이 둘을 함께 할 수 없다).
  Widget _foot(MetroData data, double innerWidth) {
    final peers = data.peers;
    final many = peers.length > 1;
    final hint = '역을 누르면 그 시기로${many ? ' · ← → 다른 정권' : ''}';
    final hintWidth = measureMetroText(hint, MetroLook.hintSize, 400) + MetroLook.footTop;
    final rows = <List<MetroPeer>>[];
    double used = 0;
    if (many) {
      var line = <MetroPeer>[];
      for (final q in peers) {
        final w = measureMetroText(q.name, MetroLook.peerSize, q.uid == data.uid ? 700 : 400) + MetroLook.peerPadding.horizontal;
        if (line.isNotEmpty && used + MetroLook.footGap + w > innerWidth) {
          rows.add(line);
          line = [];
          used = 0;
        }
        used += line.isEmpty ? w : MetroLook.footGap + w;
        line.add(q);
      }
      rows.add(line);
    }
    final sameLine = used + (used > 0 ? MetroLook.footGap : 0) + hintWidth <= innerWidth;
    final hintWidget = Padding(
      padding: const EdgeInsets.only(left: MetroLook.footTop),
      child: Text(
        hint,
        style: const TextStyle(
          fontFamily: sceneFontFamily,
          fontFamilyFallback: sceneFontFallback,
          letterSpacing: 0,
          fontSize: MetroLook.hintSize,
          height: MetroLook.lineHeight,
          color: MetroLook.muted,
        ),
      ),
    );
    Widget lineOf(List<MetroPeer> line, {required bool withHint}) => Row(
      children: [
        for (int i = 0; i < line.length; i++) ...[
          if (i > 0) const SizedBox(width: MetroLook.footGap),
          _PeerButton(peer: line[i], on: line[i].uid == _uid, onPressed: () => _switchTo(line[i].uid)),
        ],
        const Spacer(),
        if (withHint) hintWidget,
      ],
    );

    return Container(
      margin: const EdgeInsets.only(top: MetroLook.footTop),
      padding: const EdgeInsets.only(top: MetroLook.footTop),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MetroLook.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: MetroLook.footGap), lineOf(rows[i], withHint: sameLine && i == rows.length - 1)],
          if (!sameLine) ...[
            if (rows.isNotEmpty) const SizedBox(height: MetroLook.footGap),
            Row(children: [const Spacer(), hintWidget]),
          ],
        ],
      ),
    );
  }

  /// `← →`로 다른 정권 — 앱 틀이 단축키를 넘겨줄 때 쓴다(카드 안에 초점이 있을 때만).
  bool handleKey(LogicalKeyboardKey key) {
    if (_data == null) return false;
    if (key == LogicalKeyboardKey.arrowRight) {
      _step(1);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
      return true;
    }
    return false;
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  4. 자리 잡기 · 잔부품
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 카드를 제자리에 놓는다: 가리킬 것이 있으면 그 오른쪽 12에(가운데보다 34 위), 없으면 [loose]에.
/// 화면 밖으로 나가지 않게 가장자리 8 안으로 당기고, 줄 이름 오른쪽에 섰을 때만 꼭지를 단다.
class _Placed extends StatelessWidget {
  const _Placed({required this.anchor, required this.area, required this.loose, required this.onPlaced, required this.enter, required this.child});

  final Rect? anchor;
  final Size area;
  final Offset loose;
  final ValueChanged<Offset> onPlaced;
  final SurfaceMotion enter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _MeasuredPosition(
      area: area,
      anchor: anchor,
      loose: loose,
      onPlaced: onPlaced,
      builder: (context, nub) => AnimatedBuilder(
        animation: enter,
        builder: (context, inner) {
          final t = enter.value;
          return Opacity(
            opacity: enter.opacity,
            child: Transform.translate(
              offset: Offset(0, MetroLook.rise * (1 - t)),
              child: Transform.scale(scale: MetroLook.scaleFrom + (1 - MetroLook.scaleFrom) * t, child: inner),
            ),
          );
        },
        child: nub == null ? child : _WithNub(nub: nub, child: child),
      ),
    );
  }
}

/// 카드의 크기를 재서 자리를 정하는 작은 틀. 첫 그림에서는 왼쪽 위에 재 두고, 잰 뒤 제자리로 옮긴다.
class _MeasuredPosition extends StatefulWidget {
  const _MeasuredPosition({required this.area, required this.anchor, required this.loose, required this.onPlaced, required this.builder});

  final Size area;
  final Rect? anchor;
  final Offset loose;
  final ValueChanged<Offset> onPlaced;
  final Widget Function(BuildContext context, double? nub) builder;

  @override
  State<_MeasuredPosition> createState() => _MeasuredPositionState();
}

class _MeasuredPositionState extends State<_MeasuredPosition> {
  final _key = GlobalKey();
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(_MeasuredPosition oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    if ((box.size.width - _size.width).abs() < .5 && (box.size.height - _size.height).abs() < .5) return;
    setState(() => _size = box.size);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.anchor;
    final w = _size.width, h = _size.height;
    double left, top;
    if (a != null) {
      left = a.right + MetroLook.anchorGap;
      top = a.center.dy - MetroLook.anchorRise;
    } else {
      left = widget.loose.dx;
      top = widget.loose.dy;
    }
    final maxLeft = math.max(MetroLook.edgeGap, widget.area.width - w - MetroLook.edgeGap);
    final maxTop = math.max(MetroLook.edgeGap, widget.area.height - h - MetroLook.edgeGap);
    left = left.clamp(MetroLook.edgeGap, maxLeft);
    top = top.clamp(MetroLook.edgeGap, maxTop);
    final at = Offset(left, top);
    if (w > 0) widget.onPlaced(at);
    // 줄 이름을 가리키는 꼭지는 카드가 그 오른쪽에 있을 때만.
    double? nub;
    if (a != null && left >= a.right + 4 && h > 0) {
      nub = (a.center.dy - top).clamp(MetroLook.nubInset, math.max(MetroLook.nubInset, h - MetroLook.nubInset));
    }
    return Positioned(
      left: left.roundToDouble(),
      top: top.roundToDouble(),
      child: KeyedSubtree(key: _key, child: widget.builder(context, nub)),
    );
  }
}

/// 카드 왼쪽의 꼭지(마름모) — 가리키는 줄 이름을 향한다.
class _WithNub extends StatelessWidget {
  const _WithNub({required this.nub, required this.child});
  final double nub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: MetroLook.nubLeft,
          top: nub - MetroLook.nub / 2,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: MetroLook.nub,
              height: MetroLook.nub,
              decoration: const BoxDecoration(
                color: MetroLook.paper,
                boxShadow: [BoxShadow(color: Ui.line, offset: Offset(-1, 1))],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 머리의 작은 단추(`.m-btn`) — 28×28 · 둥근 9 · `--paper-2` 바탕.
class _HeadButton extends StatefulWidget {
  const _HeadButton({required this.label, required this.child, this.on = false, this.onPressed});
  final String label;
  final Widget child;
  final bool on;
  final VoidCallback? onPressed;

  @override
  State<_HeadButton> createState() => _HeadButtonState();
}

class _HeadButtonState extends State<_HeadButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: MetroLook.button,
            height: MetroLook.button,
            alignment: Alignment.center,
            // 테두리는 앞면에 그린다 — css의 `border-box`처럼 크기를 바꾸지 않게.
            decoration: BoxDecoration(color: widget.on ? Ui.accentSoft : MetroLook.paper2, borderRadius: BorderRadius.circular(MetroLook.buttonRadius)),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MetroLook.buttonRadius),
              border: Border.all(color: widget.on ? const Color(0x73000000) : (_hover ? Ui.lineStrong : MetroLook.line)),
            ),
            child: Opacity(opacity: widget.on ? 1 : .75, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// 역 · 배도 · 끝의 이름표. [inline]이면 이름과 해가 한 줄(배도), [center]면 가운데 맞춤(임시 도읍).
class _MetroLabel extends StatefulWidget {
  const _MetroLabel({
    required this.name,
    required this.sub,
    required this.tip,
    this.chip,
    this.inline = false,
    this.center = false,
    this.muted = false,
    this.onTap,
    this.onHover,
    this.onChip,
  });

  final String name, sub, tip;
  final MetroChip? chip;
  final bool inline, center, muted;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;
  final ValueChanged<String>? onChip;

  @override
  State<_MetroLabel> createState() => _MetroLabelState();
}

class _MetroLabelState extends State<_MetroLabel> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final nameStyle = TextStyle(
      fontFamily: sceneFontFamily,
      fontFamilyFallback: sceneFontFallback,
      letterSpacing: 0,
      fontSize: widget.inline ? MetroLook.secLabelSize : MetroLook.labelSize,
      height: MetroLook.lineHeight,
      fontWeight: widget.muted ? FontWeight.w600 : FontWeight.w700,
      color: widget.muted ? MetroLook.muted : MetroLook.ink,
      decoration: _hover && widget.onTap != null ? TextDecoration.underline : TextDecoration.none,
      decorationColor: MetroLook.muted,
    );
    const subStyle = TextStyle(
      fontFamily: sceneFontFamily,
      fontFamilyFallback: sceneFontFallback,
      letterSpacing: 0,
      fontSize: MetroLook.subSize,
      height: MetroLook.lineHeight,
      color: MetroLook.muted,
      fontFeatures: [ui.FontFeature.tabularFigures()],
    );
    final name = Text(widget.name, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: nameStyle);
    final sub = widget.sub.isEmpty ? null : Text(widget.sub, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: subStyle);

    Widget go = widget.inline
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              name,
              if (sub != null) ...[const SizedBox(width: 4), sub],
            ],
          )
        : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: widget.center ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [name, ?sub]);
    if (widget.onTap != null) {
      go = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hover = true);
          widget.onHover?.call(true);
        },
        onExit: (_) {
          setState(() => _hover = false);
          widget.onHover?.call(false);
        },
        child: GestureDetector(onTap: widget.onTap, child: go),
      );
    }
    if (widget.tip.isNotEmpty) go = Tooltip(message: widget.tip, child: go);

    final chip = widget.chip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: widget.center ? MainAxisAlignment.center : MainAxisAlignment.start,
      crossAxisAlignment: widget.inline ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        go,
        if (chip != null) ...[const SizedBox(width: 4), _XferChip(chip: chip, onPressed: () => widget.onChip?.call(chip.uid))],
      ],
    );
  }
}

/// 환승 칩(`.m-x`) — `⇄ 〈나라〉 외 n`. 누르면 그 나라의 노선도.
class _XferChip extends StatefulWidget {
  const _XferChip({required this.chip, this.onPressed});
  final MetroChip chip;
  final VoidCallback? onPressed;

  @override
  State<_XferChip> createState() => _XferChipState();
}

class _XferChipState extends State<_XferChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final oc = widget.chip.color.toARGB32();
    return Tooltip(
      message: '${widget.chip.tip} — 누르면 그 나라 노선도',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            height: MetroLook.chipHeight,
            padding: const EdgeInsets.symmetric(horizontal: MetroLook.chipPad),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Color(mixSrgb(oc, MetroLook.paperInt, _hover ? .42 : .26)), borderRadius: BorderRadius.circular(999)),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Color(withAlpha(oc, .55))),
            ),
            child: Text(
              widget.chip.text,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: sceneFontFamily,
                fontFamilyFallback: sceneFontFallback,
                letterSpacing: 0,
                fontSize: MetroLook.chipSize,
                height: 1,
                fontWeight: FontWeight.w600,
                color: Color(mixOklab(oc, MetroLook.inkInt, .40)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 발의 다른 정권 단추(`.m-peer`).
class _PeerButton extends StatefulWidget {
  const _PeerButton({required this.peer, required this.on, this.onPressed});
  final MetroPeer peer;
  final bool on;
  final VoidCallback? onPressed;

  @override
  State<_PeerButton> createState() => _PeerButtonState();
}

class _PeerButtonState extends State<_PeerButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final pc = widget.peer.color.toARGB32();
    final fill = widget.on ? .40 : (_hover ? .30 : .16);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: MetroLook.peerPadding,
          decoration: BoxDecoration(color: Color(mixSrgb(pc, MetroLook.paperInt, fill)), borderRadius: BorderRadius.circular(999)),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: widget.on ? Color(mixOklab(pc, MetroLook.inkInt, .80)) : Color(withAlpha(pc, .55)), width: widget.on ? 1.5 : 1),
          ),
          child: Text(
            widget.peer.name,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: sceneFontFamily,
              fontFamilyFallback: sceneFontFallback,
              letterSpacing: 0,
              fontSize: MetroLook.peerSize,
              height: MetroLook.lineHeight,
              fontWeight: widget.on ? FontWeight.w700 : FontWeight.w400,
              color: MetroLook.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.mark, required this.text});
  final Widget mark;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: MetroLook.legendInner),
        Text(
          text,
          style: const TextStyle(
            fontFamily: sceneFontFamily,
            fontFamilyFallback: sceneFontFallback,
            letterSpacing: 0,
            fontSize: MetroLook.legendSize,
            height: MetroLook.lineHeight,
            color: MetroLook.muted,
          ),
        ),
      ],
    );
  }
}

class _LegendBar extends StatelessWidget {
  const _LegendBar({required this.color, required this.height});
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: MetroLook.legendMark,
    height: height,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
  );
}

class _LegendDash extends StatelessWidget {
  const _LegendDash({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: MetroLook.legendMark,
    height: 2.5,
    child: CustomPaint(painter: _DashMark(color)),
  );
}

class _DashMark extends CustomPainter {
  const _DashMark(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    _dashLine(canvas, Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint, const [3, 3]);
  }

  @override
  bool shouldRepaint(_DashMark old) => old.color != color;
}

class _LegendRing extends StatelessWidget {
  const _LegendRing();

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: MetroLook.muted, width: 1.5),
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  5. 도형 그리기 — 본선 · 지선 · 우회 · 역 · 환승 고리
// ────────────────────────────────────────────────────────────────────────────────────────────

class _MetroPainter extends CustomPainter {
  const _MetroPainter({required this.plan, required this.line, required this.soft});

  final MetroPlan plan;
  final Color line, soft;

  @override
  void paint(Canvas canvas, Size size) {
    final y = plan.mainY;
    final main = Paint()
      ..color = line
      ..strokeWidth = MetroLook.mainWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(plan.mainFrom, y), Offset(plan.xEnd, y), main);

    // 경계가 미정인 구간: 종이색으로 덮고 그 위에 점선.
    final gap = Paint()
      ..color = MetroLook.paper
      ..strokeWidth = MetroLook.gapWidth
      ..style = PaintingStyle.stroke;
    final unknown = Paint()
      ..color = line
      ..strokeWidth = MetroLook.unknownWidth
      ..style = PaintingStyle.stroke;
    for (final (a, b) in plan.dashes) {
      canvas.drawLine(Offset(a, y), Offset(b, y), gap);
      _dashLine(canvas, Offset(a, y), Offset(b, y), unknown, const [6, 5]);
    }

    for (final n in plan.nodes) {
      final ring = n.chip?.color;
      if (n.detour) {
        final l = n.x - MetroPlan.detourHalf, r = n.x + MetroPlan.detourHalf;
        final vacant = Paint()
          ..color = MetroLook.paper
          ..strokeWidth = MetroLook.vacantWidth
          ..style = PaintingStyle.stroke;
        _dashLine(canvas, Offset(l + 6, y), Offset(r - 6, y), vacant, const [4, 4]);
        final path = Path()
          ..moveTo(l, y)
          ..cubicTo(l + 5, y + 40, r - 5, y + 40, r, y);
        final detour = Paint()
          ..color = line
          ..strokeWidth = MetroLook.detourWidth
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        _dashPath(canvas, path, detour, const [6, 5]);
        if (ring != null) _ring(canvas, Offset(n.x, y + 30), MetroLook.xferDetour, ring);
        _stop(canvas, Offset(n.x, y + 30), MetroLook.stopRadius, line, MetroLook.stopTempWidth, dash: const [3, 2]);
        continue;
      }
      if (ring != null) _ring(canvas, Offset(n.x, y), MetroLook.xferStation, ring);
      final main = identical(n, plan.longest);
      _stop(canvas, Offset(n.x, y), main ? MetroLook.stopMainRadius : MetroLook.stopRadius, line, main ? MetroLook.stopMainWidth : MetroLook.stopWidth);
    }

    canvas.drawCircle(Offset(plan.xEnd, y), MetroLook.endRadius, Paint()..color = line);

    for (final b in plan.branches) {
      final path = Path()
        ..moveTo(b.x, y - 3)
        ..lineTo(b.x, b.y + 9)
        ..quadraticBezierTo(b.x, b.y, b.x + 9, b.y)
        ..lineTo(b.x + 12, b.y);
      canvas.drawPath(
        path,
        Paint()
          ..color = soft
          ..strokeWidth = MetroLook.branchWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      final ring = b.chip?.color;
      if (ring != null) _ring(canvas, Offset(b.x + 16, b.y), MetroLook.xferBranch, ring);
      _stop(canvas, Offset(b.x + 16, b.y), MetroLook.stopSecRadius, soft, MetroLook.stopSecWidth);
    }
  }

  /// 역 동그라미 — 속은 종이색, 테두리는 노선 색.
  void _stop(Canvas canvas, Offset at, double radius, Color edge, double width, {List<double>? dash}) {
    canvas.drawCircle(at, radius, Paint()..color = MetroLook.paper);
    final paint = Paint()
      ..color = edge
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    if (dash == null) {
      canvas.drawCircle(at, radius, paint);
    } else {
      _dashPath(canvas, Path()..addOval(Rect.fromCircle(center: at, radius: radius)), paint, dash);
    }
  }

  /// 환승 고리 — 다른 나라의 색으로 두른 가는 겹고리.
  void _ring(Canvas canvas, Offset at, double radius, Color color) {
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..color = Color(mixOklab(color.toARGB32(), MetroLook.inkInt, .70))
        ..strokeWidth = MetroLook.xferWidth
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_MetroPainter old) => old.plan != plan || old.line != line || old.soft != soft;
}

/// 점선 한 줄(css `stroke-dasharray`와 같은 뜻).
void _dashLine(Canvas canvas, Offset a, Offset b, Paint paint, List<double> pattern) {
  final total = (b - a).distance;
  if (total <= 0) return;
  final step = (b - a) / total;
  double at = 0;
  int i = 0;
  while (at < total) {
    final len = pattern[i % pattern.length];
    if (i.isEven) canvas.drawLine(a + step * at, a + step * math.min(at + len, total), paint);
    at += len;
    i++;
  }
}

/// 점선 길(굽은 길 · 동그라미).
void _dashPath(Canvas canvas, Path path, Paint paint, List<double> pattern) {
  for (final metric in path.computeMetrics()) {
    double at = 0;
    int i = 0;
    while (at < metric.length) {
      final len = pattern[i % pattern.length];
      if (i.isEven) canvas.drawPath(metric.extractPath(at, math.min(at + len, metric.length)), paint);
      at += len;
      i++;
    }
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  6. 글자 폭 재기 — 브라우저의 canvas measureText에 해당(같은 글꼴 · 같은 굵기)
// ────────────────────────────────────────────────────────────────────────────────────────────

final _widths = <String, double>{};

/// 글자 한 줄의 폭. 지금 연표의 `textWidth(text, size, weight)`와 같은 자리에서 쓴다.
/// [tabular]는 숫자 폭을 고르게 하는 글꼴 기능(css `font-variant-numeric: tabular-nums`)을 켠 폭이다 —
/// 도형 셈에는 쓰지 않는다(지금 연표도 캔버스로 재므로 그 기능이 빠진 폭으로 셈한다). 이름표 상자의 폭에만 쓴다.
double measureMetroText(String text, double size, int weight, {bool tabular = false}) {
  if (text.isEmpty) return 0;
  final key = '$weight|$size|${tabular ? 't' : 'n'}|$text';
  final had = _widths[key];
  if (had != null) return had;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: sceneFontFamily,
        fontFamilyFallback: sceneFontFallback,
        letterSpacing: 0,
        fontSize: size,
        fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
        fontFeatures: tabular ? const [ui.FontFeature.tabularFigures()] : null,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return _widths[key] = width;
}

/// 이름표 상자의 실제 폭(그리는 글꼴 그대로) — 자리는 [MetroPlan]의 값으로 잡고 상자만 이만큼 넓힌다.
/// css에서도 `left`는 잰 폭(`lab.w`)으로, 상자는 내용만큼 넓어진다.
double metroLabelBox(String name, String sub, MetroChip? chip, {bool inline = false, bool muted = false}) {
  final n = measureMetroText(name, inline ? MetroLook.secLabelSize : MetroLook.labelSize, muted ? 600 : 700);
  final s = measureMetroText(sub, MetroLook.subSize, 400, tabular: true);
  final body = inline ? n + (sub.isEmpty ? 0 : 4 + s) : math.max(n, s);
  final withChip = chip == null ? 0.0 : 4 + measureMetroText(chip.text, MetroLook.chipSize, 600) + MetroLook.chipPad * 2;
  return body + withChip + 1;
}

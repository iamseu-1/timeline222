import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../scene/viewport.dart' show SceneView;
import '../../shell/motion_widgets.dart' show SurfaceMotion;
import '../../shell/sheet_look.dart';
import '../../shell/sheet_parts.dart';
import '../app_bus.dart';
import '../context_menu.dart' show MenuRow, showTimelineMenu;
import '../date_text.dart' show civilAt;
import '../detail_item.dart' show successionNames;
import '../detail_shell.dart';
import '../group_tree.dart' show groupTreeSlot;
import '../shell_keys.dart' show AppCommand, Cmd, slotCommand, slotNotice, slotZen, typingNow;
import 'kin_head.dart' show SeamLine, kinYear;
import 'kin_rows.dart' show KinLevel;
import 'succession_look.dart';
import 'succession_view.dart' show kinLevelSlot;

// ════════════════════════════════════════════════════════════════════════════════════════════
//  승계표 넓은 창 — 화면 아래 서랍(가로로 이어짐). 리메이크 4단계 틀의 시트와 창 걸음 7 · 감독 고름 G5 #9 '서고로 다시 그림'
//  ('승계표 자리 = 둘 다' — 넓은 창(화면 아래 서랍) + 옆 상세 칸의 좁은 창). 다듬기 판 `sh-succ-wide`
//  (`.claude/research/stage4-choose/themes/g-sheet-succ.js`의 `wide` · `chart` · `place` · `band` · `keyTag` · `thread` · `ruler` — git 밖)를 앱으로 옮겼다.
//
//  · 창 = 정권 색 폴더 '승계표'(화면 양옆 24 · 아래 14 · 키는 내용만큼). 머리 = 제목 꼬리표(정권 색 · 제목 20 · '해 ~ 해년 · 지도자 n' —
//    구멍에서 실이 폴더 몸통 윗변까지) · 한 줄 범례(자료에 쓰인 실 갈래 · 열쇠표 · 정통성 넷 — 먹 25 금 앞뒤) · 오른쪽 '수준 ▾' · '닫기' 종이 단추.
//  · 표 = 눈금(25년마다 짧은 금 · 50년마다 해 글 + 점선 먹 12 — 해가 아주 넓거나 좁으면 눈금 짝을 바꿈) + 꼬리표 줄. 꼬리표 = 지도자와
//    앞뒤 나라(정권 기록 `x_succ`의 pre · post — 그 나라 색) · 길이는 제 기간(해 = 가로). 표 전체를 서랍 폭에 맞추고, 가장 짧은 재위가
//    28px(맞닿은 들임을 빼도 꼬리표 24 — 구멍과 마름모가 닿지 않음)보다 좁아지면 그만큼 넓혀 가로로 끈다.
//  · 승계 = 꼬리 마름모 → 다음 구멍 실: 같은 줄이면 곧게 · 줄을 건너면 틈에서 곧게 굽음 · 간접 · 부흥은 점선 · 부분은 가는 실 ·
//    합쳐짐(앞 나라 여럿)은 매듭. 지도자 사이 실은 이음매 갈래 여섯([SeamLine])의 꼴(좁은 창과 같은 [SuccThread]).
//    맞닿은 꼬리표 사이는 4, 갈래 실이 지나는 해는 10.
//  · 열쇠표(관계 · 방식) = 띠 위(띠 윗변에서 45° 실) — 앞 열쇠표에 밀리면 오른쪽으로, 창 끝이면 왼쪽으로. 재위가 아주 짧아 이름이
//    들지 않으면 이름을 열쇠표에. 복위는 열쇠표 '다시'. 열린 끝(표 밖으로 이어지는 앞뒤 나라 · 아직 다스리는 지도자)은 32px 옅어진다.
//    뒤 나라가 둘 이상이면 둘째 줄.
//  · 수준은 '지도자만'만 그린다(가로 꼴에는 자녀 · 파 그림이 없다) — '수준 ▾'의 다른 수준은 그 수준으로 좁은 창을 연다([kinLevelSlot]).
//  · 여는 길: 좁은 창 바닥의 '넓게'([openSuccessionWide] — 상세 칸은 나라 상세로) · 대본의 slot 걸음(`succWide` = 정권 uid).
//    닫기: '닫기' · Esc(상세 창 다음 차례 — 단체 계보 창 규칙). 누름: 지도자 꼬리표 = 그 칸 창(`leader:i`) · 앞뒤 나라 = 그 나라 상세.
//  · 단체 계보 창과는 한 자리(연표 아래)라 함께 열리지 않는다(어느 쪽을 열든 다른 쪽을 닫는다). 휴대폰과 860 아래 폭은 서랍 없이 좁은 창만.
//  · 연표는 단체 계보 창처럼 앱 틀의 `stageBottomInset`으로 비킨다([SuccessionDrawer.insetOn] — 배율 알약 · 상세 칸이 서랍 위로).
//  그리개(실 · 마름모 · 구멍 · 열쇠표 · 제목 꼬리표 · 범례 견본)는 좁은 창과 같은 `succession_look.dart`.
//  칸 정통성 무늬(공동 · 섭정 · 명목 · 주장)는 자료가 아직 없어 범례에만 둔다(그림판 범례의 정통성 상자와 같음).
// ════════════════════════════════════════════════════════════════════════════════════════════

/// [AppBus.slot]에 쓰는 이름 — 값은 정권 uid(글 · 열기), null이면 닫힘.
const succWideSlot = 'succWide';

/// 넓은 창 한 장을 붙잡는 열쇠(검사 · 1배 그림).
const succWideKey = ValueKey('승계표 넓은 창');

/// 정권 [uid]의 넓은 창을 연다 — 단체 계보 창과 한 자리라 그 창은 닫는다.
void openSuccessionWide(AppBus bus, String uid) {
  bus.slot(groupTreeSlot).value = null;
  bus.slot(succWideSlot).value = uid;
}

/// 넓은 창을 닫는다.
void closeSuccessionWide(AppBus bus) => bus.slot(succWideSlot).value = null;

/// 넓은 창 치수(1배 px — 다듬기 판 `wide` · `chart`의 값).
abstract final class SuccWideLook {
  /// 서랍: 화면 양옆 24 · 아래 14 · 860보다 좁으면 없음 · 폴더 안쪽 16(아래 14 — 눈금 점선이 마지막 줄 아래 4까지 내려옴).
  static const sideMargin = 24.0, bottomMargin = 14.0, minWidth = 860.0, pad = 16.0, padBottom = 14.0;

  /// 머리: 제목 꼬리표 뒤 32에 범례 · 범례 칸 사이 22(견본 뒤 8 · 글 11 먹 60) · 먹 25 금 키 16 · 단추 키 22 · 글 앞뒤 7 · 사이 6 · 표까지 12.
  static const headGap = 32.0, legendGap = 22.0, legendTextGap = 8.0, ruleHeight = 16.0, button = 22.0, buttonPad = 7.0, buttonGap = 6.0, chartGap = 12.0;

  /// 제목 꼬리표의 실 — 구멍에서 폴더 몸통 윗변 안 1까지(제목 꼬리표 위 16 − 1).
  static const titleThread = 15.0;

  /// 표: 눈금 18 · 눈금과 첫 줄 · 줄 사이 20(열쇠표가 듦) · 줄 = 꼬리표 40 · 맞닿은 끝 2씩(사이 4) · 갈래 실이 지나는 해 5씩(사이 10) ·
  /// 열린 끝 32 · 앞뒤 나라 자리 150(없으면 16) · 가장 짧은 재위의 자리 28(들임을 빼고 꼬리표 24 — 구멍 · 마름모가 닿지 않음) · 앞뒤 나라 꼬리표 40 이상 · 마지막 줄 아래 4(점선 끝).
  static const ruler = 18.0, rowGap = 20.0, row = SuccLook.tag, join = 2.0, branch = 5.0, fade = 32.0, nationRoom = 150.0, endRoom = 16.0;
  static const minTag = 28.0, minNation = 40.0, below = 4.0;

  /// 꼬리표 글: 구멍 뒤 7(구멍 가운데에서) · 대수 뒤 3 · 마름모 앞 6 · 해 글은 오른쪽 끝 4 안.
  static const nameAfterHole = 7.0, ordGap = 3.0, nameBeforeDiamond = 6.0, yearsRight = 4.0;

  /// 열쇠표: 꼬리표 왼쪽에서 19 · 열쇠표 사이 4 · 바깥 상자 13이 꼬리표 윗변 1 위(위로 14) · 글 앞 11 · 뒤 7(바깥 상자).
  static const keyLeft = 19.0, keyGap = 4.0, keyAbove = 14.0, keyLead = 11.0, keyTail = 7.0;

  /// 눈금: 짧은 금 2 ~ 14(먹 25) · 큰 금은 14부터 점선 2 3(먹 12) · 해 글 10(금 오른쪽 4 · 가운데 8) · 해 글 사이 60 ~ 600px(그 밖이면 눈금 짝을 바꿈).
  static const tickTop = 2.0, tickBottom = 14.0, tickDash = 2.0, tickGap = 3.0, tickText = 10.0, tickLabelLeft = 4.0, tickMid = 8.0, labelMin = 60.0, labelMax = 600.0;
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  자료 — 정권 기록 하나를 넓은 창의 띠 · 이음으로
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 띠의 갈래 — 앞 나라 · 지도자 · 뒤 나라.
enum SuccWideSide { pre, leader, post }

/// 넓은 창의 띠 하나(지도자 · 앞뒤 나라). [a] · [b]는 해(분수 해 · 표 밖이면 무한), [openL] · [openR]은 자료가 열어 둔 끝
/// (해를 모르는 앞 나라의 시작 · 아직 다스리는 지도자의 끝).
@immutable
class SuccWideBand {
  const SuccWideBand({
    required this.side,
    required this.index,
    required this.name,
    required this.color,
    required this.a,
    required this.b,
    this.ordinal = '',
    this.uid = '',
    this.openL = false,
    this.openR = false,
    this.key,
    this.again = false,
  });

  final SuccWideSide side;

  /// 지도자면 `leader:i`의 i, 앞뒤 나라면 `x_succ`의 pre · post 차례.
  final int index;
  final String name, ordinal, uid;
  final Color color;
  final double a, b;
  final bool openL, openR;

  /// 열쇠표 글(관계 · 방식 — 지도자는 이음매 글 · 뒤 나라는 승계 갈래). 이름이 띠에 들지 않으면 자리 셈이 이름을 앞에 더한다.
  final InlineSpan? key;

  /// 다시 오른 지도자(복위) — 열쇠표 '다시'.
  final bool again;

  bool get isLeader => side == SuccWideSide.leader;
}

/// 승계 이음 — 띠 [from]의 꼬리 마름모 → 띠 [to]의 구멍. [line]은 실 갈래(이음매 [SeamLine] 0 ~ 5 · 나라 사이 [SuccLine]).
@immutable
class SuccWideLink {
  const SuccWideLink(this.from, this.to, this.line);
  final int from, to, line;
}

/// 해 글(`300년 ~ 788년` · `기원전 200년 ~ 100년`)에서 시작 · 끝 해를 읽는다 — 앞뒤 나라 기록을 받지 못했을 때만(첫 해 · 끝 해).
/// '미정' 따위로 해가 없는 쪽은 null.
(double?, double?) succWhenSpan(String when) {
  double? at(String side) {
    final m = RegExp(r'(기원전\s*)?(\d+)\s*년').firstMatch(side);
    if (m == null) return null;
    final v = double.tryParse(m[2]!);
    return v == null ? null : (m[1] != null ? -v : v);
  }

  final sides = when.split('~');
  if (sides.length < 2) {
    final v = at(when);
    return (v, v);
  }
  return (at(sides.first), at(sides.last));
}

/// 넓은 창이 그리는 것 — 정권 하나의 띠(앞 나라 · 지도자 · 뒤 나라 차례) · 이음 · 머리 글 · 범례.
class SuccWideData {
  SuccWideData._({required this.uid, required this.name, required this.sub, required this.color, required this.from, required this.to, required this.bands, required this.links, required this.legend});

  final String uid, name, sub;
  final Color color;

  /// 표의 몸(정권 기간 ∪ 지도자 기간 — 해).
  final double from, to;
  final List<SuccWideBand> bands;
  final List<SuccWideLink> links;

  /// 한 줄 범례 앞쪽(실 갈래 · 열쇠표 — 자료에 쓰인 것만): (견본 갈래 — [SuccLegendKind], 글). 정통성 넷은 [legit].
  final List<(String, String)> legend;

  /// 정통성 넷(늘 — 그림판 범례의 정통성 상자와 같은 이름).
  static const legit = <(String, String)>[
    (SuccLegendKind.joint, '공동'),
    (SuccLegendKind.regent, '섭정'),
    (SuccLegendKind.nominal, '명목'),
    (SuccLegendKind.claim, '주장'),
  ];

  int get leaders => bands.where((b) => b.isLeader).length;

  /// 정권 기록 [json](`leaders` · `x_lineage` · `x_succ` · `color` · `start` · `endY`)을 읽는다. [spans]는 앞뒤 나라 uid → (시작, 끝) 해
  /// (그 나라 기록을 받아 둔 것 — 없으면 `x_succ`의 해 글). 지도자가 없으면 null.
  static SuccWideData? parse(String uid, Map<String, dynamic> json, {Map<String, (double?, double?)> spans = const {}}) {
    final leaders = detailList(json, 'leaders');
    if (leaders.isEmpty) return null;
    double? n(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    final color = detailColor(json['color'], SheetLook.ink45);
    final ps = n(json['start']), pe = n(json['endY']) ?? n(json['end']);
    final lineage = json['x_lineage'] is Map ? (json['x_lineage'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    Map<String, dynamic>? lin(int m) {
      final one = lineage['leader:$m'];
      return one is Map ? one.cast<String, dynamic>() : null;
    }

    // 지도자 해 — 끝이 없으면 다음 지도자의 시작 · 나라의 끝(아직 다스리는 끝 지도자는 열린 끝).
    final la = <double>[], lb = <double>[];
    for (var m = 0; m < leaders.length; m++) {
      final c = leaders[m];
      final a = n(c['start']) ?? (m > 0 ? lb[m - 1] : ps) ?? pe ?? 0;
      final next = m + 1 < leaders.length ? n(leaders[m + 1]['start']) : null;
      la.add(a);
      lb.add(math.max(a, n(c['end']) ?? n(c['endY']) ?? next ?? pe ?? a + 1));
    }
    final from = math.min(ps ?? la.first, la.first), to = math.max(pe ?? lb.last, lb.last);

    final succ = json['x_succ'] is Map ? (json['x_succ'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final pre = detailList(succ, 'pre'), post = detailList(succ, 'post');
    (double?, double?) spanOf(Map<String, dynamic> e) => spans[detailString(e, 'uid')] ?? succWhenSpan(detailString(e, 'when'));

    final bands = <SuccWideBand>[], links = <SuccWideLink>[];
    for (var k = 0; k < pre.length; k++) {
      final e = pre[k];
      final (sa, sb) = spanOf(e);
      bands.add(SuccWideBand(
        side: SuccWideSide.pre,
        index: k,
        name: detailString(e, 'name'),
        uid: detailString(e, 'uid'),
        color: detailColor(e['color'], SheetLook.ink45),
        a: sa ?? double.negativeInfinity,
        b: sb ?? from,
        openL: sa == null,
      ));
    }
    final first = bands.length;
    for (var m = 0; m < leaders.length; m++) {
      final c = leaders[m], l = lin(m);
      final o = n(c['ordinal']);
      bands.add(SuccWideBand(
        side: SuccWideSide.leader,
        index: m,
        name: detailString(c, 'name'),
        ordinal: o == null ? '' : '${o.toInt()}대',
        color: color,
        a: la[m],
        b: lb[m],
        openR: m == leaders.length - 1 && n(c['end']) == null && n(c['endY']) == null,
        key: succSeamSpan(l),
        again: l != null && (l['restored'] == 1 || l['restored'] == true || SeamLine.of(l) == SeamLine.restore),
      ));
      if (m > 0) links.add(SuccWideLink(first + m - 1, first + m, SeamLine.of(l)));
    }
    final last = bands.length - 1;
    for (var k = 0; k < pre.length; k++) {
      links.add(SuccWideLink(k, first, SuccLine.ofNation(detailString(pre[k], 'type'))));
    }
    for (var k = 0; k < post.length; k++) {
      final e = post[k], type = detailString(e, 'type');
      final (sa, sb) = spanOf(e);
      final word = successionNames[type];
      bands.add(SuccWideBand(
        side: SuccWideSide.post,
        index: k,
        name: detailString(e, 'name'),
        uid: detailString(e, 'uid'),
        color: detailColor(e['color'], SheetLook.ink45),
        a: sa ?? to,
        b: sb ?? double.infinity,
        openR: sb == null,
        key: word == null ? null : TextSpan(text: '$word 승계'),
      ));
      links.add(SuccWideLink(last, bands.length - 1, SuccLine.ofNation(type)));
    }

    // 한 줄 범례 — 자료에 쓰인 실 갈래만(비움은 글 없는 옅은 실이라 빼고) · 합쳐짐 · 복위 · 열쇠표.
    final lines = {for (final l in links) if (bands[l.from].isLeader && bands[l.to].isLeader) l.line};
    final types = {for (final e in [...pre, ...post]) detailString(e, 'type')};
    final legend = <(String, String)>[];
    final solid = [if (lines.contains(SeamLine.solid) || lines.contains(SeamLine.restore)) '세습 · 추대', if (types.contains('direct')) '직접 승계'];
    if (solid.isNotEmpty) legend.add((SuccLegendKind.seam(SeamLine.solid), solid.join(' · ')));
    if (lines.contains(SeamLine.abdicate)) legend.add((SuccLegendKind.seam(SeamLine.abdicate), '선양'));
    if (lines.contains(SeamLine.usurp)) legend.add((SuccLegendKind.seam(SeamLine.usurp), '찬탈 · 정변'));
    if (lines.contains(SeamLine.unknown)) legend.add((SuccLegendKind.seam(SeamLine.unknown), '관계 · 방식 미상'));
    final dashed = [
      if (types.any((t) => t != 'direct' && t != 'partial' && t != 'revival')) '간접 승계',
      if (types.contains('revival')) '부흥',
    ];
    if (dashed.isNotEmpty) legend.add((SuccLegendKind.seam(SuccLine.dashed), dashed.join(' · ')));
    if (types.contains('partial')) legend.add((SuccLegendKind.seam(SuccLine.thin), '부분 승계'));
    if (pre.length > 1) legend.add((SuccLegendKind.merge, '합쳐짐'));
    if (bands.any((b) => b.again)) legend.add((SuccLegendKind.again, '복위(같은 사람)'));
    if (bands.any((b) => b.key != null || b.again)) legend.add((SuccLegendKind.key, '관계 · 방식'));

    String year(double t) => kinYear(civilAt(t).year);
    return SuccWideData._(
      uid: uid,
      name: detailString(json, 'name'),
      sub: '${year(ps ?? from)} ~ ${year(pe ?? to)}년 · 지도자 ${leaders.length}',
      color: color,
      from: from,
      to: to,
      bands: bands,
      links: links,
      legend: legend,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  자리 셈(순수 — 글 폭은 [SuccWideMeasure]로 받는다)
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 글 한 덩이의 폭(창은 TextPainter로 · 검사는 흉내로).
typedef SuccWideMeasure = double Function(InlineSpan span);

/// 띠 안 이름의 자리 — 대수 + 이름 · 이름만 · 열쇠표로 옮김(목업 `q.label` 'full' · 'name' · 'key').
enum SuccWideName { full, name, key }

/// 열쇠표 하나 — 바깥 화소 상자 · 글 · 45° 실(띠 윗변 → 열쇠표 구멍).
@immutable
class SuccWideKey {
  const SuccWideKey(this.band, this.box, this.text, this.from, this.to);
  final int band;
  final Rect box;
  final InlineSpan text;
  final Offset from, to;
}

/// 눈금 하나 — 화소 가운데 x · 큰 금(해 글 · 점선)인가 · 해 글(들지 않으면 null).
@immutable
class SuccWideTick {
  const SuccWideTick(this.x, this.major, this.label);
  final double x;
  final bool major;
  final String? label;
}

/// 실 한 가닥의 토막 — 가로 · 세로(띠 뒤) · 굽음(사분 곡선 — [c]가 꺾이는 자리).
@immutable
class SuccWideSeg {
  const SuccWideSeg.h(double x0, double x1, double y) : kind = 0, a = const Offset(0, 0), b = const Offset(0, 0), c = null, _x0 = x0, _x1 = x1, _y = y;
  const SuccWideSeg.v(double x, double y0, double y1) : kind = 1, a = const Offset(0, 0), b = const Offset(0, 0), c = null, _x0 = y0, _x1 = y1, _y = x;
  const SuccWideSeg.bend(this.a, this.c, this.b) : kind = 2, _x0 = 0, _x1 = 0, _y = 0;

  /// 0 가로 · 1 세로 · 2 굽음.
  final int kind;
  final Offset a, b;
  final Offset? c;
  final double _x0, _x1, _y;

  /// 곧은 토막의 시작 · 끝(가로면 x · 세로면 y)과 그 가로지름(가로면 y · 세로면 x).
  double get start => _x0;
  double get end => _x1;
  double get across => _y;
}

/// 실 한 가닥 — 이음 [link]의 실 갈래 [line] · 토막들 · 같은 줄인가([same] — 이음매 갈래의 꼴을 다 그림).
@immutable
class SuccWideThread {
  const SuccWideThread(this.link, this.line, this.segs, {required this.same});
  final int link, line;
  final List<SuccWideSeg> segs;
  final bool same;
}

/// 넓은 창 표의 자리 — 띠마다 줄 · 바깥 화소 상자 · 구멍 · 마름모 · 이름 자리 · 해 글 · 열쇠표 · 눈금 · 실 · 매듭.
/// 표 왼쪽 위가 (0, 0)이고, 첫 줄 꼬리표 윗변은 눈금 18 + 20 아래다.
class SuccWidePlan {
  SuccWidePlan._(this.data, this.width, this.height, this.scale, this.t0, this.t1, this.rows, this.rowOf, this.boxes, this.openL, this.openR, this.holes, this.diamonds,
      this.names, this.nameLeft, this.ordWidth, this.years, this.keys, this.ticks, this.threads, this.knots);

  final SuccWideData data;

  /// 표 전체의 폭 · 키(받은 폭보다 넓으면 가로로 끈다).
  final double width, height;

  /// 1년의 px · 표 양 끝의 해.
  final double scale, t0, t1;
  final int rows;
  final List<int> rowOf;
  final List<Rect> boxes;
  final List<bool> openL, openR;
  final List<Offset?> holes, diamonds;
  final List<SuccWideName> names;

  /// 이름(대수) 글의 왼쪽(띠 바깥 상자 왼쪽에서) · 대수 글 폭 + 3(대수가 없으면 0).
  final List<double> nameLeft, ordWidth;
  final List<String?> years;
  final List<SuccWideKey> keys;
  final List<SuccWideTick> ticks;
  final List<SuccWideThread> threads;
  final List<Offset> knots;

  double xOf(double t) => (t - t0) * scale;

  /// 줄 [r]의 꼬리표 윗변.
  static double rowTop(int r) => SuccWideLook.ruler + SuccWideLook.rowGap + r * (SuccWideLook.row + SuccWideLook.rowGap);

  // ---- 글 꼴(창의 글과 같은 꼴로 잰다) ----

  static const _tabular = [FontFeature.tabularFigures()];
  static TextStyle ordStyle(Color c) => sheetText(SuccLook.ordText, color: SheetLook.nameInk(c)).copyWith(fontFeatures: _tabular);
  static TextStyle nameStyle(Color c) => sheetText(SuccLook.nameText, bold: true, color: SheetLook.tagInk(c));
  static TextStyle yearStyle(Color c) => sheetText(SuccLook.yearText, color: SheetLook.nameInk(c)).copyWith(fontFeatures: _tabular);
  static TextStyle get keyStyle => sheetText(SheetLook.keyText, color: SheetLook.ink60);
  static TextStyle tickStyle(bool major) => sheetText(SuccWideLook.tickText, color: major ? SheetLook.ink60 : SheetLook.ink45);

  /// 눈금 짝(짧은 금 · 해 글) — 기본 25 · 50, 해 글 사이가 60 ~ 600px 밖이면 처음으로 60을 넘는 짝.
  static const tickPairs = <(double, double)>[(1, 5), (5, 10), (10, 20), (25, 50), (50, 100), (100, 200), (250, 500), (500, 1000), (1000, 2000), (2500, 5000)];

  /// 받은 폭 [width] 안에 [data]를 놓는다.
  static SuccWidePlan layout(SuccWideData data, {required double width, required SuccWideMeasure measure}) {
    const eps = 1e-6;
    final bands = data.bands, n = bands.length;
    final padL = bands.any((b) => b.side == SuccWideSide.pre) ? SuccWideLook.nationRoom : SuccWideLook.endRoom;
    final padR = bands.any((b) => b.side == SuccWideSide.post) ? SuccWideLook.nationRoom : SuccWideLook.endRoom;
    final span = math.max(data.to - data.from, eps);
    var shortest = double.infinity;
    for (final b in bands) {
      if (b.isLeader) shortest = math.min(shortest, math.max(b.b - b.a, 1.0));
    }
    // 서랍 폭에 맞추되, 가장 짧은 재위가 자리 28보다 좁으면 그만큼 넓힌다(가로로 끎).
    final s = math.max(1e-3, math.max((width - padL - padR) / span, shortest.isFinite ? SuccWideLook.minTag / shortest : 0.0));
    final total = math.max(width, (padL + padR + s * span).ceilToDouble());
    final t0 = data.from - padL / s, t1 = data.to + padR / s;
    double xOf(double t) => (t - t0) * s;

    // 그리는 해(표 범위로 자름 — 앞뒤 나라는 40 이상 · 지도자는 1px 이상).
    final da = List<double>.filled(n, 0), db = List<double>.filled(n, 0);
    final openL = List<bool>.filled(n, false), openR = List<bool>.filled(n, false);
    for (var i = 0; i < n; i++) {
      final b = bands[i];
      openL[i] = b.openL || b.a < t0 - eps;
      openR[i] = b.openR || b.b > t1 + eps;
      var a = math.max(b.a, t0), z = math.min(b.b, t1);
      if (b.isLeader) {
        z = math.max(z, a + 1 / s);
      } else {
        final least = SuccWideLook.minNation / s;
        // 표 밖에서 시작하는 뒤 나라(한참 뒤의 부흥 따위) · 표 밖에서 끝난 앞 나라는 앞뒤 나라 자리를 통째로 쓴다(해 글은 제 해 그대로 · 열린 끝).
        if (b.side == SuccWideSide.post && a > t1 - least) a = data.to;
        if (b.side == SuccWideSide.pre && z < t0 + least) z = data.from;
        if (z - a < least) {
          if (b.side == SuccWideSide.post) {
            z = math.min(t1, math.max(z, a + least));
            a = math.max(t0, math.min(a, z - least));
          } else {
            a = math.max(t0, math.min(a, z - least));
            z = math.min(t1, math.max(z, a + least));
          }
        }
      }
      da[i] = a;
      db[i] = z;
    }

    // 줄 — 지도자 먼저, 그다음 앞 나라 · 뒤 나라를 겹치지 않는 첫 줄에(뒤 나라가 둘이면 둘째는 다음 줄).
    final rowOf = List<int>.filled(n, 0);
    final lanes = <List<int>>[];
    for (final side in const [SuccWideSide.leader, SuccWideSide.pre, SuccWideSide.post]) {
      for (var i = 0; i < n; i++) {
        if (bands[i].side != side) continue;
        bool clash(int j) => da[i] < db[j] - eps && da[j] < db[i] - eps;
        var r = 0;
        while (r < lanes.length && lanes[r].any(clash)) {
          r++;
        }
        if (r == lanes.length) lanes.add(<int>[]);
        lanes[r].add(i);
        rowOf[i] = r;
      }
    }
    final rows = math.max(1, lanes.length);

    // 이음 — 드는 수 · 나가는 띠 · 갈래 실이 세로로 지나는 해(그 해의 두 줄 모두 — 목업 BRANCH).
    final incoming = List<int>.filled(n, 0), out = List<bool>.filled(n, false);
    final branch = <String>{};
    for (final l in data.links) {
      incoming[l.to]++;
      out[l.from] = true;
      if (rowOf[l.from] != rowOf[l.to]) {
        branch
          ..add('${rowOf[l.from]}:${db[l.from]}')
          ..add('${rowOf[l.to]}:${db[l.from]}');
      }
    }
    double inset(int r, double t) => branch.contains('$r:$t') ? SuccWideLook.branch : SuccWideLook.join;

    final boxes = <Rect>[], holes = <Offset?>[], diamonds = <Offset?>[];
    final names = <SuccWideName>[], nameLeft = <double>[], ordWidth = <double>[], years = <String?>[];
    String year(double t) => t.isFinite ? kinYear(civilAt(t).year) : '';
    for (var i = 0; i < n; i++) {
      final b = bands[i], r = rowOf[i], top = rowTop(r);
      // 승계가 드나드는 끝은 2씩 들임(맞닿은 두 꼬리표 사이 4) · 갈래 실이 지나는 해는 5(사이 10) · 표 끝은 들이지 않음.
      final inL = da[i] <= t0 + eps ? 0.0 : (incoming[i] > 0 || branch.contains('$r:${da[i]}') ? inset(r, da[i]) : 0.0);
      final inR = db[i] >= t1 - eps ? 0.0 : (out[i] || branch.contains('$r:${db[i]}') ? inset(r, db[i]) : 0.0);
      final left = (xOf(da[i]) + inL).roundToDouble();
      final right = math.max(left + 1, (xOf(db[i]) - inR).roundToDouble());
      final box = Rect.fromLTRB(left, top, right, top + SuccWideLook.row);
      boxes.add(box);
      final hole = openL[i] ? null : succHoleAt(box);
      final diamond = out[i] && !openR[i] ? succDiamondRight(box) : null;
      holes.add(hole);
      diamonds.add(diamond);
      // 이름 — 대수 + 이름이 들면 둘 다, 이름만 들면 이름만, 아니면 열쇠표로(목업 `q.label`).
      final nx = hole != null ? hole.dx + SuccWideLook.nameAfterHole : box.left + .5 + SuccWideLook.fade + 2;
      final rlim = (diamond != null ? diamond.dx - SuccWideLook.nameBeforeDiamond : box.right - .5 - 6) - (openR[i] ? SuccWideLook.fade - 6 : 0);
      final pw = b.ordinal.isEmpty ? 0.0 : measure(TextSpan(text: b.ordinal, style: ordStyle(b.color))) + SuccWideLook.ordGap;
      final nw = measure(TextSpan(text: b.name, style: nameStyle(b.color)));
      names.add(pw + nw <= rlim - nx ? SuccWideName.full : (nw <= rlim - nx ? SuccWideName.name : SuccWideName.key));
      nameLeft.add(nx - box.left);
      ordWidth.add(names.last == SuccWideName.full ? pw : 0);
      final y = openL[i] ? '~ ${year(b.b)}' : (openR[i] ? '${year(b.a)} ~' : '${year(b.a)} ~ ${year(b.b)}');
      final room = box.right - .5 - SuccWideLook.yearsRight - nx - (openR[i] ? SuccWideLook.fade - 6 : 0);
      years.add(measure(TextSpan(text: y, style: yearStyle(b.color))) <= room ? y : null);
    }

    // 열쇠표 — 줄마다 왼쪽부터(앞 열쇠표에 밀리면 오른쪽으로), 그다음 뒤에서부터 창 끝 안으로(왼쪽으로). 그래도 앞 열쇠표와 겹치면 그리지 않는다.
    final keys = <SuccWideKey>[];
    InlineSpan? keyOf(int i) {
      final b = bands[i];
      final parts = <InlineSpan>[
        if (names[i] == SuccWideName.key) TextSpan(text: b.ordinal.isEmpty ? b.name : '${b.ordinal} ${b.name}', style: TextStyle(fontWeight: FontWeight.w700, color: SheetLook.tagInk(b.color))),
        if (b.again) const TextSpan(text: '다시', style: TextStyle(fontWeight: FontWeight.w700, color: SheetLook.ink85)),
        ?b.key,
      ];
      if (parts.isEmpty) return null;
      return TextSpan(children: [
        for (var k = 0; k < parts.length; k++) ...[if (k > 0) const TextSpan(text: ' · '), parts[k]],
      ]);
    }

    for (var r = 0; r < rows; r++) {
      final list = <(int, InlineSpan, double)>[];
      for (final i in [for (var i = 0; i < n; i++) i]..sort((x, y) => boxes[x].left.compareTo(boxes[y].left))) {
        if (rowOf[i] != r || openL[i]) continue;
        final text = keyOf(i);
        if (text == null) continue;
        final w = (SuccWideLook.keyLead + measure(TextSpan(style: keyStyle, children: [text])) + SuccWideLook.keyTail).ceilToDouble();
        list.add((i, text, w));
      }
      final kx = <double>[];
      var last = double.negativeInfinity;
      for (final (i, _, w) in list) {
        final x = math.max(last + SuccWideLook.keyGap, math.min(boxes[i].left + SuccWideLook.keyLeft, total - w));
        kx.add(x);
        last = x + w;
      }
      var limit = total;
      for (var k = list.length - 1; k >= 0; k--) {
        if (kx[k] + list[k].$3 > limit) kx[k] = limit - list[k].$3;
        limit = kx[k] - SuccWideLook.keyGap;
      }
      var floor = 0.0;
      for (var k = 0; k < list.length; k++) {
        final (i, text, w) = list[k];
        if (kx[k] < floor - eps) continue;
        floor = kx[k] + w + SuccWideLook.keyGap;
        final band = boxes[i];
        final box = Rect.fromLTWH(kx[k], band.top - SuccWideLook.keyAbove, w, SuccLook.keyBox);
        final hole = box.topLeft + SheetKeyLabel.shape.holeAt!;
        // 45° 실 — 띠 윗변의 (열쇠표 왼쪽 − 2.5)에서. 밀려 띠 밖이면 띠 안 끝(오른쪽 10 · 왼쪽 4 안)으로.
        final lo = band.left + 4.5, hi = math.max(lo, band.right - 10.5);
        final foot = Offset((box.left - SuccLook.keyFromBack).clamp(lo, hi), band.top + .5);
        keys.add(SuccWideKey(i, box, text, foot, hole));
      }
    }

    // 눈금 — 표의 두 끝은 눈금이 아님(앞뒤 나라가 그 너머로 이어짐).
    var pair = tickPairs[3];
    if (pair.$2 * s < SuccWideLook.labelMin || pair.$2 * s > SuccWideLook.labelMax) pair = tickPairs.firstWhere((p) => p.$2 * s >= SuccWideLook.labelMin, orElse: () => tickPairs.last);
    final (minor, major) = pair;
    final ticks = <SuccWideTick>[];
    for (var t = (t0 / minor).ceilToDouble() * minor; t <= t1 + eps; t += minor) {
      if ((t - t0).abs() < eps || (t - t1).abs() < eps) continue;
      final x = xOf(t).floorToDouble() + .5;
      final big = (t / major - (t / major).roundToDouble()).abs() < eps;
      String? label;
      if (big) {
        final text = year(t);
        if (x + SuccWideLook.tickLabelLeft + measure(TextSpan(text: text, style: tickStyle(true))) <= total) label = text;
      }
      ticks.add(SuccWideTick(x, big, label));
    }

    // 실 — 같은 줄이면 마름모 → 구멍 곧게 · 줄을 건너면 틈의 세로 통로에서 곧게 굽음(세로는 띠 뒤) · 합쳐지면 모인 자리에 매듭.
    final threads = <SuccWideThread>[], knots = <Offset>[];
    for (var k = 0; k < data.links.length; k++) {
      final l = data.links[k];
      final d = diamonds[l.from], h = holes[l.to];
      if (d == null || h == null) continue;
      final end = h.dx - SheetLook.holeRadius;
      if ((d.dy - h.dy).abs() < 1) {
        threads.add(SuccWideThread(k, l.line, [SuccWideSeg.h(d.dx, end, d.dy)], same: true));
        continue;
      }
      final x1 = boxes[l.from].right - .5, x0 = boxes[l.to].left + .5;
      final xv = x0 - x1 < 12 ? ((x1 + x0) / 2).floorToDouble() + .5 : x1 + 8;
      final r = [6.0, (h.dy - d.dy).abs() / 2, math.max(0.0, end - xv), math.max(0.0, xv - d.dx)].reduce(math.min);
      final up = h.dy < d.dy ? -1.0 : 1.0;
      threads.add(SuccWideThread(k, l.line, [
        SuccWideSeg.h(d.dx, xv - r, d.dy),
        SuccWideSeg.bend(Offset(xv - r, d.dy), Offset(xv, d.dy), Offset(xv, d.dy + up * r)),
        SuccWideSeg.v(xv, d.dy + up * r, h.dy - up * r),
        SuccWideSeg.bend(Offset(xv, h.dy - up * r), Offset(xv, h.dy), Offset(xv + r, h.dy)),
        SuccWideSeg.h(xv + r, end, h.dy),
      ], same: false));
      if (incoming[l.to] > 1) knots.add(Offset(xv, h.dy));
    }

    final height = rowTop(rows - 1) + SuccWideLook.row + SuccWideLook.below;
    return SuccWidePlan._(data, total, height, s, t0, t1, rows, rowOf, boxes, openL, openR, holes, diamonds, names, nameLeft, ordWidth, years, keys, ticks, threads, knots);
  }
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  그리개 — 띠 · 실(띠 뒤 · 띠 위) · 눈금
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 넓은 창의 꼬리표(가로 꼴): 칠 제 색 24%(올리면 먹 4% 더) · 머리 24 밑 흰 층 16(왼쪽 아래 귀는 모따기 — 열린 왼끝은 직각) ·
/// 머리 밑선과 테 = 제 색 84% + 먹(고리 칠 — 열린 끝은 그쪽 세로 테 없이) · 구멍(열린 왼끝이 아니면). 마름모는 실 위에 따로 그린다.
class SuccWideTagPainter extends CustomPainter {
  const SuccWideTagPainter({required this.color, this.openL = false, this.openR = false, this.hover = false});
  final Color color;
  final bool openL, openR, hover;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final fill = SheetLook.tagFill(color), edge = SheetLook.tagEdge(color);
    final kind = openL ? SheetTagKind.plain : SheetTagKind.cham;
    canvas.drawPath(sheetTagPath(box, kind), Paint()..color = hover ? SuccLook.lift(fill) : fill);
    final x0 = .5, x1 = size.width - .5, ys = SuccLook.head - .5, yb = size.height - .5, ch = openL ? 0.0 : SheetLook.tagChamfer;
    canvas.drawPath(
      Path()
        ..moveTo(x1, ys)
        ..lineTo(x0, ys)
        ..lineTo(x0, yb - ch)
        ..lineTo(x0 + ch, yb)
        ..lineTo(x1, yb)
        ..close(),
      Paint()..color = hover ? SheetLook.ink4 : SheetLook.paper,
    );
    canvas.drawRect(Rect.fromLTRB(openL ? 0 : 1, ys - .5, size.width, ys + .5), Paint()..color = edge);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(openL ? 1 : -1, -1, openR ? size.width - 1 : size.width + 1, size.height + 1));
    canvas.drawPath(sheetTagRing(box, kind), Paint()..color = edge);
    canvas.restore();
    if (!openL) paintSuccHole(canvas, succHoleAt(box));
  }

  @override
  bool shouldRepaint(SuccWideTagPainter old) => old.color != color || old.openL != openL || old.openR != openR || old.hover != hover;
}

/// 실 토막 하나를 그 갈래의 꼴로 — 같은 줄의 곧은 실은 이음매 갈래 그대로, 줄을 건너는 실은 바탕 꼴(이은 · 점선 · 가는 · 옅은)로.
void _paintSeg(Canvas canvas, SuccWideSeg seg, int line, {required bool same}) {
  final base = same || line == SuccLine.dashed || line == SuccLine.thin || line == SeamLine.blank ? line : (line == SeamLine.unknown ? SuccLine.dashed : SeamLine.solid);
  switch (seg.kind) {
    case 0:
      if (seg.end > seg.start) SuccThread.of(base, at: seg.across, a: seg.start, b: seg.end, vertical: false).paint(canvas);
    case 1:
      final a = math.min(seg.start, seg.end), b = math.max(seg.start, seg.end);
      if (b > a) SuccThread.of(base, at: seg.across, a: a, b: b).paint(canvas);
    default:
      if ((seg.a - seg.b).distance < .01) return;
      canvas.drawPath(
        Path()
          ..moveTo(seg.a.dx, seg.a.dy)
          ..quadraticBezierTo(seg.c!.dx, seg.c!.dy, seg.b.dx, seg.b.dy),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = base == SuccLine.thin ? 1 : SuccLook.thread
          ..color = base == SeamLine.blank ? SheetLook.ink25 : SheetLook.ink45,
      );
  }
}

/// 띠 뒤 — 눈금(짧은 금 먹 25 · 큰 금 아래 점선 먹 12) · 열쇠표의 45° 실(먹 45 · 1px) · 줄을 건너는 실의 세로 토막.
class _BackPainter extends CustomPainter {
  const _BackPainter(this.plan);
  final SuccWidePlan plan;

  @override
  void paint(Canvas canvas, Size size) {
    final short = Paint()..color = SheetLook.ink25, dash = Paint()..color = SheetLook.ink12;
    for (final t in plan.ticks) {
      final x = t.x - .5;
      canvas.drawRect(Rect.fromLTWH(x, SuccWideLook.tickTop, 1, SuccWideLook.tickBottom - SuccWideLook.tickTop), short);
      if (!t.major) continue;
      for (var y = SuccWideLook.tickBottom; y < plan.height; y += SuccWideLook.tickDash + SuccWideLook.tickGap) {
        canvas.drawRect(Rect.fromLTRB(x, y, x + 1, math.min(plan.height, y + SuccWideLook.tickDash)), dash);
      }
    }
    final key = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = SheetLook.ink45;
    for (final k in plan.keys) {
      canvas.drawLine(k.from, k.to, key);
    }
    for (final th in plan.threads) {
      for (final seg in th.segs) {
        if (seg.kind == 1) _paintSeg(canvas, seg, th.line, same: th.same);
      }
    }
  }

  @override
  bool shouldRepaint(_BackPainter old) => !identical(old.plan, plan);
}

/// 띠 위 — 실(가로 · 굽음) · 꼬리 마름모(제 색 60% + 먹) · 합쳐짐 매듭(반지름 2 · 먹 45).
class _FrontPainter extends CustomPainter {
  const _FrontPainter(this.plan);
  final SuccWidePlan plan;

  @override
  void paint(Canvas canvas, Size size) {
    for (final th in plan.threads) {
      for (final seg in th.segs) {
        if (seg.kind != 1) _paintSeg(canvas, seg, th.line, same: th.same);
      }
    }
    for (var i = 0; i < plan.boxes.length; i++) {
      final d = plan.diamonds[i];
      if (d != null) paintSuccDiamond(canvas, d, plan.data.bands[i].color);
    }
    for (final k in plan.knots) {
      canvas.drawCircle(k, SuccLook.knot, Paint()..color = SheetLook.ink45);
    }
  }

  @override
  bool shouldRepaint(_FrontPainter old) => !identical(old.plan, plan);
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  표 위젯
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 넓은 창의 표 — 띠 뒤 그림(눈금 · 열쇠표 실 · 세로 실) · 해 글 · 꼬리표 · 띠 위 그림(실 · 마름모 · 매듭) · 열쇠표 차례로 쌓는다.
/// [onBand]는 띠를 눌렀을 때(차례 번호).
class SuccWideChart extends StatelessWidget {
  const SuccWideChart({super.key, required this.plan, this.onBand});
  final SuccWidePlan plan;
  final void Function(int band)? onBand;

  @override
  Widget build(BuildContext context) {
    final bands = plan.data.bands;
    return SizedBox(
      width: plan.width,
      height: plan.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: CustomPaint(painter: _BackPainter(plan))),
          for (final t in plan.ticks)
            if (t.label != null)
              Positioned(
                left: (t.x - .5) + SuccWideLook.tickLabelLeft,
                top: SuccWideLook.tickMid - SuccWideLook.tickText / 2,
                height: SuccWideLook.tickText,
                child: succLine(t.label!, SuccWidePlan.tickStyle(true)),
              ),
          for (var i = 0; i < bands.length; i++)
            Positioned.fromRect(
              rect: plan.boxes[i],
              child: SuccWideTag(plan: plan, index: i, onTap: onBand == null ? null : () => onBand!(i)),
            ),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FrontPainter(plan)))),
          for (final k in plan.keys) Positioned.fromRect(rect: k.box, child: IgnorePointer(child: SuccKeyLabel(k.text))),
        ],
      ),
    );
  }
}

/// 꼬리표 하나 — 머리 24(대수 8.5 + 이름 9 굵게 · 열쇠표로 옮겼으면 비움) · 흰 층 16(해 8.5 — 들 때만) · 열린 끝은 32px 옅어짐.
class SuccWideTag extends StatelessWidget {
  const SuccWideTag({super.key, required this.plan, required this.index, this.onTap});
  final SuccWidePlan plan;
  final int index;
  final VoidCallback? onTap;

  /// 읽기 글 — 지도자는 '대수 이름', 앞뒤 나라는 '앞 나라 · 이름' · '뒤 나라 · 이름'.
  String get semantics {
    final b = plan.data.bands[index];
    return switch (b.side) {
      SuccWideSide.leader => '${b.ordinal} ${b.name}'.trim(),
      SuccWideSide.pre => '앞 나라 ${b.name}',
      SuccWideSide.post => '뒤 나라 ${b.name}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final b = plan.data.bands[index], box = plan.boxes[index];
    final openL = plan.openL[index], openR = plan.openR[index];
    final name = plan.names[index], years = plan.years[index], left = plan.nameLeft[index];
    Widget body(bool hover) {
      Widget tag = CustomPaint(
        painter: SuccWideTagPainter(color: b.color, openL: openL, openR: openR, hover: hover),
        child: SizedBox(
          width: box.width,
          height: box.height,
          child: ClipRect(
            child: Stack(children: [
              if (name != SuccWideName.key)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: SuccLook.head,
                  child: CustomMultiChildLayout(
                    delegate: _HeadLine(left: left, ord: plan.ordWidth[index]),
                    children: [
                      if (name == SuccWideName.full) LayoutId(id: 'ord', child: succLine(b.ordinal, SuccWidePlan.ordStyle(b.color))),
                      LayoutId(id: 'name', child: succLine(b.name, SuccWidePlan.nameStyle(b.color))),
                    ],
                  ),
                ),
              if (years != null)
                Positioned(
                  left: left,
                  right: 0,
                  top: SuccLook.head,
                  height: SuccLook.floor - 1,
                  child: Align(alignment: Alignment.centerLeft, child: succLine(years, SuccWidePlan.yearStyle(b.color))),
                ),
            ]),
          ),
        ),
      );
      if (openL || openR) {
        final f = (SuccWideLook.fade / box.width).clamp(0.0, .5);
        tag = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [if (openL) Colors.transparent, Colors.black, Colors.black, if (openR) Colors.transparent],
            stops: [if (openL) 0, openL ? f : 0, openR ? 1 - f : 1, if (openR) 1],
          ).createShader(rect),
          child: tag,
        );
      }
      return tag;
    }

    return SuccPress(onTap: onTap, semantics: semantics, builder: body);
  }
}

/// 머리 글 — 대수(있으면)와 이름을 제 자리 x에, 세로는 머리 24의 가운데(온 화소 — 좁은 창의 꼬리표와 같은 셈).
class _HeadLine extends MultiChildLayoutDelegate {
  _HeadLine({required this.left, required this.ord});
  final double left, ord;

  @override
  void performLayout(Size size) {
    double mid(Size s) => ((size.height - s.height) / 2).roundToDouble();
    final loose = BoxConstraints(maxHeight: size.height);
    if (hasChild('ord')) {
      final o = layoutChild('ord', loose);
      positionChild('ord', Offset(left, mid(o)));
    }
    final n = layoutChild('name', loose);
    positionChild('name', Offset(left + ord, mid(n)));
  }

  @override
  bool shouldRelayout(_HeadLine old) => old.left != left || old.ord != ord;
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  서랍 — 연표 위 층(앱 틀이 `Positioned.fill`로 둔다 · 닫혀 있으면 자리를 차지하지 않는다)
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 승계표 넓은 창의 층. [onInset]은 서랍의 키(연표가 비킬 몫 — [insetOn])가 바뀌면 부른다(앱 틀이 다시 그려 배율 알약 · 상세 칸을 올림).
class SuccessionDrawer extends StatefulWidget {
  const SuccessionDrawer({super.key, required this.bus, this.onInset});
  final AppBus bus;
  final VoidCallback? onInset;

  static final _mounted = <AppBus>{};
  static final _insets = <AppBus, double>{};

  /// 이 길에 서랍 층이 붙어 있는가(좁은 창의 '넓게'가 설지).
  static bool mountedOn(AppBus bus) => _mounted.contains(bus);

  /// 서랍이 연표 아래에서 차지한 키(폴더 · 흰 둘레 · 아래 14) — 닫혀 있거나 숨었으면 0. 앱 틀의 `stageBottomInset`이 읽는다.
  static double insetOn(AppBus bus) => _insets[bus] ?? 0;

  /// 지금 서랍을 열 수 있는가 — 층이 붙어 있고, 휴대폰이 아니며, 창 폭이 860 이상.
  static bool canOpen(BuildContext context, AppBus bus) => mountedOn(bus) && !SceneView.phone && (MediaQuery.maybeSizeOf(context)?.width ?? 0) >= SuccWideLook.minWidth;

  @override
  State<SuccessionDrawer> createState() => SuccessionDrawerState();
}

class SuccessionDrawerState extends State<SuccessionDrawer> {
  late final SurfaceMotion _enter = SurfaceMotion();
  final _folderKey = GlobalKey();
  final _scroll = ScrollController();

  SuccWideData? _data;
  SuccWidePlan? _plan;
  String? _uid;
  int _turn = 0;
  bool _hidden = false, _revealed = false, _publishing = false;

  /// 같은 키 누름에서 다른 쪽이 이미 무언가를 닫았는가(Esc 차례) — 다음 마이크로태스크에 풀린다(단체 계보 창과 같은 규칙).
  bool _handledNow = false;

  AppBus get _bus => widget.bus;

  /// 열려 있는 정권의 자료 · 마지막 자리 셈(검사가 본다).
  SuccWideData? get data => _data;
  SuccWidePlan? get plan => _plan;

  /// 열려 있는가(자료를 받았고 슬롯이 그 정권).
  bool get isOpen => _uid != null && _data != null;

  /// 열려 있지만 좁은 폭 · 휴대폰이라 숨었는가.
  bool get hidden => _hidden;

  @override
  void initState() {
    super.initState();
    SuccessionDrawer._mounted.add(_bus);
    _enter.addStatusListener(_onStatus);
    _listen(_bus, true);
    HardwareKeyboard.instance.addHandler(_escape);
    _onSlot();
  }

  @override
  void didUpdateWidget(SuccessionDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bus != widget.bus) {
      SuccessionDrawer._mounted.remove(oldWidget.bus);
      SuccessionDrawer._insets.remove(oldWidget.bus);
      _listen(oldWidget.bus, false);
      SuccessionDrawer._mounted.add(_bus);
      _listen(_bus, true);
      _onSlot();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      if (_enter.isAnimating) _enter.value = _uid == null ? 0 : 1;
    }
  }

  @override
  void dispose() {
    SuccessionDrawer._mounted.remove(_bus);
    SuccessionDrawer._insets.remove(_bus);
    _listen(_bus, false);
    HardwareKeyboard.instance.removeHandler(_escape);
    _enter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _listen(AppBus bus, bool on) {
    void hook(ValueNotifier<Object?> slot, VoidCallback f) => on ? slot.addListener(f) : slot.removeListener(f);
    hook(bus.slot(succWideSlot), _onSlot);
    hook(bus.slot(groupTreeSlot), _onGroupTree);
    hook(bus.slot(slotCommand), _onCommand);
    hook(bus.slot(slotZen), _markHandled);
    hook(bus.slot(_lensSlot), _markHandled);
  }

  // ── 여닫기 ────────────────────────────────────────────────────────────────────────────────

  void _onSlot() {
    final v = _bus.slot(succWideSlot).value;
    if (v is String && v.isNotEmpty) {
      // 단체 계보 창과 한 자리 — 이쪽을 열면 그쪽을 닫는다(대본의 slot 걸음처럼 슬롯을 바로 써도).
      if (_bus.slot(groupTreeSlot).value != null) _bus.slot(groupTreeSlot).value = null;
      if (v != _uid || _data == null) unawaited(_load(v));
    } else if (_uid != null) {
      _shut();
    }
  }

  /// 단체 계보 창이 열리면 이 창은 닫는다(한 자리).
  void _onGroupTree() {
    if (_bus.slot(groupTreeSlot).value != null && _bus.slot(succWideSlot).value != null) closeSuccessionWide(_bus);
  }

  /// 항목 기록(정권 · 앞뒤 나라 — 작은 기록이라 [detailEntity]로 받아 푼다 · 계보 뼈대는 이 창이 받지 않는다).
  Future<Map<String, dynamic>?> _record(String uid) => detailEntity(_bus, uid);

  /// 앞뒤 나라의 해 — 그 나라 기록(start · endY)을 받고, 받지 못하면 `x_succ`의 해 글.
  Future<(double?, double?)> _spanOf(Map<String, dynamic> e) async {
    final uid = detailString(e, 'uid');
    final json = uid.isEmpty ? null : await _record(uid);
    double? n(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    if (json != null && n(json['start']) != null) return (n(json['start']), n(json['endY']) ?? n(json['end']));
    return succWhenSpan(detailString(e, 'when'));
  }

  Future<void> _load(String uid) async {
    final turn = ++_turn;
    _uid = uid;
    final json = await _record(uid);
    if (!mounted || turn != _turn) return;
    final succ = json?['x_succ'];
    final nations = succ is Map ? [...detailList(succ.cast<String, dynamic>(), 'pre'), ...detailList(succ.cast<String, dynamic>(), 'post')] : const <Map<String, dynamic>>[];
    final spans = <String, (double?, double?)>{};
    await Future.wait([
      for (final e in nations)
        () async {
          final key = detailString(e, 'uid');
          if (key.isNotEmpty) spans[key] = await _spanOf(e);
        }(),
    ]);
    if (!mounted || turn != _turn) return;
    final data = json == null ? null : SuccWideData.parse(uid, json, spans: spans);
    if (data == null) {
      _bus.slot(slotNotice).value = '승계표를 그릴 지도자가 없습니다 — 이 기록에는 지도자 목록이 실려 있지 않습니다.';
      if (_bus.slot(succWideSlot).value == uid) closeSuccessionWide(_bus);
      return;
    }
    setState(() {
      _data = data;
      _revealed = false;
    });
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _shut() {
    _turn++;
    _uid = null;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _enter.value = 0;
      _data = null;
    } else {
      _enter.reverse();
    }
    setState(() {});
  }

  void _onStatus(AnimationStatus status) {
    if (!mounted) return;
    // 닫는 움직임이 끝나면 자료를 놓는다.
    if (status == AnimationStatus.dismissed && _uid == null) _data = null;
    setState(() {});
  }

  // ── 누름 · 단추 ──────────────────────────────────────────────────────────────────────────

  /// 띠를 눌렀다 — 지도자는 그 칸 창, 앞뒤 나라는 그 나라 상세.
  void _onBand(int i) {
    final d = _data;
    if (d == null) return;
    final b = d.bands[i];
    if (b.isLeader) {
      _bus.select(d.uid, cell: 'leader:${b.index}');
    } else if (b.uid.isNotEmpty) {
      _bus.select(b.uid);
    }
  }

  static const _levelNames = {KinLevel.leaders: '지도자만', KinLevel.children: '자녀까지', KinLevel.branches: '파 이름까지', KinLevel.all: '모두'};

  /// '수준 ▾' — 넓은 창은 지도자만 그린다. 다른 수준을 고르면 이 서랍을 닫고 그 수준으로 좁은 창(상세 칸)을 연다.
  void _levelMenu(BuildContext button) {
    final d = _data;
    final box = button.findRenderObject();
    if (d == null || box is! RenderBox) return;
    final at = box.localToGlobal(Offset(0, box.size.height));
    unawaited(showTimelineMenu(context, [
      for (final e in _levelNames.entries)
        MenuRow(
          e.value,
          checked: e.key == KinLevel.leaders,
          keyText: e.key == KinLevel.leaders ? '' : '좁은 창',
          onSelected: e.key == KinLevel.leaders ? null : () => _toNarrow(d.uid, e.key),
        ),
    ], at: at));
  }

  void _toNarrow(String uid, KinLevel level) {
    _bus.slot(kinLevelSlot).value = {'uid': uid, 'level': level};
    closeSuccessionWide(_bus);
    final now = _bus.selection.value;
    // 이미 그 승계표가 열려 있으면 다시 열어 수준을 받게 한다.
    if (now != null && now.uid == uid && now.cell == successionCell) _bus.clearSelection();
    _bus.select(uid, cell: successionCell);
  }

  // ── 들을 것 · Esc ─────────────────────────────────────────────────────────────────────────

  void _onCommand() {
    final c = _bus.slot(slotCommand).value;
    if (c is AppCommand && (c.name == Cmd.close || c.name == Cmd.searchClose)) _markHandled();
  }

  void _markHandled() {
    _handledNow = true;
    scheduleMicrotask(() => _handledNow = false);
  }

  /// 렌즈(주제 보기) 슬롯의 이름 — 단축키 부품이 Esc로 렌즈를 끄면 같은 누름에 이 창까지 닫지 않으려고 듣는다(단체 계보 창과 같음).
  static const _lensSlot = 'themeLens';

  /// Esc — 메뉴 · 대화 상자 · 검색 칸 · 상세 창이 먼저(단축키 부품이 그쪽을 닫는다), 그다음 이 창(단체 계보 창 규칙 그대로).
  bool _escape(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape || !isOpen || _hidden || !mounted) return false;
    if (_handledNow || typingNow() || _bus.selection.value != null) return false;
    if (Navigator.maybeOf(context)?.canPop() ?? false) return false;
    closeSuccessionWide(_bus);
    return true;
  }

  // ── 연표 비킴 ─────────────────────────────────────────────────────────────────────────────

  /// 그린 뒤 서랍의 키를 적고(바뀌었으면 앱 틀을 다시 그리게), 처음 연 때는 그 나라 띠를 서랍 위의 보이는 자리로 데려온다.
  void _publishLater() {
    if (_publishing) return;
    _publishing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishing = false;
      if (!mounted) return;
      var inset = 0.0;
      final folder = _folderKey.currentContext?.findRenderObject();
      if (isOpen && !_hidden && folder is RenderBox && folder.hasSize) inset = (folder.size.height + SuccWideLook.bottomMargin + SheetLook.folderRim).ceilToDouble();
      if (inset != SuccessionDrawer.insetOn(_bus)) {
        SuccessionDrawer._insets[_bus] = inset;
        widget.onInset?.call();
      }
      final d = _data;
      if (inset > 0 && !_revealed && d != null) {
        _revealed = true;
        unawaited(_reveal(d.uid, inset));
      }
    });
  }

  /// 그 나라 띠가 서랍에 가려 있으면 서랍 위로(세로로만 · 이미 보이면 그대로 — 단체 계보 창의 `_reveal`과 같은 셈).
  Future<void> _reveal(String uid, double inset) async {
    int? row;
    try {
      final answer = await _bus.ask({
        'op': 'ids_of',
        'uids': [uid],
      });
      final bands = answer['bands'];
      if (bands is List) {
        for (final b in bands) {
          if (b is Map && b['uid'] == uid && b['row'] is num) row = (b['row'] as num).toInt();
        }
      }
    } catch (_) {
      return;
    }
    if (!mounted || row == null || !isOpen) return;
    final layout = _bus.scene.layout;
    if (row < 0 || row >= layout.rowCount || !layout.isVisible(row)) return;
    final top = layout.rowTop(row);
    if (top < 0) return;
    final height = layout.geo(row).height;
    final v = _bus.controller.view;
    final visible = v.bodyHeight - inset / v.mag;
    if (visible <= 0) return;
    if (top >= v.top && top + height <= v.top + visible) return;
    final want = top + height > v.top + visible ? top + height - visible + 8 : top - 8;
    _bus.controller.scrollTo(math.max(0, want));
  }

  // ── 그리기 ────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _publishLater();
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final hidden = SceneView.phone || box.maxWidth < SuccWideLook.minWidth;
        if (hidden != _hidden) {
          _hidden = hidden;
          _publishLater();
        }
        if (hidden) return const SizedBox.shrink();
        const rim = SheetLook.folderRim;
        return Stack(
          children: [
            Positioned(
              left: SuccWideLook.sideMargin - rim,
              right: SuccWideLook.sideMargin - rim,
              bottom: SuccWideLook.bottomMargin - rim,
              child: AnimatedBuilder(
                animation: _enter,
                builder: (context, child) => Opacity(
                  opacity: _enter.opacity,
                  child: Transform.translate(offset: Offset(0, 8 * (1 - _enter.value)), child: child),
                ),
                // 서랍 위(흰 둘레까지)의 누름 · 바퀴는 아래 연표로 내려가지 않는다(오른쪽 클릭 차림표도).
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(rim),
                    child: KeyedSubtree(key: succWideKey, child: _sheet(context, d, box.maxWidth - 2 * SuccWideLook.sideMargin)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sheet(BuildContext context, SuccWideData d, double width) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    double measure(InlineSpan span) {
      final tp = TextPainter(text: TextSpan(style: base, children: [span]), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    final inner = math.max(0.0, width - 2 * SuccWideLook.pad);
    final plan = _plan = SuccWidePlan.layout(d, width: inner, measure: measure);
    final titleStyle = sheetText(SuccLook.titleSize, bold: true), subStyle = sheetText(SuccLook.titleSub);
    final headW = (SuccLook.titleLead + math.max(measure(TextSpan(text: d.name, style: titleStyle)), measure(TextSpan(text: d.sub, style: subStyle))) + 24).ceilToDouble();
    Widget chart = SuccWideChart(plan: plan, onBand: _onBand);
    if (plan.width > inner + .5) {
      // 표가 서랍보다 넓다 — 가로로 끈다(마우스 끌기도).
      chart = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, dragDevices: PointerDeviceKind.values.toSet()),
        child: SingleChildScrollView(controller: _scroll, scrollDirection: Axis.horizontal, child: chart),
      );
    }
    return SheetFolder(
      key: _folderKey,
      label: '승계표',
      color: d.color,
      padding: const EdgeInsets.fromLTRB(SuccWideLook.pad, SuccWideLook.pad, SuccWideLook.pad, SuccWideLook.padBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: SuccLook.title,
            child: Row(children: [
              SizedBox(
                width: math.min(headW, inner / 2),
                child: SuccTitleTag(color: d.color, title: d.name, sub: d.sub, thread: SuccWideLook.titleThread, knot: false),
              ),
              const SizedBox(width: SuccWideLook.headGap),
              Expanded(child: _legendLine(d, measure)),
              Builder(
                builder: (context) => SheetPaperButton(label: '수준 ▾', height: SuccWideLook.button, pad: SuccWideLook.buttonPad, hint: '넓은 창은 지도자만 — 다른 수준은 좁은 창으로', onTap: () => _levelMenu(context)),
              ),
              const SizedBox(width: SuccWideLook.buttonGap),
              SheetPaperButton(label: '닫기', height: SuccWideLook.button, pad: SuccWideLook.buttonPad, onTap: () => closeSuccessionWide(_bus)),
            ]),
          ),
          const SizedBox(height: SuccWideLook.chartGap),
          SizedBox(height: plan.height, child: Semantics(container: true, label: '승계표 · ${d.name}', child: chart)),
        ],
      ),
    );
  }

  /// 한 줄 범례 — 자료에 쓰인 실 갈래 · 열쇠표, 먹 25 금, 정통성 넷, 먹 25 금. 자리가 모자라면 뒤에서부터 뺀다(겹침 · 넘침 없이).
  Widget _legendLine(SuccWideData d, SuccWideMeasure measure) => LayoutBuilder(
    builder: (context, box) {
      final textStyle = sheetText(SuccLook.legendText, color: SheetLook.ink60);
      double sampleW(String kind) => kind == SuccLegendKind.again
          ? (SuccWideLook.keyLead + measure(const TextSpan(text: '다시', style: TextStyle(fontWeight: FontWeight.w700, fontSize: SheetLook.keyText))) + SuccWideLook.keyTail).ceilToDouble()
          : SuccLook.legendSample;
      double itemW((String, String) it) => sampleW(it.$1) + SuccWideLook.legendTextGap + measure(TextSpan(text: it.$2, style: textStyle)).ceilToDouble();
      Widget item((String, String) it) => Row(mainAxisSize: MainAxisSize.min, children: [
        SuccLegendSample(it.$1, color: d.color),
        const SizedBox(width: SuccWideLook.legendTextGap),
        succLine(it.$2, textStyle),
      ]);
      const rule = SizedBox(width: 1, height: SuccWideLook.ruleHeight, child: ColoredBox(color: SheetLook.ink25));
      final kids = <Widget>[];
      var x = 0.0;
      bool fits(double w) => x + w <= box.maxWidth + .01;
      void put(Widget w, double width) {
        if (kids.isNotEmpty) {
          kids.add(const SizedBox(width: SuccWideLook.legendGap));
          x += SuccWideLook.legendGap;
        }
        kids.add(w);
        x += width;
      }

      for (final it in d.legend) {
        final w = itemW(it);
        if (!fits((kids.isEmpty ? 0 : SuccWideLook.legendGap) + w)) return _row(kids);
        put(item(it), w);
      }
      // 정통성 넷 — 앞뒤에 먹 25 금(넷이 다 들 때만 뒤 금).
      if (!fits((kids.isEmpty ? 0 : SuccWideLook.legendGap) + 1 + SuccWideLook.legendGap + itemW(SuccWideData.legit.first))) return _row(kids);
      put(rule, 1);
      var all = true;
      for (final it in SuccWideData.legit) {
        final w = itemW(it);
        if (!fits(SuccWideLook.legendGap + w)) {
          all = false;
          break;
        }
        put(item(it), w);
      }
      if (all && fits(SuccWideLook.legendGap + 1)) put(rule, 1);
      return _row(kids);
    },
  );

  static Widget _row(List<Widget> kids) => Row(mainAxisSize: MainAxisSize.min, children: kids);
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../scene/color_mix.dart';
import '../scene/fonts.dart';
import '../scene/marks.dart';
import '../scene/ruler.dart';
import '../shell/look.dart';
import '../shell/sheet_look.dart';
import '../shell/sheet_parts.dart';
import 'app_bus.dart';
import 'detail_shell.dart';
import 'shell_keys.dart';

// 승계표 넓은 창(화면 아래 서랍)은 이 창과 한 자리(연표 아래)라 함께 내보낸다 — 앱 틀이 가져오기 줄을 늘리지 않고 그 층을 붙이게.
export 'kin/succession_wide.dart' show SuccessionDrawer;

// ════════════════════════════════════════════════════════════════════════════════════════════
//  단체 계보 창 — 설계 D5 결정 4 A '아래쪽 넓은 창 · 가로 시간 나무'(docs/설계-10건/7-8-단체와-렌즈.md 9-1 · 감독-선택.md D5)
//  웹 js/group-tree.js의 창을 옮겼고, 리메이크 4단계 틀의 시트와 창 걸음 8(감독 고름 G5 #9 '서고로 다시 그림' — 다듬기 판 sht-gtree ·
//  `.claude/research/stage4-choose/themes/g-sheet-tree.js` — git 밖)에서 서고 꼴로 다시 그렸다. 기능 · 누르는 길 · 기억 · 움직임은 그대로다.
//
//  감독 원칙: 띠 · 창의 구분은 글 딱지가 아니라 테두리 · 모양 · 색으로 — 꼬리표 안에는 이름 · 기간 말고 글을 두지 않는다.
//
//  창: 연표 아래쪽에 붙는 넓은 창(연표 폭 그대로 · 높이 min(525px, 56%)) = 그 나라 색 폴더 '단체 계보'(제 색 9% · 테 55% · 어깨 탭 맨 글 12
//      제 색 25% + 먹 · 몸통의 아래 끝은 창 밖 — 연표 밑에 붙은 서랍).
//    · 머리 줄: 나라 꼬리표(누르면 나라 상세) · 범례 흰 종이 한 줄(갈라짐 · 합쳐짐 · 이름 바꿈 · 방식 미상 · 적지 않음 | 집권 · 연정 · 있던 기간) · 닫기 종이.
//    · 왼쪽 상자 '고른 단체'(연표의 이름 칸 자리): 단체 꼬리표 30 · 기간 · 조명 중 · [단체 창] [이 시기로] · 집권 n · 연정 m과 칸 견본 줄 ·
//      이어짐(앞 · 뒤 단체 꼬리표 — 누르면 그 단체를 고름 · 이음 갈래) · 안내 두 줄.
//    · 오른쪽 상자 '단체 {수}': 뚜껑에 큰 금마다 해 글 · 몸에 점선 금(25년 · 50년 — 보기 배율에 따라 짝을 바꿈). 연도 x는 위 연표와 같은 자리
//      (연표를 밀거나 당기면 나무도 함께 — 조종부를 듣는다).
//    · 단체 = 그림판의 단체 꼬리표 그대로(둥근 끝 12 · 구멍 · 머리 24에 이름 9 굵게 · 흰 층 16에 해 8.5 — 승계표의 이름띠와 같은 꼴) ·
//      집권 = 흰 층의 칠한 칸(제 색 45% · 연정 24% · 실권은 집권과 같은 칠 · 칸 금 먹 25) · 뒤가 있으면 꼬리 마름모.
//    · 실(먹 45 · 1.5): 끝에서 갈라짐 = 꼬리 마름모 → 앞 꼬리표 끝의 통로 → 세로 실 → 아이의 구멍 · 안에서 갈라짐 = 앞 꼬리표 아랫변의 매듭 →
//      아이 왼쪽 6의 세로 실 → 구멍 · 합쳐짐 = 실들이 매듭에서 모여 구멍 하나로 · 이름 바꿈 = 같은 줄의 짧은 실 ·
//      방식 미상 = 점 실 + 아이 위 열쇠표 '방식 미상' · 적지 않음 = 옅은 실(먹 25 · 1). 꺾이는 곳은 굽음 6.
//    · 고른 단체 = 고른 테(먹 100 · 1.5)와 검은 구멍 테 · 위 연표의 그 나라 띠에 집권 덩이마다 조명(bus.slot('spots')).
//    · 꼬리표를 누르면 그 단체를 고름 · 두 번 누르면 단체 창 · 실을 누르면 그 일의 사건(맺은 사건이 있을 때만).
//    · 그 나라 띠가 창에 가려 있으면 창 위로 데려온다(세로로만 · 이미 보이면 그대로).
//    · 열 때 보기: 나무 전체가 보기 밖이면 나무 전체로, 나무는 보이지만 고른 채로 연 단체가 보기 밖이면 그 단체의 기간으로.
//    · Esc: 상세 창이 열려 있으면 상세 창이 먼저(단축키 부품의 몫), 그다음 이 창.
//  줄 높이 = 꼬리표 40 + 사이 6(열쇠표가 달린 줄은 위로 14 더). 줄의 y는 앱이 셈한다(줄 번호 × 줄 간격 + 열쇠표 자리) — 배치 셈은 그대로.
//  곧은 실은 네모 칠(실제 앱(Windows GPU 그리기)에서 꺾인 길의 획이 옅게 나오던 일을 피함 — `sheet_parts.dart` [sheetTagRing]의 까닭) ·
//  굽음 · 45° 실만 선으로 긋는다.
//
//  나무의 배치는 새 앱이 셈하지 않는다 — 내보내기(prototype/scripts/export/entities.mjs groupWindowRefs)가 웹과 같은 셈(HT.groupTreeLayout)을
//  돌려 항목 기록에 실은 것을 그린다:
//    정권 기록 x_groupTree = { polity?, span:[분,분], rows, nodes:[{uid,name,color,row,span,when,range,type?,count?,segs?,spots?}], edges?:[…] }
//    단체 기록 x_treeAt   = 그 단체의 나무를 품은 정권 uid(나라 나무와 같을 때) · 아니면 단체 기록에 x_groupTree
//
//  ── 앱에 끼우는 법 ───────────────────────────────────────────────────────────────────────────
//    Stack(children: [ …연표…, Positioned.fill(child: GroupTreeLayer(bus: bus)) ])   ← 연표 위(묶음 카드 · 노선도와 같은 자리)
//    닫혀 있으면 아무 자리도 차지하지 않는다. 열기는 `openGroupTree(bus, 기록 uid, group: 단체 uid)` — 단체 창 · 나라 상세의
//    '단체 계보' 단추([GroupTreeButton])가 부른다. 단추는 이 층이 붙어 있을 때만 선다(붙지 않은 앱에서 누를 곳 없는 단추가 생기지 않게).
// ════════════════════════════════════════════════════════════════════════════════════════════

/// [AppBus.slot]에 쓰는 이름 — 값은 [GroupTreeRequest](열기) 또는 null(닫기).
const groupTreeSlot = 'groupTree';

/// 계보 창 한 장만 그림으로 뜰 때 붙잡는 열쇠(검사의 1배 그림 · 웹 창과 맞대기).
const groupTreeKey = ValueKey('단체 계보 창');

/// 단체 계보 창을 열어 달라는 부탁.
@immutable
class GroupTreeRequest {
  const GroupTreeRequest(this.uid, {this.group});

  /// 나무를 품은 기록(정권 — 그 나라의 나무 · 단체 — 그 단체의 나무 또는 x_treeAt으로 가리킨 나라).
  final String uid;

  /// 고른 채로 열 단체(없으면 아무것도 고르지 않음).
  final String? group;

  @override
  bool operator ==(Object other) => other is GroupTreeRequest && other.uid == uid && other.group == group;
  @override
  int get hashCode => Object.hash(uid, group);
}

/// 단체 계보 창을 연다(같은 부탁이어도 다시 연다).
void openGroupTree(AppBus bus, String uid, {String? group}) {
  final slot = bus.slot(groupTreeSlot);
  if (slot.value == GroupTreeRequest(uid, group: group)) slot.value = null;
  slot.value = GroupTreeRequest(uid, group: group);
}

/// 단체 계보 창을 닫는다.
void closeGroupTree(AppBus bus) => bus.slot(groupTreeSlot).value = null;

/// 이 기록에서 단체 계보를 열 수 있는가 — 나무를 품은 기록의 uid(제 기록이면 [uid], 나라 나무를 가리키면 그 나라). 없으면 null.
String? groupTreeHolder(Map<String, dynamic> json, String uid) {
  if (json['x_groupTree'] is Map) return uid;
  final at = json['x_treeAt'];
  return at is String && at.isNotEmpty ? at : null;
}

/// '단체 계보' 단추 — 단체 창의 아래 단추 줄 · 나라 상세의 '단체' 상자 머리(웹 `.sub-act`).
/// [bus]를 주지 않으면 창을 띄운 뼈대([DetailHost])의 길을 쓴다. 계보 창 층([GroupTreeLayer])이 붙어 있지 않으면 서지 않는다.
class GroupTreeButton extends StatelessWidget {
  const GroupTreeButton({super.key, required this.uid, this.group, this.bus});
  final String uid;
  final String? group;
  final AppBus? bus;

  @override
  Widget build(BuildContext context) {
    final b = bus ?? context.findAncestorWidgetOfExactType<DetailHost>()?.bus;
    if (b == null || uid.isEmpty || !GroupTreeLayer.mountedOn(b)) return const SizedBox.shrink();
    return DetailSmallButton('단체 계보', onTap: () => openGroupTree(b, uid, group: group));
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  1. 자료 — 내보내기가 실은 나무
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 막대 안 집권 덩이의 종류: 0 집권 · 1 연정 · 2 실권(칠은 집권과 같음).
enum GroupSegKind { power, coal, real }

@immutable
class GroupTreeSeg {
  const GroupTreeSeg(this.a, this.b, this.kind);
  final double a, b;
  final GroupSegKind kind;
}

@immutable
class GroupTreeNode {
  const GroupTreeNode({
    required this.uid,
    required this.name,
    required this.color,
    required this.row,
    required this.lo,
    required this.hi,
    this.when = '',
    this.range = '',
    this.type = '',
    this.count = '',
    this.segs = const [],
    this.spots = const [],
  });
  final String uid, name, when, range, type, count;
  final Color color;
  final int row;
  final double lo, hi;
  final List<GroupTreeSeg> segs;

  /// 고르면 위 연표에 켤 조명 [{uid, start, end}](분).
  final List<Map<String, dynamic>> spots;

  /// 막대의 풍선 글(웹 `n.tip`) — 이름 · 종류 · 기간 · 집권 n번.
  String get tip => '$name${type.isNotEmpty ? ' · $type' : ''} · $when${count.isNotEmpty ? ' · $count' : ''} — 누르면 연표에 조명 · 두 번 누르면 단체 창';
}

@immutable
class GroupTreeEdge {
  const GroupTreeEdge({required this.from, required this.to, required this.kind, this.same = false, this.after = false, this.ev = '', this.tip = ''});
  final int from, to;

  /// split · merge · rename · unknown(방식 미상) · blank(적지 않음).
  final String kind;

  /// 이름 바꿈을 같은 줄에 이어 씀(다리).
  final bool same;

  /// 뒤 단체가 앞 단체가 끝난 뒤 시작 — 세로 줄기가 앞 단체의 끝에서 내려온다.
  final bool after;

  /// 누르면 열 사건(없으면 누를 수 없음).
  final String ev;
  final String tip;
}

@immutable
class GroupTreeData {
  const GroupTreeData({required this.holder, required this.lo, required this.hi, required this.rows, required this.nodes, this.edges = const [], this.polityUid = '', this.polityName = '', this.polityColor});
  final String holder, polityUid, polityName;
  final Color? polityColor;
  final double lo, hi;
  final int rows;
  final List<GroupTreeNode> nodes;
  final List<GroupTreeEdge> edges;

  int indexOf(String uid) => nodes.indexWhere((n) => n.uid == uid);

  /// 기록의 `x_groupTree`를 읽는다(꼴이 틀리면 null).
  static GroupTreeData? parse(String holder, Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    double? n(Object? v) => v is num ? v.toDouble() : null;
    String s(Map<String, dynamic> o, String k) => o[k] is String ? o[k] as String : (o[k] == null ? '' : '${o[k]}');
    ({double lo, double hi})? span(Object? v) => v is List && v.length >= 2 && v[0] is num && v[1] is num ? (lo: (v[0] as num).toDouble(), hi: (v[1] as num).toDouble()) : null;
    final nodes = <GroupTreeNode>[];
    for (final raw in (m['nodes'] is List ? m['nodes'] as List : const [])) {
      if (raw is! Map) return null;
      final o = raw.cast<String, dynamic>();
      final sp = span(o['span']);
      if (sp == null) return null;
      nodes.add(GroupTreeNode(
        uid: s(o, 'uid'),
        name: s(o, 'name'),
        color: detailColor(o['color']),
        row: (n(o['row']) ?? 0).toInt(),
        lo: sp.lo,
        hi: math.max(sp.lo, sp.hi),
        when: s(o, 'when'),
        range: s(o, 'range'),
        type: s(o, 'type'),
        count: s(o, 'count'),
        segs: [
          for (final g in (o['segs'] is List ? o['segs'] as List : const []))
            if (g is List && g.length >= 3 && g[0] is num && g[1] is num && g[2] is num)
              GroupTreeSeg((g[0] as num).toDouble(), (g[1] as num).toDouble(), GroupSegKind.values[(g[2] as num).toInt().clamp(0, 2)]),
        ],
        spots: [
          for (final p in (o['spots'] is List ? o['spots'] as List : const []))
            if (p is Map) p.cast<String, dynamic>(),
        ],
      ));
    }
    if (nodes.isEmpty) return null;
    final edges = <GroupTreeEdge>[];
    for (final raw in (m['edges'] is List ? m['edges'] as List : const [])) {
      if (raw is! Map) continue;
      final o = raw.cast<String, dynamic>();
      final from = n(o['from'])?.toInt(), to = n(o['to'])?.toInt();
      if (from == null || to == null || from < 0 || to < 0 || from >= nodes.length || to >= nodes.length) continue;
      edges.add(GroupTreeEdge(from: from, to: to, kind: s(o, 'kind').isEmpty ? 'blank' : s(o, 'kind'), same: o['same'] == 1 || o['same'] == true, after: o['after'] == 1 || o['after'] == true, ev: s(o, 'ev'), tip: s(o, 'tip')));
    }
    final whole = span(m['span']) ?? (lo: nodes.map((x) => x.lo).reduce(math.min), hi: nodes.map((x) => x.hi).reduce(math.max));
    final polity = m['polity'] is Map ? (m['polity'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final rows = (n(m['rows']) ?? (nodes.map((x) => x.row).reduce(math.max) + 1)).toInt();
    return GroupTreeData(
      holder: holder,
      lo: whole.lo,
      hi: whole.hi,
      rows: math.max(rows, 1),
      nodes: nodes,
      edges: edges,
      polityUid: s(polity, 'uid'),
      polityName: s(polity, 'name'),
      polityColor: polity['color'] == null ? null : detailColor(polity['color']),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  2. 생김새 — 다듬기 판 sht-gtree(목업 g-sheet-tree `drawTree`)의 치수 · 먹은 시트 토큰(sheet_look.dart)의 여섯
// ────────────────────────────────────────────────────────────────────────────────────────────

abstract final class GroupTreeLook {
  // ---- 단체 꼬리표(그림판 꼬리표 · 승계표 이름띠와 같은 꼴) ----

  /// 머리 24 + 흰 층 16 = 바깥 화소 상자 40 · 줄 사이 6 → 줄 간격 46 · 열쇠표가 달린 줄은 위로 14 더(열쇠표 바깥 상자 13 + 틈 1 —
  /// 그림판에서 열쇠표가 달린 줄의 위 틈과 같은 셈).
  static const head = 24.0, floor = 16.0, barHeight = head + floor, rowGap = 6.0, pitch = barHeight + rowGap, keyRoom = 14.0;

  /// 나무 안 첫 줄 위 · 끝 줄 아래 여백(상자 뚜껑 밑선에서).
  static const top = 12.0, bottom = 12.0;

  /// 왼쪽 둥근 끝 12 · 들임: 승계가 드는 머리 · 나가는 끝 6(맞닿은 두 꼬리표 사이 12 — 세로 실이 양쪽 테에서 6) · 이름 바꿈(같은 줄) 4 ·
  /// 가장 좁은 폭 2.
  static const round = 12.0, indent = 6.0, renameIndent = 4.0, minWidth = 2.0;

  /// 구멍 · 꼬리 마름모가 서는 가장 좁은 꼬리표 폭(구멍 테는 왼쪽에서 12까지 · 마름모는 오른쪽에서 10.5부터 — 서로 닿지 않게).
  static const minHole = 14.0, minDiamond = 24.0;

  /// 글: 이름 9 굵게 탭 글(구멍 뒤 7부터 · 마름모 앞 6까지 — 마름모가 없으면 오른쪽 끝 6 안 · 머리 가운데) ·
  /// 해 8.5 이름 글(흰 층 가운데 · 이름과 같은 왼쪽 · 오른쪽 끝 4 안). 보이는 왼쪽 밖에서 시작한 꼬리표는 글을 보이는 왼쪽 8로 옮긴다.
  static const nameText = 9.0, yearText = 8.5, afterHole = 7.0, beforeDiamond = 6.0, nameRight = 6.0, yearsRight = 4.0, stickyLeft = 8.0;

  /// 집권 칸 칠 — 집권(실권도) = 제 색 45% · 연정 = 24%. 칸 금은 먹 25(꼬리표 끝 3 안 · 해 글 앞뒤 3에는 긋지 않음).
  static const powerShare = .45, coalShare = .24, cellClear = 3.0;

  // ---- 실 ----

  /// 이은 실(갈라짐 · 합쳐짐 · 이름 바꿈) 1.5 먹 45 · 옅은 실(적지 않음) 1 먹 25 · 점 실(방식 미상) 지름 1.75 · 3.5마다 먹 45 ·
  /// 꺾이는 곳 굽음 6 · 매듭 반지름 2. 실은 구멍 테에서 멎는다.
  static const thread = 1.5, faint = 1.0, dot = 1.75, dotStep = 3.5, bend = 6.0, knot = 2.0;

  /// 끝에서 갈라짐 · 합쳐짐의 세로 통로 — 앞 꼬리표 끝에서 6 밖(뒤 꼬리표와 12보다 가까우면 둘 사이 가운데).
  static const lane = 6.0;

  /// 열쇠표('방식 미상'): 아이 꼬리표 왼쪽에서 19 · 바깥 상자 13이 꼬리표 윗변 1 위(위로 14) · 45° 실은 꼬리표 윗변의 왼쪽 16.5에서 열쇠표 구멍까지.
  static const keyLeft = 19.0, keyAbove = 14.0, keyFrom = 16.5;

  // ---- 창 ----

  /// 창의 높이 `min(525px, 56%)`.
  static const maxHeight = 525.0, heightRatio = .56;

  /// 폴더: 화면 양옆 8 · 몸통의 아래 끝은 창 밖 24(아래 귀를 감춤 — 연표 밑에 붙은 서랍) · 안쪽 12 · 머리 줄 24 · 상자까지 10 ·
  /// 오른쪽 상자 '단체'는 연표 그림 영역 왼쪽 4 밖에서(나무의 x = 연표의 x) · 왼쪽 상자 '고른 단체'는 그 앞 12까지 — 150보다 좁으면 두지 않음.
  static const margin = 8.0, sink = 24.0, pad = 12.0, headRow = 24.0, headGap = 10.0, boxGap = 12.0, plotInset = 4.0, sideMin = 150.0;

  /// 머리 줄: 나라 꼬리표(글 11 굵게) 뒤 범례까지 12 이상 · 범례 뒤 닫기까지 12.
  static const headSpace = 12.0, headText = 11.0;

  /// 범례 종이(키 24): 견본 24 · 견본 뒤 6 · 글 11 먹 60 · 칸 사이 14 · 앞뒤 12 · 가름 금 먹 12(키 13).
  static const legendSample = 24.0, legendGap = 6.0, legendText = 11.0, legendSpacing = 14.0, legendPad = 12.0, legendRule = 13.0;

  /// 범례 견본의 빛깔 — 어느 단체의 색도 아닌 회청(목업 P.slate).
  static const legendColor = Color(0xffa4b1b7);

  /// 눈금: 작은 금 · 큰 금 모두 점선 2 3(큰 금 먹 12 · 작은 금 먹 4) · 큰 금마다 뚜껑에 해 글 10 먹 60(금 오른쪽 4 · 뚜껑 라벨 뒤 10부터 ·
  /// 오른쪽 끝 8 안) · 큰 금 사이가 60 ~ 600px 밖이면 짝을 바꿈(넓은 승계표와 같은 짝 — 300년 보기면 25년 · 50년).
  static const tickText = 10.0, tickLeft = 4.0, tickDash = 2.0, tickGap = 3.0, tickAfterLabel = 10.0, tickRight = 8.0, labelMin = 60.0, labelMax = 600.0;
  static const tickPairs = <(int, int)>[(1, 5), (5, 10), (10, 20), (25, 50), (50, 100), (100, 200), (250, 500), (500, 1000), (1000, 2000), (2500, 5000)];

  /// '고른 단체' 상자: 안쪽 12(아래 5) · 단체 꼬리표 30(이름 13 굵게 · 구멍 뒤 8) · 줄 22 · 이어짐 꼬리표 24(사이 6 · 글 11 굵게 · 앞 칸 22) ·
  /// 집권 칸 견본 18 × 10(글 앞 10) · 조명 표 16 × 9(먹 100 · 1.5 · 글 앞 6) · 안내 줄 17.
  static const sidePad = 12.0, sideBottom = 5.0, pickTag = 30.0, pickName = 13.0, pickLead = 17.5, line = 22.0, linkTag = 24.0, linkGap = 6.0, linkSide = 22.0;
  static const chipW = 18.0, chipH = 10.0, chipGap = 10.0, tipLine = 17.0;

  /// 왼쪽 상자의 안내 글(고른 단체가 없을 때 — 웹 HINT 그대로).
  static const hint = '막대를 누르면 위 연표의 그 나라 띠에 그 단체의 집권 기간이 조명됩니다. 이음선을 누르면 그 일(갈라짐 · 합쳐짐 · 이름 바꿈)의 사건. 연표를 밀거나 당기면 나무도 함께 움직입니다.';

  /// 고른 단체가 있을 때 상자 아래 두 줄(다듬기 판 그대로).
  static const tips = ['막대를 누르면 위 연표에 조명', '실을 누르면 그 일의 사건'];

  /// 이음 갈래의 이름(범례 · 이어짐 · 풍선).
  static const howWords = {'split': '갈라짐', 'merge': '합쳐짐', 'rename': '이름 바꿈', 'unknown': '방식 미상', 'blank': '적지 않음'};

  /// 집권 칸의 칠 — 제 색과 종이를 섞는다(in srgb).
  static Color segFill(Color c, GroupSegKind k) => Color(mixSrgb(c.toARGB32(), 0xffffffff, k == GroupSegKind.coal ? coalShare : powerShare));

  /// 그림(CustomPainter)이 쓰는 글 꼴 — 창의 글꼴(장면 글꼴)을 직접 준다.
  static TextStyle font(TextStyle s) => s.copyWith(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback);
  static TextStyle nameStyle(Color c) => font(sheetText(nameText, bold: true, color: SheetLook.tagInk(c)));
  static TextStyle yearStyle(Color c) => font(sheetText(yearText, color: SheetLook.nameInk(c)));
  static final keyStyle = font(sheetText(SheetLook.keyText, bold: true, color: SheetLook.ink60));
}

/// 꼬리표 흰 층의 해 글 — 내보내기의 `range`('842–905')를 '842 ~ 905'로(지금도 있는 단체는 '1402 ~ 현재').
String groupYears(GroupTreeNode g) {
  final parts = g.range.split('–');
  if (parts.length != 2) return g.range;
  final end = g.when.trimRight().endsWith('현재') ? '현재' : parts[1];
  return '${parts[0]} ~ $end';
}

/// 분 → 해 글(웹 HT.formatAxisYear — 정수 해 · 기원전).
String groupYearOf(double minute) => yearLabel((yearAt(minute) + 1e-6).floor());

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 자리 셈 — 화면과 무관 · 검사가 직접 본다
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 실의 꼴: 이은 실 · 옅은 실 · 점 실.
enum GroupLineStyle { solid, faint, dotted }

/// 단체 꼬리표 하나의 자리 — 바깥 화소 상자(정수 자리 · 키 40). 테는 반 픽셀 안쪽을 지난다.
@immutable
class GroupBarGeo {
  const GroupBarGeo(this.x1, this.x2, this.y, this.row, {this.tail = false});
  final double x1, x2, y;
  final int row;

  /// 꼬리 마름모에서 실이 나가는가(같은 줄로 잇거나 끝난 뒤에 시작한 뒤 단체가 있음).
  final bool tail;

  double get width => x2 - x1;
  Rect get rect => Rect.fromLTRB(x1, y, x2, y + GroupTreeLook.barHeight);
  double get cy => y + GroupTreeLook.barHeight / 2;

  /// 구멍 가운데(둥근 끝 — 왼쪽 9.5 · 위 6.5).
  Offset get hole => sheetHoleAt(rect, SheetTagKind.key);
  bool get hasHole => width >= GroupTreeLook.minHole;

  /// 꼬리 마름모 가운데(오른쪽 7.5 · 위 6.5) — 뒤가 없거나 꼬리표가 좁으면 null.
  Offset? get diamond => tail && width >= GroupTreeLook.minDiamond ? sheetDiamondAt(rect) : null;

  /// 실이 떠나는 자리 — 마름모 가운데(마름모가 없으면 오른쪽 끝의 구멍 높이).
  Offset get lead => diamond ?? Offset(x2, hole.dy);

  /// 실이 드는 자리 — 구멍 테 왼쪽.
  Offset get into => Offset(hole.dx - SheetLook.holeRadius, hole.dy);

  /// 윗테 · 머리 밑선 · 아랫테의 y(반 픽셀).
  double get top => y + .5;
  double get headLine => y + GroupTreeLook.head - .5;
  double get bottom => y + GroupTreeLook.barHeight - .5;
}

/// 실의 한 토막 — 곧은 토막([control]이 없음) 또는 굽음(이차 곡선 · 꺾인 점이 [control]).
@immutable
class GroupThreadPiece {
  const GroupThreadPiece(this.a, this.b, [this.control]);
  final Offset a, b;
  final Offset? control;
  bool get vertical => control == null && a.dx == b.dx;
  bool get horizontal => control == null && a.dy == b.dy;

  @override
  bool operator ==(Object other) => other is GroupThreadPiece && other.a == a && other.b == b && other.control == control;
  @override
  int get hashCode => Object.hash(a, b, control);
}

/// 실 하나 — 꺾인 점 목록. 꺾이는 곳은 [bend]로 굽힌다(목업 `Q` — 꺾인 점이 곡선의 조정점).
@immutable
class GroupThread {
  const GroupThread(this.points, this.style, {this.bend = GroupTreeLook.bend});
  final List<Offset> points;
  final GroupLineStyle style;
  final double bend;

  double get width => style == GroupLineStyle.faint ? GroupTreeLook.faint : GroupTreeLook.thread;
  Color get color => style == GroupLineStyle.faint ? SheetLook.ink25 : SheetLook.ink45;

  /// 곧은 토막과 굽음 — 굽음은 양쪽 토막 길이(사이 토막이면 반)를 넘지 않는다.
  List<GroupThreadPiece> get pieces {
    final out = <GroupThreadPiece>[];
    if (points.length < 2) return out;
    var cur = points.first;
    for (var i = 1; i < points.length; i++) {
      final p = points[i];
      if (i < points.length - 1 && bend > 0) {
        final n = points[i + 1];
        final inLen = (p - cur).distance, outLen = (n - p).distance;
        if (inLen > 0 && outLen > 0) {
          final r = math.min(bend, math.min(inLen * (i > 1 ? .5 : 1), outLen * (i + 1 < points.length - 1 ? .5 : 1)));
          final a = p - (p - cur) / inLen * r, b = p + (n - p) / outLen * r;
          if (a != cur) out.add(GroupThreadPiece(cur, a));
          out.add(GroupThreadPiece(a, b, p));
          cur = b;
          continue;
        }
      }
      if (p != cur) out.add(GroupThreadPiece(cur, p));
      cur = p;
    }
    return out;
  }

  /// 실의 길(점 실의 점을 놓을 때).
  Path get path {
    final p = Path();
    final list = pieces;
    if (list.isEmpty) return p;
    p.moveTo(list.first.a.dx, list.first.a.dy);
    for (final s in list) {
      final c = s.control;
      if (c == null) {
        p.lineTo(s.b.dx, s.b.dy);
      } else {
        p.quadraticBezierTo(c.dx, c.dy, s.b.dx, s.b.dy);
      }
    }
    return p;
  }

  /// 점 실의 점 가운데(실 처음부터 [GroupTreeLook.dotStep]마다 — 목업 `stroke-dasharray: 0.01 3.5`).
  List<Offset> get dots {
    final out = <Offset>[];
    for (final m in path.computeMetrics()) {
      for (var t = 0.0; t <= m.length + 1e-6; t += GroupTreeLook.dotStep) {
        final at = m.getTangentForOffset(math.min(t, m.length));
        if (at != null) out.add(at.position);
      }
    }
    return out;
  }
}

/// 매듭(안에서 갈라짐 — 앞 꼬리표 아랫변 · 합쳐짐 — 실들이 모이는 자리).
@immutable
class GroupKnot {
  const GroupKnot(this.at, {this.faint = false});
  final Offset at;
  final bool faint;
}

/// 열쇠표('방식 미상') 하나 — 단체 차례 · 바깥 상자 · 45° 실(꼬리표 윗변 → 열쇠표 구멍).
@immutable
class GroupKeyGeo {
  const GroupKeyGeo(this.node, this.box, this.from, this.hole);
  final int node;
  final Rect box;
  final Offset from, hole;
}

@immutable
class GroupEdgeHit {
  const GroupEdgeHit(this.edge, this.points);
  final GroupTreeEdge edge;
  final List<Offset> points;

  /// 굵기 10px의 투명한 선(웹 `.gt-hit` stroke-width 10)에 들었는가.
  bool contains(Offset p) {
    for (int i = 0; i + 1 < points.length; i++) {
      if (_distance(p, points[i], points[i + 1]) <= 5) return true;
    }
    return false;
  }

  static double _distance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len = ab.distanceSquared;
    final t = len == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

/// 한 번 그릴 것: 꼬리표 자리 · 실 · 매듭 · 열쇠표 · 누르는 자리.
class GroupTreeGeometry {
  GroupTreeGeometry._(this.bars, this.threads, this.knots, this.keys, this.hits, this.rowTops, this.height);

  /// 노드 차례 그대로(보이지 않는 줄도 자리는 셈한다 — 누르기 · 검사가 쓴다).
  final List<GroupBarGeo> bars;
  final List<GroupThread> threads;
  final List<GroupKnot> knots;
  final List<GroupKeyGeo> keys;
  final List<GroupEdgeHit> hits;

  /// 줄마다 꼬리표 윗변의 y(열쇠표 자리를 넣어) · 나무 전체의 키.
  final List<double> rowTops;
  final double height;

  /// 같은 줄로 잇는 이음(이름 바꿈을 이어 씀 — 줄이 같으면 모두).
  static bool sameRow(GroupTreeData d, GroupTreeEdge e) => e.same || d.nodes[e.from].row == d.nodes[e.to].row;

  /// 열쇠표('방식 미상')를 다는 단체 — 들어오는 실이 방식 미상(같은 줄 이음 빼고 — 목업 `keyed`).
  static List<bool> keyedOf(GroupTreeData d) {
    final out = List<bool>.filled(d.nodes.length, false);
    for (final e in d.edges) {
      if (e.kind == 'unknown' && !sameRow(d, e)) out[e.to] = true;
    }
    return out;
  }

  /// 줄마다 꼬리표 윗변의 y — 앞 줄들의 키 + 사이 + 열쇠표 자리(목업 `rowTop`).
  static List<double> rowTopsOf(GroupTreeData d) {
    final count = math.max(1, math.max(d.rows, d.nodes.isEmpty ? 1 : d.nodes.map((g) => g.row).reduce(math.max) + 1));
    final keyRow = List<bool>.filled(count, false);
    final keyed = keyedOf(d);
    for (var i = 0; i < d.nodes.length; i++) {
      if (keyed[i]) keyRow[d.nodes[i].row.clamp(0, count - 1)] = true;
    }
    final tops = <double>[];
    var y = GroupTreeLook.top;
    for (var r = 0; r < count; r++) {
      if (keyRow[r]) y += GroupTreeLook.keyRoom;
      tops.add(y);
      y += GroupTreeLook.pitch;
    }
    return tops;
  }

  /// 나무의 키 — 끝 줄의 꼬리표 아래 + 여백.
  static double heightOf(List<double> tops) => tops.last + GroupTreeLook.barHeight + GroupTreeLook.bottom;

  /// [x]는 분 → 그림 영역 안의 x(px), [width]는 그림 영역의 폭, [rows]는 그릴 줄의 범위(위아래 여유 포함 — 없으면 모두),
  /// [keyWidth]는 열쇠표 글 '방식 미상'의 폭, [viewLeft]는 보이는 왼쪽(그림 영역 기준 — 상자 안쪽이 그림 영역보다 조금 왼쪽에서 시작).
  factory GroupTreeGeometry.of(GroupTreeData d, double Function(double minute) x, {required double width, ({int lo, int hi})? rows, double keyWidth = 40, double viewLeft = 0}) {
    final tops = rowTopsOf(d);
    double topOf(int row) => tops[row.clamp(0, tops.length - 1)];
    final n = d.nodes.length;
    final ins = List.generate(n, (_) => <GroupTreeEdge>[]), outs = List.generate(n, (_) => <GroupTreeEdge>[]);
    for (final e in d.edges) {
      outs[e.from].add(e);
      ins[e.to].add(e);
    }
    bool same(GroupTreeEdge e) => sameRow(d, e);
    /* 꼬리표 자리 — 승계가 드나드는 끝은 6씩 들임(맞닿은 두 꼬리표 사이 12) · 이름 바꿈으로 같은 줄에 이어 쓰면 4 */
    final bars = <GroupBarGeo>[];
    for (int i = 0; i < n; i++) {
      final g = d.nodes[i];
      var xa = x(g.lo), xb = x(g.hi);
      if (ins[i].any(same)) {
        xa += GroupTreeLook.renameIndent;
      } else if (ins[i].isNotEmpty) {
        xa += GroupTreeLook.indent;
      }
      if (outs[i].any(same)) {
        xb -= GroupTreeLook.renameIndent;
      } else if (outs[i].any((e) => e.after)) {
        xb -= GroupTreeLook.indent;
      }
      final x1 = xa.roundToDouble();
      bars.add(GroupBarGeo(x1, math.max(x1 + GroupTreeLook.minWidth, xb.roundToDouble()), topOf(g.row).roundToDouble(), g.row, tail: outs[i].any((e) => same(e) || e.after)));
    }
    bool rowsIn(int ra, int rb) => rows == null || (math.max(ra, rb) >= rows.lo && math.min(ra, rb) <= rows.hi);
    bool xsIn(double xa, double xb) => math.max(xa, xb) >= viewLeft - 40 && math.min(xa, xb) <= width + 40;
    GroupLineStyle style(String kind) => kind == 'blank' ? GroupLineStyle.faint : kind == 'unknown' ? GroupLineStyle.dotted : GroupLineStyle.solid;
    final threads = <GroupThread>[], knots = <GroupKnot>[], keys = <GroupKeyGeo>[], hits = <GroupEdgeHit>[];
    final joins = <int, Set<double>>{};
    for (final e in d.edges) {
      final a = bars[e.from], b = bars[e.to];
      if (!rowsIn(a.row, b.row)) continue;
      final s = style(e.kind), into = b.into, merge = e.kind == 'merge';
      if (same(e)) {
        // 같은 줄(이름 바꿈) — 앞 꼬리표의 마름모에서 뒤 꼬리표 구멍까지 짧은 실
        final pts = [a.lead, into];
        if (!xsIn(a.lead.dx, into.dx)) continue;
        threads.add(GroupThread(pts, s));
        hits.add(GroupEdgeHit(e, pts));
        continue;
      }
      if (!e.after) {
        // 안에서 갈라짐 — 앞 꼬리표 아랫변(아이가 위 줄이면 윗변)의 매듭에서 아이 왼쪽 6으로 곧게 → 굽음 → 구멍
        final vx = b.x1 - GroupTreeLook.indent + .5, y0 = b.y >= a.y ? a.bottom : a.top;
        if (!xsIn(vx, into.dx)) continue;
        final pts = merge ? [Offset(vx, y0), Offset(vx, into.dy)] : [Offset(vx, y0), Offset(vx, into.dy), into];
        threads.add(GroupThread(pts, s));
        knots.add(GroupKnot(Offset(vx, y0), faint: s == GroupLineStyle.faint));
        if (merge) joins.putIfAbsent(e.to, () => <double>{}).add(vx);
        hits.add(GroupEdgeHit(e, merge ? [...pts, into] : pts));
        continue;
      }
      // 끝에서 갈라짐 · 합쳐짐 — 꼬리 마름모 → 앞 꼬리표 끝 6 밖의 통로 → 굽음 → 세로 실 → 굽음 → 구멍(합쳐짐은 매듭에서 모여 구멍으로)
      final xv = math.min(((a.x2 + b.x1) / 2).roundToDouble(), a.x2 + GroupTreeLook.lane) + .5;
      final lead = a.lead;
      if (!xsIn(lead.dx, into.dx)) continue;
      final pts = merge ? [lead, Offset(xv, lead.dy), Offset(xv, into.dy)] : [lead, Offset(xv, lead.dy), Offset(xv, into.dy), into];
      threads.add(GroupThread(pts, s));
      if (merge) joins.putIfAbsent(e.to, () => <double>{}).add(xv);
      hits.add(GroupEdgeHit(e, merge ? [...pts, into] : pts));
    }
    // 합쳐짐 — 모인 자리(뒤 꼬리표의 구멍 줄)마다 매듭 · 가장 왼쪽 매듭에서 구멍까지 실 하나
    for (final j in joins.entries) {
      final into = bars[j.key].into;
      final xs = j.value.toList()..sort();
      threads.add(GroupThread([Offset(xs.first, into.dy), into], GroupLineStyle.solid));
      for (final at in xs) {
        knots.add(GroupKnot(Offset(at, into.dy)));
      }
    }
    // 열쇠표 — 방식 미상으로 든 단체 위(꼬리표 왼쪽 19 · 윗변 1 위)
    final keyed = keyedOf(d);
    for (var i = 0; i < n; i++) {
      if (!keyed[i]) continue;
      final b = bars[i];
      if (rows != null && (b.row < rows.lo || b.row > rows.hi)) continue;
      final box = Rect.fromLTWH(b.x1 + GroupTreeLook.keyLeft, b.y - GroupTreeLook.keyAbove, (keyWidth + SheetLook.keyLead + SheetLook.keyTail).roundToDouble() + 1, SheetLook.keyTag + 1);
      if (!xsIn(box.left, box.right)) continue;
      keys.add(GroupKeyGeo(i, box, Offset(b.x1 + GroupTreeLook.keyFrom, b.top), box.topLeft + SheetKeyLabel.shape.holeAt!));
    }
    return GroupTreeGeometry._(bars, threads, knots, keys, hits, tops, heightOf(tops));
  }

  /// 그 자리의 꼬리표(노드 차례) — 없으면 -1.
  int barAt(Offset p) {
    for (int i = bars.length - 1; i >= 0; i--) {
      if (bars[i].rect.contains(p)) return i;
    }
    return -1;
  }

  /// 그 자리의 실(누를 수 있는 것 — 사건이 있는 것만). 없으면 null.
  GroupTreeEdge? edgeAt(Offset p) {
    for (final h in hits.reversed) {
      if (h.edge.ev.isNotEmpty && h.contains(p)) return h.edge;
    }
    return null;
  }
}

/// 꼬리표 글의 자리 — 이름(구멍 뒤 7부터 · 마름모 앞 6 · 마름모가 없으면 오른쪽 끝 6 안에 들 때만 — 안 들면 첫 글자 · 그것도 안 들면 없음) ·
/// 해(흰 층 · 이름과 같은 왼쪽 · 오른쪽 끝 4 안에 들 때만). 보이는 왼쪽 [viewLeft]보다 왼쪽에서 시작한 꼬리표는 글을 보이는 왼쪽 8로 옮긴다.
/// 글 상자는 글 크기만큼(줄 높이 1) — 이름은 머리 가운데, 해는 흰 층 가운데.
({String name, Rect? nameRect, String years, Rect? yearsRect}) groupTagLabel(GroupTreeNode g, GroupBarGeo b, double Function(String text, TextStyle style) widthOf, {double viewLeft = double.negativeInfinity}) {
  final left = math.max(b.hole.dx + GroupTreeLook.afterHole, viewLeft + GroupTreeLook.stickyLeft);
  final right = b.diamond != null ? b.diamond!.dx - GroupTreeLook.beforeDiamond : b.x2 - .5 - GroupTreeLook.nameRight;
  final style = GroupTreeLook.nameStyle(g.color);
  var name = '';
  if (g.name.isNotEmpty && widthOf(g.name, style) <= right - left) {
    name = g.name;
  } else {
    final first = g.name.characters.isEmpty ? '' : g.name.characters.first;
    if (first.isNotEmpty && widthOf(first, style) <= right - left) name = first;
  }
  final ny = b.y + GroupTreeLook.head / 2;
  final years = groupYears(g);
  final wy = years.isEmpty ? 0.0 : widthOf(years, GroupTreeLook.yearStyle(g.color));
  final showYears = years.isNotEmpty && wy <= b.x2 - .5 - GroupTreeLook.yearsRight - left;
  final fy = b.headLine + GroupTreeLook.floor / 2;
  return (
    name: name,
    nameRect: name.isEmpty ? null : Rect.fromLTWH(left, ny - GroupTreeLook.nameText / 2, widthOf(name, style), GroupTreeLook.nameText),
    years: showYears ? years : '',
    yearsRect: showYears ? Rect.fromLTWH(left, fy - GroupTreeLook.yearText / 2, wy, GroupTreeLook.yearText) : null,
  );
}

/// 글 폭 — 같은 글 · 같은 꼴은 한 번만 잰다(연표를 끄는 동안 매 장면 다시 재지 않게).
class _TextWidths {
  final _memo = <String, double>{};
  final _painters = <String, TextPainter>{};

  double width(String text, TextStyle style) => _memo['${style.hashCode}|$text'] ??= painter(text, style).width;

  TextPainter painter(String text, TextStyle style) {
    final key = '${style.hashCode}|$text';
    final hit = _painters[key];
    if (hit != null) return hit;
    if (_painters.length > 4000) {
      for (final p in _painters.values) {
        p.dispose();
      }
      _painters.clear();
    }
    return _painters[key] = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
  }

  void dispose() {
    for (final p in _painters.values) {
      p.dispose();
    }
    _painters.clear();
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  4. 그리기
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 실 꼴의 칠 차례 — 옅은 실 → 점 실 → 이은 실(겹치면 짙은 실이 위).
int _styleRank(GroupLineStyle s) => switch (s) {
  GroupLineStyle.faint => 0,
  GroupLineStyle.dotted => 1,
  GroupLineStyle.solid => 2,
};

/// 실 · 꼬리표를 칠하는 차례(목업 `back` · `mid` · `front`): 통로의 세로 실(꼬리표 뒤) → 꼬리표 → 고른 테 → 나머지 실(가로 · 굽음 · 점) →
/// 매듭 → 꼬리 마름모 → 열쇠표. 같은 자리를 지나는 곧은 실은 한 토막으로 모아 한 번만 칠한다(겹쳐 칠하면 가장자리가 짙어짐).
class _ThreadRuns {
  _ThreadRuns(Iterable<GroupThread> threads) {
    final vertical = <(GroupLineStyle, double), List<(double, double)>>{};
    final horizontal = <(GroupLineStyle, double), List<(double, double)>>{};
    final seen = <(GroupLineStyle, GroupThreadPiece)>{};
    for (final t in threads) {
      final pieces = t.pieces;
      for (final p in pieces) {
        if (p.vertical) {
          vertical.putIfAbsent((t.style, p.a.dx), () => []).add((math.min(p.a.dy, p.b.dy), math.max(p.a.dy, p.b.dy)));
        } else if (p.horizontal) {
          horizontal.putIfAbsent((t.style, p.a.dy), () => []).add((math.min(p.a.dx, p.b.dx), math.max(p.a.dx, p.b.dx)));
        } else if (seen.add((t.style, p))) {
          others.add((t.style, p));
        }
      }
      if (t.style == GroupLineStyle.dotted) {
        for (final d in t.dots) {
          final onVertical = pieces.any((p) => p.vertical && (d.dx - p.a.dx).abs() < .01 && d.dy >= math.min(p.a.dy, p.b.dy) - .01 && d.dy <= math.max(p.a.dy, p.b.dy) + .01);
          (onVertical ? backDots : frontDots).add(d);
        }
      }
    }
    List<(GroupLineStyle, Rect)> runs(Map<(GroupLineStyle, double), List<(double, double)>> m, bool vert) {
      final out = <(GroupLineStyle, Rect)>[];
      for (final entry in m.entries) {
        final (style, at) = entry.key;
        if (style == GroupLineStyle.dotted) continue;
        final h = (style == GroupLineStyle.faint ? GroupTreeLook.faint : GroupTreeLook.thread) / 2;
        final spans = entry.value..sort((a, b) => a.$1.compareTo(b.$1));
        var (lo, hi) = spans.first;
        void put() => out.add((style, vert ? Rect.fromLTRB(at - h, lo, at + h, hi) : Rect.fromLTRB(lo, at - h, hi, at + h)));
        for (final s in spans.skip(1)) {
          if (s.$1 <= hi + .01) {
            hi = math.max(hi, s.$2);
          } else {
            put();
            (lo, hi) = s;
          }
        }
        put();
      }
      return out..sort((a, b) => _styleRank(a.$1).compareTo(_styleRank(b.$1)));
    }

    back = runs(vertical, true);
    front = runs(horizontal, false);
    others.sort((a, b) => _styleRank(a.$1).compareTo(_styleRank(b.$1)));
  }

  /// 통로의 세로 실(꼬리표 뒤) · 가로 실(꼬리표 위) — 네모 칠.
  late final List<(GroupLineStyle, Rect)> back, front;

  /// 굽음 · 비스듬한 토막(꼬리표 위) — 선.
  final others = <(GroupLineStyle, GroupThreadPiece)>[];

  /// 점 실의 점 — 세로 통로의 것은 꼬리표 뒤, 나머지는 위.
  final backDots = <Offset>[], frontDots = <Offset>[];

  static Color colorOf(GroupLineStyle s) => s == GroupLineStyle.faint ? SheetLook.ink25 : SheetLook.ink45;
  static double widthOf(GroupLineStyle s) => s == GroupLineStyle.faint ? GroupTreeLook.faint : GroupTreeLook.thread;

  static void paintRects(Canvas canvas, List<(GroupLineStyle, Rect)> list) {
    for (final (style, r) in list) {
      if (r.width > 0 && r.height > 0) canvas.drawRect(r, Paint()..color = colorOf(style));
    }
  }

  static void paintDots(Canvas canvas, List<Offset> dots) {
    final paint = Paint()..color = SheetLook.ink45;
    for (final d in dots) {
      canvas.drawCircle(d, GroupTreeLook.dot / 2, paint);
    }
  }

  void paintOthers(Canvas canvas) {
    for (final (style, p) in others) {
      if (style == GroupLineStyle.dotted) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = widthOf(style)
        ..color = colorOf(style);
      final c = p.control;
      if (c == null) {
        canvas.drawLine(p.a, p.b, paint);
      } else {
        canvas.drawPath(
          Path()
            ..moveTo(p.a.dx, p.a.dy)
            ..quadraticBezierTo(c.dx, c.dy, p.b.dx, p.b.dy),
          paint,
        );
      }
    }
  }
}

class _GroupTreePainter extends CustomPainter {
  _GroupTreePainter({
    required this.data,
    required this.geo,
    required this.x,
    required this.selected,
    required this.hovered,
    required this.widths,
    required this.rows,
    required this.viewLeft,
    required this.viewRight,
  });
  final GroupTreeData data;
  final GroupTreeGeometry geo;

  /// 분 → 그림 영역 안 x.
  final double Function(double minute) x;
  final int selected, hovered;
  final _TextWidths widths;
  final ({int lo, int hi}) rows;

  /// 보이는 가로 범위(그림 영역 기준 — 상자 안쪽).
  final double viewLeft, viewRight;

  bool _shown(GroupBarGeo b) => b.row >= rows.lo && b.row <= rows.hi && b.x2 >= viewLeft - 40 && b.x1 <= viewRight + 40;

  @override
  void paint(Canvas canvas, Size size) {
    final runs = _ThreadRuns(geo.threads);
    /* 1. 통로의 세로 실(꼬리표 뒤) */
    _ThreadRuns.paintRects(canvas, runs.back);
    _ThreadRuns.paintDots(canvas, runs.backDots);
    /* 2. 꼬리표 */
    for (int i = 0; i < data.nodes.length; i++) {
      final b = geo.bars[i];
      if (_shown(b)) _tag(canvas, data.nodes[i], b, here: i == selected, hover: i == hovered);
    }
    /* 3. 고른 테(먹 100 · 1.5 — 2 밖 · 둥근 끝 14) */
    if (selected >= 0 && selected < geo.bars.length && _shown(geo.bars[selected])) {
      canvas.drawPath(SheetPickRing.outsideRing(geo.bars[selected].rect, SheetTagKind.key), Paint()..color = SheetLook.pickInk);
    }
    /* 4. 나머지 실(꼬리표 위) */
    _ThreadRuns.paintRects(canvas, runs.front);
    runs.paintOthers(canvas);
    _ThreadRuns.paintDots(canvas, runs.frontDots);
    /* 5. 매듭 */
    for (final k in geo.knots) {
      canvas.drawCircle(k.at, GroupTreeLook.knot, Paint()..color = k.faint ? SheetLook.ink25 : SheetLook.ink45);
    }
    /* 6. 꼬리 마름모(실이 떠나는 자리 위에) */
    for (int i = 0; i < data.nodes.length; i++) {
      final b = geo.bars[i], d = b.diamond;
      if (d != null && _shown(b)) canvas.drawPath(sheetDiamondPath(d), Paint()..color = SheetLook.diamondInk(data.nodes[i].color));
    }
    /* 7. 열쇠표 — 45° 실(먹 45 · 1) 위에 흰 종이 열쇠표 */
    for (final k in geo.keys) {
      canvas.drawLine(
        k.from,
        k.hole,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = SheetLook.ink45,
      );
      canvas.save();
      canvas.translate(k.box.left, k.box.top);
      SheetKeyLabel.shape.paint(canvas, k.box.size);
      canvas.restore();
      _text(canvas, GroupTreeLook.howWords['unknown']!, GroupTreeLook.keyStyle, k.box.left + SheetLook.keyLead, k.box.center.dy);
    }
  }

  void _text(Canvas canvas, String text, TextStyle style, double left, double cy) {
    final tp = widths.painter(text, style);
    tp.paint(canvas, Offset(left, cy - tp.height / 2));
  }

  /// 단체 꼬리표 하나 — 그림판 꼬리표 그대로(둥근 끝 12 · 칠 제 색 24% · 머리 밑선과 테 84% + 먹 · 흰 층 · 집권 칸 · 구멍 · 이름 · 해).
  void _tag(Canvas canvas, GroupTreeNode g, GroupBarGeo b, {required bool here, required bool hover}) {
    final box = b.rect, c = g.color;
    final fill = SheetLook.tagFill(c), edge = SheetLook.tagEdge(c);
    canvas.drawPath(sheetTagPath(box, SheetTagKind.key, round: GroupTreeLook.round), Paint()..color = hover ? SheetTagButton.lift(fill) : fill);
    // 흰 층 — 머리 밑선(반 픽셀)부터 아랫테까지 · 왼쪽 아래 귀는 꼬리표와 같은 둥근 끝.
    final x0 = box.left + .5, x1 = box.right - .5, ys = b.headLine, yb = b.bottom;
    final r = math.max(0.0, math.min(GroupTreeLook.round, math.min((yb - b.top) / 2, x1 - x0)));
    final floor = Path()
      ..moveTo(x1, ys)
      ..lineTo(x0, ys)
      ..lineTo(x0, math.max(ys, yb - r))
      ..arcToPoint(Offset(x0 + r, yb), radius: Radius.circular(r), clockwise: false)
      ..lineTo(x1, yb)
      ..close();
    canvas.drawPath(floor, Paint()..color = hover ? SheetLook.ink4 : SheetLook.paper);
    final label = groupTagLabel(g, b, widths.width, viewLeft: viewLeft);
    final yr = label.yearsRect;
    bool clear(double at) => yr == null || at < yr.left - GroupTreeLook.cellClear || at > yr.right + GroupTreeLook.cellClear;
    if (g.segs.isNotEmpty) {
      // 집권 칸 — 흰 층 꼴로 잘라 둥근 귀를 지킴 · 칸 금 먹 25(꼬리표 끝 3 안 · 해 글 자리에는 긋지 않음)
      canvas.save();
      canvas.clipPath(floor);
      final line = Paint()..color = SheetLook.ink25;
      for (final s in g.segs) {
        final l = math.max(x(s.a), x0).roundToDouble(), rr = math.min(x(s.b), x1).roundToDouble();
        if (rr - l < 2) continue;
        canvas.drawRect(Rect.fromLTRB(l, ys + .5, rr, yb - .5), Paint()..color = GroupTreeLook.segFill(c, s.kind));
        if (l > x0 + GroupTreeLook.cellClear && clear(l + .5)) canvas.drawRect(Rect.fromLTRB(l, ys + .5, l + 1, yb - .5), line);
        if (rr < x1 - GroupTreeLook.cellClear && clear(rr - .5)) canvas.drawRect(Rect.fromLTRB(rr - 1, ys + .5, rr, yb - .5), line);
      }
      canvas.restore();
    }
    // 머리 밑선 · 테(테는 획이 아니라 고리 칠 — [sheetTagRing]의 까닭)
    canvas.drawRect(Rect.fromLTRB(box.left + 1, ys - .5, box.right - 1, ys + .5), Paint()..color = edge);
    canvas.drawPath(sheetTagRing(box, SheetTagKind.key, round: GroupTreeLook.round), Paint()..color = edge);
    if (b.hasHole) {
      canvas.drawCircle(b.hole, SheetLook.holeRadius, Paint()..color = SheetLook.paper);
      canvas.drawCircle(
        b.hole,
        SheetLook.holeRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = here ? SheetLook.pickInk : SheetLook.ink45,
      );
    }
    final nr = label.nameRect;
    if (nr != null) _text(canvas, label.name, GroupTreeLook.nameStyle(c), nr.left, nr.center.dy);
    if (yr != null) _text(canvas, label.years, GroupTreeLook.yearStyle(c), yr.left, yr.center.dy);
  }

  @override
  bool shouldRepaint(_GroupTreePainter old) =>
      old.geo != geo || old.selected != selected || old.hovered != hovered || old.rows != rows || old.data != data || old.viewLeft != viewLeft || old.viewRight != viewRight;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) => [
    for (int i = 0; i < data.nodes.length; i++)
      if (geo.bars[i].row >= rows.lo && geo.bars[i].row <= rows.hi && geo.bars[i].x2 > 0 && geo.bars[i].x1 < size.width)
        CustomPainterSemantics(
          rect: geo.bars[i].rect.intersect(Offset.zero & size),
          properties: SemanticsProperties(label: data.nodes[i].tip, button: true, selected: i == selected, textDirection: TextDirection.ltr),
        ),
  ];

  @override
  bool shouldRebuildSemantics(_GroupTreePainter old) => shouldRepaint(old);
}

/// 상자 '단체' 몸의 점선 금(2 긋고 3 띄움 · 큰 금 먹 12 · 작은 금 먹 4) — 나무 뒤 · 세로로 밀어도 그대로.
class _GridPainter extends CustomPainter {
  const _GridPainter(this.ticks);

  /// (몸 안 x, 큰 금인가).
  final List<(double, bool)> ticks;

  @override
  void paint(Canvas canvas, Size size) {
    final major = Paint()..color = SheetLook.ink12, minor = Paint()..color = SheetLook.ink4;
    for (final (at, big) in ticks) {
      final x = at.roundToDouble();
      if (x < 3 || x > size.width - 3) continue;
      for (var y = 0.0; y < size.height; y += GroupTreeLook.tickDash + GroupTreeLook.tickGap) {
        canvas.drawRect(Rect.fromLTRB(x, y, x + 1, math.min(size.height, y + GroupTreeLook.tickDash)), big ? major : minor);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => !listEquals(old.ticks, ticks);
}

/// 상자 '단체' 몸의 자름 — 아래 두 귀는 상자 모따기를 따른다(꼬리표 · 실이 상자 테 밖으로 나가지 않게).
class _BodyClip extends CustomClipper<Path> {
  const _BodyClip();

  @override
  Path getClip(Size size) {
    const c = SheetLook.boxChamfer - 1;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(c, size.height)
      ..lineTo(0, size.height - c)
      ..close();
  }

  @override
  bool shouldReclip(_BodyClip oldClipper) => false;
}


// ────────────────────────────────────────────────────────────────────────────────────────────
//  5. 창
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 단체 계보 창의 층 — 연표 위 Stack에 `Positioned.fill`로 둔다. 닫혀 있으면 자리를 차지하지 않는다.
class GroupTreeLayer extends StatefulWidget {
  const GroupTreeLayer({super.key, required this.bus});
  final AppBus bus;

  static final _mounted = <AppBus>{};

  /// 이 길에 계보 창 층이 붙어 있는가(단추가 설지).
  static bool mountedOn(AppBus bus) => _mounted.contains(bus);

  /// 어느 길에든 계보 창 층이 붙어 있는가 — 길을 모르는 자리(나라 상세의 '단체' 상자 머리)에서 단추를 세울지 미리 본다
  /// (붙지 않은 앱에서는 빈 단추 자리도 두지 않아 상자의 생김새가 1px도 바뀌지 않게).
  static bool get anyMounted => _mounted.isNotEmpty;

  @override
  State<GroupTreeLayer> createState() => GroupTreeLayerState();
}

class GroupTreeLayerState extends State<GroupTreeLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  final _scroll = ScrollController();
  final _widths = _TextWidths();

  GroupTreeData? _data;
  int _selected = -1, _hovered = -1;
  int _turn = 0;

  /// 이 창이 켠 조명(같은 것일 때만 걷는다 — 다른 창이 켠 조명은 건드리지 않음).
  Object? _lit;

  /// 같은 키 누름에서 다른 쪽이 이미 무언가를 닫았는가(Esc 차례) — 다음 마이크로태스크에 풀린다.
  bool _handledNow = false;

  AppBus get _bus => widget.bus;

  /// 열려 있는 나무(닫혀 있으면 null) · 고른 단체의 차례(없으면 -1) — 검사와 앱 틀이 본다.
  GroupTreeData? get data => _data;
  int get selected => _selected;
  bool get isOpen => _data != null;

  @override
  void initState() {
    super.initState();
    GroupTreeLayer._mounted.add(_bus);
    _listen(_bus);
    HardwareKeyboard.instance.addHandler(_escape);
    _onSlot();
  }

  @override
  void didUpdateWidget(GroupTreeLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bus != widget.bus) {
      GroupTreeLayer._mounted.remove(oldWidget.bus);
      _unlisten(oldWidget.bus);
      GroupTreeLayer._mounted.add(_bus);
      _listen(_bus);
      _onSlot();
    }
  }

  @override
  void dispose() {
    GroupTreeLayer._mounted.remove(_bus);
    _unlisten(_bus);
    HardwareKeyboard.instance.removeHandler(_escape);
    _clearSpots();
    _data = null;
    _applyFocus(frame: false); // 장면이 먼저 닫혔을 수 있다 — 표시만 풀고 장면은 청하지 않는다
    _enter.dispose();
    _scroll.dispose();
    _widths.dispose();
    super.dispose();
  }

  void _listen(AppBus bus) {
    bus.slot(groupTreeSlot).addListener(_onSlot);
    bus.slot(slotCommand).addListener(_onCommand);
    bus.slot(slotZen).addListener(_markHandled);
    bus.slot(_lensSlot).addListener(_markHandled);
    bus.slot('spots').addListener(_onSpots);
    bus.controller.addListener(_onView);
  }

  void _unlisten(AppBus bus) {
    bus.slot(groupTreeSlot).removeListener(_onSlot);
    bus.slot(slotCommand).removeListener(_onCommand);
    bus.slot(slotZen).removeListener(_markHandled);
    bus.slot(_lensSlot).removeListener(_markHandled);
    bus.slot('spots').removeListener(_onSpots);
    bus.controller.removeListener(_onView);
  }

  // ── 여닫기 ────────────────────────────────────────────────────────────────────────────────

  void _onSlot() {
    final v = _bus.slot(groupTreeSlot).value;
    if (v is GroupTreeRequest) {
      _load(v);
    } else if (_data != null) {
      _shut();
    }
  }

  /// 창을 닫는다(✕ · 닫기 · Esc).
  void close() => closeGroupTree(_bus);

  Future<Map<String, dynamic>?> _record(String uid) async {
    try {
      final answer = await _bus.ask({'op': 'entity', 'uid': uid});
      final raw = answer['json'];
      final json = raw is String ? jsonDecode(raw) : raw;
      return json is Map ? json.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load(GroupTreeRequest req) async {
    final turn = ++_turn;
    var holder = req.uid;
    var json = await _record(holder);
    if (json != null && json['x_groupTree'] is! Map) {
      final at = json['x_treeAt'];
      if (at is String && at.isNotEmpty) {
        holder = at;
        json = await _record(holder);
      }
    }
    if (!mounted || turn != _turn) return;
    final data = json == null ? null : GroupTreeData.parse(holder, json['x_groupTree']);
    if (data == null) {
      _bus.slot(slotNotice).value = '단체 계보를 읽지 못했습니다 — 이 저장소에는 계보 나무가 실려 있지 않습니다.';
      if (_bus.slot(groupTreeSlot).value == req) _bus.slot(groupTreeSlot).value = null;
      return;
    }
    final was = _data != null;
    setState(() {
      _data = data;
      _selected = -1;
      _hovered = -1;
    });
    if (!was) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _enter.value = 1;
      } else {
        _enter.forward(from: 0);
      }
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    // 나무가 연표의 보기 범위와 하나도 겹치지 않으면 나무 전체가 들어오게(앞뒤로 6% · 적어도 2년). 나무는 보이지만 고른 단체가 보기 밖이면
    // 그 단체의 기간으로('이 시기로'와 같은 틀 — 고른 단체의 막대와 위 연표의 조명이 보이게 · 조금이라도 보이면 그대로)
    final v = _bus.controller.view;
    bool seen(GroupTreeNode n) => n.hi > v.lo && n.lo < v.hi;
    final pick = req.group == null ? -1 : data.indexOf(req.group!);
    if (!data.nodes.any(seen)) {
      final pad = math.max(2 * _yearMinutes, (data.hi - data.lo) * .06);
      _bus.goTo(data.lo - pad, data.hi + pad);
    } else if (pick >= 0 && !seen(data.nodes[pick])) {
      focusOn(data.nodes[pick]);
    }
    select(pick);
    if (data.polityUid.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(data.polityUid));
  }

  void _shut() {
    _turn++;
    _clearSpots();
    setState(() {
      _data = null;
      _selected = -1;
      _hovered = -1;
    });
    _applyFocus();
    _enter.value = 0;
  }

  // ── 고르기 · 조명 ──────────────────────────────────────────────────────────────────────────

  /// 그 단체를 고른다(-1이면 고르지 않음) — 위 연표의 그 나라 띠에 집권 덩이마다 조명.
  void select(int index) {
    final d = _data;
    if (d == null) return;
    final i = index >= 0 && index < d.nodes.length ? index : -1;
    setState(() => _selected = i);
    _applySpots();
    _applyFocus();
  }

  /// 고른 단체의 칸만 진하게(웹 `timeline.setGroupFocus`) — 위 연표의 집권 단 · 실권 단(붕당 렌즈면 그 단체 칸)에서 그 단체가 든 칸은
  /// 안쪽 진한 테두리, 나머지 단체 칸은 옅게. 고르지 않았거나 창을 닫으면 푼다. 장면의 표시 상태에 적고 한 장면을 청한다.
  void _applyFocus({bool frame = true}) {
    final d = _data;
    final node = d == null || _selected < 0 ? null : d.nodes[_selected];
    final marks = SceneMarks.of(_bus.scene);
    final color = node == null ? 0 : node.color.toARGB32() & 0xffffff;
    if (marks.groupFocus == node?.uid && marks.groupFocusColor == color) return;
    marks
      ..groupFocus = node?.uid
      ..groupFocusColor = color
      ..version += 1;
    if (frame) _bus.scene.requestFrame();
  }

  void _applySpots() {
    final d = _data;
    final spots = d == null || _selected < 0 ? const <Map<String, dynamic>>[] : d.nodes[_selected].spots;
    if (spots.isEmpty) {
      _clearSpots();
      return;
    }
    final mine = List<Map<String, dynamic>>.unmodifiable(spots);
    _lit = mine;
    _bus.slot('spots').value = mine;
  }

  void _clearSpots() {
    final slot = _bus.slot('spots');
    if (_lit != null && identical(slot.value, _lit)) slot.value = null;
    _lit = null;
  }

  /// 다른 창이 조명을 걷었으면 고른 단체의 조명을 되살린다(웹 restoreSpot).
  void _onSpots() {
    if (_data == null || _selected < 0 || _bus.slot('spots').value != null) return;
    scheduleMicrotask(() {
      if (mounted && _data != null && _selected >= 0 && _bus.slot('spots').value == null) _applySpots();
    });
  }

  /// 그 나라 띠를 창 위의 보이는 자리로(세로로만 · 이미 보이면 그대로).
  Future<void> _reveal(String uid) async {
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
    if (!mounted || row == null || _data == null) return;
    final layout = _bus.scene.layout;
    if (row < 0 || row >= layout.rowCount || !layout.isVisible(row)) return;
    final top = layout.rowTop(row);
    if (top < 0) return;
    final height = layout.geo(row).height;
    final v = _bus.controller.view;
    final visible = v.bodyHeight - sheetHeight(v.height) / v.mag;
    if (visible <= 0) return;
    if (top >= v.top && top + height <= v.top + visible) return;
    final want = top + height > v.top + visible ? top + height - visible + 8 : top - 8;
    _bus.controller.scrollTo(math.max(0, want));
  }

  // ── 들을 것 ───────────────────────────────────────────────────────────────────────────────

  /// 연표의 보기가 바뀌었다(밀기 · 당기기 · 돋보기 · 창 크기) — 나무를 같은 x로 다시 그린다. 연표가 배치 도중(LayoutBuilder 안의
  /// controller.resize)에 알리면 그 장면이 끝난 뒤에(배치 도중에 다른 위젯을 다시 짓게 하면 안 되므로).
  void _onView() {
    if (_data == null || !mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks || phase == SchedulerPhase.midFrameMicrotasks) {
      if (_viewQueued) return;
      _viewQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _viewQueued = false;
        if (mounted && _data != null) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  bool _viewQueued = false;

  void _onCommand() {
    final c = _bus.slot(slotCommand).value;
    if (c is AppCommand && (c.name == Cmd.close || c.name == Cmd.searchClose)) _markHandled();
  }

  void _markHandled() {
    _handledNow = true;
    scheduleMicrotask(() => _handledNow = false);
  }

  /// 렌즈(주제 보기) 슬롯의 이름 — 렌즈 부품(ui/theme_lens.dart · shell_keys.dart의 slotThemeLens)과 같은 글. 단축키 부품이 Esc로 렌즈를 끄면
  /// 같은 누름에 이 창까지 닫지 않으려고 듣는다.
  static const _lensSlot = 'themeLens';

  /// Esc — 메뉴 · 대화 상자 · 검색 칸 · 상세 창이 먼저(단축키 부품이 그쪽을 닫는다), 그다음 이 창.
  /// 단축키 부품(이 층보다 먼저 키를 듣는다)이 같은 누름에 렌즈를 끄거나 집중 모드를 풀었으면 이 창은 그대로 — 한 번에 하나만.
  /// (웹 차례는 '이 창 → 렌즈 → 집중 모드' — 단축키 부품의 Esc 갈래에 이 창 한 줄이 들어가면 그 차례가 된다: 보고의 이음 제안)
  bool _escape(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape || _data == null || !mounted) return false;
    if (_handledNow || typingNow() || _bus.selection.value != null) return false;
    if (Navigator.maybeOf(context)?.canPop() ?? false) return false;
    close();
    return true;
  }

  // ── 그리기 ────────────────────────────────────────────────────────────────────────────────

  static const _yearMinutes = 525960.0;

  /// 창의 높이 — `min(525px, 56%)`.
  static double sheetHeight(double layerHeight) => math.min(GroupTreeLook.maxHeight, layerHeight * GroupTreeLook.heightRatio);

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final h = sheetHeight(box.maxHeight);
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: h,
              child: AnimatedBuilder(
                animation: _enter,
                builder: (context, child) {
                  final t = Ui.ease.transform(_enter.value);
                  return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child));
                },
                child: KeyedSubtree(key: groupTreeKey, child: _sheet(d, box.maxWidth)),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 제목 줄의 글 — `나라 · 단체 n · 연도 눈금은 연표와 같은 자리`(나무의 읽기 글).
  String subOf(GroupTreeData d) => [if (d.polityName.isNotEmpty) d.polityName, '단체 ${d.nodes.length}', '연도 눈금은 연표와 같은 자리'].join(' · ');

  /// 창 — 그 나라 색 폴더(몸통의 아래 끝은 창 밖에 감춤). 폴더 위(흰 둘레까지)의 누름 · 바퀴는 아래 연표로 내려가지 않는다.
  Widget _sheet(GroupTreeData d, double width) {
    const rim = SheetLook.folderRim, look = (margin: GroupTreeLook.margin, pad: GroupTreeLook.pad, sink: GroupTreeLook.sink);
    final plot = plotOf();
    // 폴더 안(내용)의 왼쪽 = 화면 8 + 안쪽 12. 오른쪽 상자는 그림 영역 왼쪽 4 밖에서, 왼쪽 상자는 그 앞 12까지.
    const contentLeft = GroupTreeLook.margin + GroupTreeLook.pad;
    final sideW = plot.left - GroupTreeLook.plotInset - GroupTreeLook.boxGap - contentLeft;
    final side = sideW >= GroupTreeLook.sideMin;
    final treeLeft = side ? plot.left - GroupTreeLook.plotInset - contentLeft : 0.0;
    return DefaultTextStyle(
      // 연표 위에 뜨는 창이라 글꼴을 직접 준다(노선도 카드와 같이 — 앱 틀의 테마 글꼴이 이 층까지 내려오지 않는 자리).
      style: DetailUi.body.copyWith(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: look.margin - rim,
                right: look.margin - rim,
                top: 0,
                bottom: -(look.sink + rim),
                child: Padding(
                  padding: const EdgeInsets.all(rim),
                  child: SheetFolder(
                    label: '단체 계보',
                    color: d.polityColor,
                    padding: EdgeInsets.fromLTRB(look.pad, look.pad, look.pad, look.sink + look.pad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: GroupTreeLook.headRow, child: _headRow(d, treeLeft)),
                        const SizedBox(height: GroupTreeLook.headGap),
                        Expanded(
                          child: Stack(
                            children: [
                              if (side) Positioned(left: 0, top: 0, bottom: 0, width: sideW, child: _side(d)),
                              Positioned(left: treeLeft, right: 0, top: 0, bottom: 0, child: _treeBox(d, plot, contentLeft + treeLeft)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 머리 줄 — 나라 꼬리표(누르면 나라 상세) · 범례 흰 종이(오른쪽 상자와 같은 왼쪽에서) · 닫기 종이.
  Widget _headRow(GroupTreeData d, double legendLeft) => CustomMultiChildLayout(
    delegate: _HeadLayout(legendLeft),
    children: [
      if (d.polityUid.isNotEmpty)
        LayoutId(
          id: _HeadPart.nation,
          child: SheetTagButton(
            label: d.polityName,
            color: d.polityColor ?? GroupTreeLook.legendColor,
            text: GroupTreeLook.headText,
            hint: '누르면 나라 상세',
            semantics: '${d.polityName} — 나라 상세',
            onTap: () => _bus.select(d.polityUid),
          ),
        ),
      LayoutId(id: _HeadPart.legend, child: const _GroupLegend()),
      LayoutId(id: _HeadPart.close, child: SheetPaperButton(label: '닫기', onTap: close)),
    ],
  );

  /// 그림 영역의 자리(창 안 px): 왼쪽 = 연표의 이름 칸 폭, 폭 = 연표의 그림 영역 — 둘 다 화면 px(배치 px × 돋보기 배율).
  ({double left, double width}) plotOf() {
    final v = _bus.controller.view;
    return (left: v.left * v.mag, width: math.max(60.0, v.plotWidth * v.mag));
  }

  /// 분 → 그림 영역 안 x(화면 px) — 위 연표와 같은 x.
  double xOf(double minute) {
    final v = _bus.controller.view;
    return (minute - v.lo) * v.ppm * v.mag;
  }

  /// 눈금(그림 영역 기준 x · [left] ~ [right] 안) — 작은 금 · 큰 금의 짝은 큰 금 사이가 60 ~ 600px 안에 들게(300년 보기면 25년 · 50년).
  /// 큰 금에만 해 글. 해 좌표에는 0년이 없다.
  List<({double x, bool major, String label})> ticksIn(double left, double right) {
    final v = _bus.controller.view;
    final k = v.ppm * v.mag;
    if (!(k > 0) || !(right > left)) return const [];
    final s = k * 525949.2; // 한 해의 px
    var pair = GroupTreeLook.tickPairs[3];
    if (pair.$2 * s < GroupTreeLook.labelMin || pair.$2 * s > GroupTreeLook.labelMax) {
      pair = GroupTreeLook.tickPairs.firstWhere((p) => p.$2 * s >= GroupTreeLook.labelMin, orElse: () => GroupTreeLook.tickPairs.last);
    }
    final y0 = yearAt(v.lo + left / k), y1 = yearAt(v.lo + right / k);
    final out = <({double x, bool major, String label})>[];
    var guard = 0;
    for (var y = (y0 / pair.$1).floor() * pair.$1; y <= y1 && guard < 2000; y += pair.$1, guard++) {
      if (y == 0) continue;
      final x = xOf(minuteOfYear(y.toDouble()));
      if (x < left - 1 || x > right + 1) continue;
      final major = y % pair.$2 == 0;
      out.add((x: x, major: major, label: major ? yearLabel(y) : ''));
    }
    return out;
  }

  /// 오른쪽 상자 '단체 {수}' — 뚜껑에 큰 금의 해 글, 몸에 점선 금과 나무(세로로 밂). [boxLeft]는 상자 왼쪽의 창 안 x.
  Widget _treeBox(GroupTreeData d, ({double left, double width}) plot, double boxLeft) => LayoutBuilder(
    builder: (context, box) {
      final boxW = box.maxWidth;
      final count = '${d.nodes.length}';
      // 몸(상자 테 안)의 왼쪽 = 상자 왼쪽 + 1 · 나무(그림 영역)는 몸 안 plotDx에서 시작
      final plotDx = plot.left - (boxLeft + 1);
      final bodyW = math.max(0.0, boxW - 2);
      final ticks = ticksIn(-plotDx, bodyW - plotDx);
      final labelStyle = GroupTreeLook.font(sheetText(SheetLook.boxLabelText, bold: true)), countStyle = GroupTreeLook.font(sheetText(SheetLook.boxLabelText));
      final tickStyle = GroupTreeLook.font(sheetText(GroupTreeLook.tickText, color: SheetLook.ink60));
      final labelEnd = SheetLook.boxInset + (_widths.width('단체', labelStyle) + 2 * SheetLook.boxLabelPad).ceilToDouble() + SheetLook.boxCountGap + _widths.width(count, countStyle);
      return Stack(
        children: [
          Positioned.fill(
            child: SheetBox(label: '단체', count: count, padding: EdgeInsets.zero, fill: true, child: const SizedBox.expand()),
          ),
          for (final t in ticks)
            if (t.label.isNotEmpty)
              if ((1 + plotDx + t.x).roundToDouble() + GroupTreeLook.tickLeft case final lx when lx > labelEnd + GroupTreeLook.tickAfterLabel && lx + _widths.width(t.label, tickStyle) < boxW - GroupTreeLook.tickRight)
                Positioned(
                  left: lx,
                  top: (SheetLook.boxLid - GroupTreeLook.tickText) / 2,
                  height: GroupTreeLook.tickText,
                  child: Text(t.label, maxLines: 1, softWrap: false, style: tickStyle),
                ),
          Positioned(
            left: 1,
            right: 1,
            top: SheetLook.boxLid + 1,
            bottom: 1,
            child: ClipPath(
              clipper: const _BodyClip(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: CustomPaint(painter: _GridPainter([for (final t in ticks) (plotDx + t.x, t.major)]))),
                  Positioned(
                    left: plotDx,
                    top: 0,
                    bottom: 0,
                    width: plot.width,
                    child: Semantics(container: true, label: '단체 계보 · ${subOf(d)}', child: _tree(d, plot.width, -plotDx, bodyW - plotDx)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  /// 줄 위치(열쇠표 자리 넣음) — 나무마다 한 번.
  List<double> _tops(GroupTreeData d) {
    if (!identical(_topsFor, d)) {
      _topsFor = d;
      _topsMemo = GroupTreeGeometry.rowTopsOf(d);
    }
    return _topsMemo;
  }

  GroupTreeData? _topsFor;
  List<double> _topsMemo = const [GroupTreeLook.top];

  /// 보이는 줄의 범위(위아래로 여섯 줄 여유).
  static ({int lo, int hi}) _rowsIn(List<double> tops, double offset, double viewH) {
    var lo = 0;
    while (lo < tops.length && tops[lo] + GroupTreeLook.barHeight < offset) {
      lo++;
    }
    var hi = lo;
    while (hi + 1 < tops.length && tops[hi + 1] <= offset + viewH) {
      hi++;
    }
    return (lo: lo - 6, hi: hi + 6);
  }

  double get _keyWidth => _widths.width(GroupTreeLook.howWords['unknown']!, GroupTreeLook.keyStyle);

  Widget _tree(GroupTreeData d, double width, double viewLeft, double viewRight) => LayoutBuilder(
    builder: (context, box) {
      final viewH = box.maxHeight.isFinite ? box.maxHeight : 400.0;
      final offset = _scroll.hasClients ? _scroll.offset : 0.0;
      final tops = _tops(d);
      final rows = _rowsIn(tops, offset, viewH);
      final geo = GroupTreeGeometry.of(d, xOf, width: width, rows: rows, keyWidth: _keyWidth, viewLeft: viewLeft);
      final painter = _GroupTreePainter(data: d, geo: geo, x: xOf, selected: _selected, hovered: _hovered, widths: _widths, rows: rows, viewLeft: viewLeft, viewRight: viewRight);
      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollUpdateNotification && geo.height > viewH) setState(() {}); // 나무 안 세로 밀기 — 새로 보이는 줄을 그림
          return false;
        },
        child: SingleChildScrollView(
          controller: _scroll,
          // 상자 몸의 자름(_BodyClip)이 가장자리를 맡는다 — 그림 영역 왼쪽의 4px 틈까지 꼬리표가 보이게.
          clipBehavior: Clip.none,
          child: MouseRegion(
            onHover: (e) {
              final i = geo.barAt(e.localPosition);
              final hit = i >= 0 || geo.edgeAt(e.localPosition) != null;
              if (i != _hovered || hit != _pointing) {
                setState(() {
                  _hovered = i;
                  _pointing = hit;
                });
              }
            },
            onExit: (_) {
              if (_hovered != -1 || _pointing) {
                setState(() {
                  _hovered = -1;
                  _pointing = false;
                });
              }
            },
            cursor: _pointing ? SystemMouseCursors.click : MouseCursor.defer,
            // 누름은 손을 뗄 때 곧바로(웹 click — 두 번 누름을 기다리느라 고르기가 늦지 않게) · 6px 넘게 움직였으면 나무 안 세로 밀기로 보고 건너뜀 ·
            // 같은 꼬리표를 300ms 안에 다시 누르면 두 번 누름(웹 dblclick — 단체 창).
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _downAt = e.localPosition,
              onPointerUp: (e) {
                final down = _downAt;
                _downAt = null;
                if (down == null || (e.localPosition - down).distance > 6) return;
                _tap(geo, e.localPosition, e.timeStamp);
              },
              child: CustomPaint(size: Size(width, geo.height), painter: painter),
            ),
          ),
        ),
      );
    },
  );

  bool _pointing = false;
  Offset? _downAt;

  /// 지난 누름(꼬리표 차례 · 때) — 두 번 누름을 가린다.
  int _lastBar = -1;
  Duration? _lastAt;

  /// 누름 — 꼬리표면 그 단체를 고르고, 사건이 있는 실이면 그 사건 창.
  void tapAt(Offset local) {
    final d = _data;
    if (d == null) return;
    final width = plotOf().width;
    final geo = GroupTreeGeometry.of(d, xOf, width: width);
    _tap(geo, local, null);
  }

  void _tap(GroupTreeGeometry geo, Offset p, Duration? at) {
    final d = _data;
    if (d == null) return;
    final i = geo.barAt(p);
    final edge = i < 0 ? geo.edgeAt(p) : null;
    if (edge != null) {
      _lastBar = -1;
      _bus.select(edge.ev);
      return;
    }
    if (i < 0) {
      _lastBar = -1;
      return;
    }
    final again = at != null && _lastAt != null && i == _lastBar && at - _lastAt! <= const Duration(milliseconds: 300);
    _lastBar = again ? -1 : i;
    _lastAt = at;
    if (again) {
      _bus.select(d.nodes[i].uid, kind: 'group');
    } else {
      select(i);
    }
  }

  /// 왼쪽 상자 '고른 단체' — 고른 단체가 없으면 안내 글, 있으면 꼬리표 · 기간 · 단추 · 집권 · 이어짐과 아래 안내 두 줄.
  Widget _side(GroupTreeData d) {
    final g = _selected >= 0 && _selected < d.nodes.length ? d.nodes[_selected] : null;
    final tip = sheetText(SheetLook.boxLabelText, color: SheetLook.ink45);
    return SheetBox(
      label: '고른 단체',
      fill: true,
      padding: const EdgeInsets.fromLTRB(GroupTreeLook.sidePad, GroupTreeLook.sidePad, GroupTreeLook.sidePad, GroupTreeLook.sideBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: g == null ? Text(GroupTreeLook.hint, style: sheetText(SheetLook.boxLabelText, color: SheetLook.ink60).copyWith(height: 1.55)) : _picked(d, g),
            ),
          ),
          if (g != null)
            for (final t in GroupTreeLook.tips) SizedBox(height: GroupTreeLook.tipLine, child: Align(alignment: Alignment.centerLeft, child: _one(t, tip))),
        ],
      ),
    );
  }

  static Widget _one(String text, TextStyle style) => Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style);

  /// 고른 단체의 자세히(다듬기 판 sht-gtree의 왼쪽 상자 차례 그대로).
  Widget _picked(GroupTreeData d, GroupTreeNode g) {
    final c = g.color, i = d.nodes.indexOf(g);
    final links = <(String, int, String)>[
      for (final e in d.edges)
        if (e.to == i) ('앞', e.from, e.kind),
      for (final e in d.edges)
        if (e.from == i) ('뒤', e.to, e.kind),
    ];
    var power = 0, coal = 0, real = 0;
    for (final s in g.segs) {
      switch (s.kind) {
        case GroupSegKind.power:
          power++;
        case GroupSegKind.coal:
          coal++;
        case GroupSegKind.real:
          real++;
      }
    }
    final small = sheetText(SheetLook.boxLabelText, color: SheetLook.ink45), head = sheetText(SheetLook.boxLabelText, bold: true, color: SheetLook.ink60);
    const rule = SizedBox(height: 1, child: ColoredBox(color: SheetLook.ink12));
    Widget line(Widget left, [Widget? right]) => SizedBox(
      height: GroupTreeLook.line,
      child: Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: left)), ?right]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTag(
          shape: SheetTagButton.shapeOf(c, kind: SheetTagKind.key),
          height: GroupTreeLook.pickTag,
          child: Padding(
            padding: const EdgeInsets.only(left: GroupTreeLook.pickLead, right: 8),
            child: Align(alignment: Alignment.centerLeft, child: _one(g.name, sheetText(GroupTreeLook.pickName, bold: true, color: SheetLook.tagInk(c)))),
          ),
        ),
        const SizedBox(height: 15),
        SizedBox(
          height: 12,
          child: Row(
            children: [
              Expanded(child: _one(g.when, sheetText(SheetLook.chipText))),
              const CustomPaint(size: Size(17, 10), painter: _LitMark()),
              const SizedBox(width: 6),
              _one('조명 중', sheetText(SheetLook.boxLabelText, color: SheetLook.ink60)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SheetRun(
          children: [
            SheetPaperButton(label: '단체 창', onTap: () => _bus.select(g.uid, kind: 'group')),
            SheetPaperButton(label: '이 시기로', onTap: () => focusOn(g)),
          ],
        ),
        const SizedBox(height: 15),
        rule,
        const SizedBox(height: 9),
        line(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _one('집권', head),
              const SizedBox(width: 5),
              _one(g.segs.isEmpty ? '없음' : '$power · 연정 $coal${real > 0 ? ' · 실권 $real' : ''}', small),
            ],
          ),
        ),
        for (final s in g.segs)
          line(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(size: const Size(GroupTreeLook.chipW, GroupTreeLook.chipH), painter: _ChipPainter(c, s.kind)),
                const SizedBox(width: GroupTreeLook.chipGap),
                _one('${groupYearOf(s.a)} ~ ${groupYearOf(s.b)}', sheetText(SheetLook.chipText)),
              ],
            ),
            s.kind == GroupSegKind.power ? null : _one(s.kind == GroupSegKind.coal ? '연정' : '실권', small),
          ),
        if (links.isNotEmpty) ...[
          const SizedBox(height: 13),
          rule,
          const SizedBox(height: 10),
          SizedBox(height: 20, child: Align(alignment: Alignment.centerLeft, child: _one('이어짐', head))),
          for (final (side, j, kind) in links)
            Padding(
              padding: const EdgeInsets.only(bottom: GroupTreeLook.linkGap),
              child: SizedBox(
                height: GroupTreeLook.linkTag,
                child: Row(
                  children: [
                    SizedBox(width: GroupTreeLook.linkSide, child: _one(side, sheetText(SheetLook.boxLabelText, color: SheetLook.ink60))),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SheetTagButton(
                          label: d.nodes[j].name,
                          color: d.nodes[j].color,
                          kind: SheetTagKind.key,
                          height: GroupTreeLook.linkTag,
                          text: GroupTreeLook.headText,
                          tail: 9.5,
                          hint: '누르면 이 단체를 고름',
                          onTap: () => select(j),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _one(GroupTreeLook.howWords[kind] ?? kind, small),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// 이 시기로 — 그 단체의 기간 앞뒤로 15%(적어도 2년)를 두고.
  void focusOn(GroupTreeNode g) {
    final pad = math.max(2 * _yearMinutes, (g.hi - g.lo) * .15);
    _bus.goTo(g.lo - pad, g.hi + pad);
  }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  6. 머리 줄 · 범례 · 작은 견본
// ────────────────────────────────────────────────────────────────────────────────────────────

enum _HeadPart { nation, legend, close }

/// 머리 줄 자리 — 나라 꼬리표는 왼쪽(폭의 1/3까지), 닫기는 오른쪽, 범례는 [legendLeft](오른쪽 상자의 왼쪽)부터(나라 꼬리표 뒤 12 이상 ·
/// 닫기 앞 12까지 — 넘치는 칸은 범례가 스스로 뺀다).
class _HeadLayout extends MultiChildLayoutDelegate {
  _HeadLayout(this.legendLeft);
  final double legendLeft;

  @override
  void performLayout(Size size) {
    var nationRight = 0.0;
    if (hasChild(_HeadPart.nation)) {
      final s = layoutChild(_HeadPart.nation, BoxConstraints.loose(Size(size.width / 3, size.height)));
      positionChild(_HeadPart.nation, Offset(0, ((size.height - s.height) / 2).roundToDouble()));
      nationRight = s.width;
    }
    final c = layoutChild(_HeadPart.close, BoxConstraints.loose(size));
    final cx = size.width - c.width;
    positionChild(_HeadPart.close, Offset(cx, ((size.height - c.height) / 2).roundToDouble()));
    final lx = math.max(legendLeft, nationRight == 0 ? 0.0 : nationRight + GroupTreeLook.headSpace);
    final l = layoutChild(_HeadPart.legend, BoxConstraints(maxWidth: math.max(0.0, cx - GroupTreeLook.headSpace - lx), maxHeight: size.height));
    positionChild(_HeadPart.legend, Offset(lx, ((size.height - l.height) / 2).roundToDouble()));
  }

  @override
  bool shouldRelayout(_HeadLayout old) => old.legendLeft != legendLeft;
}

/// 범례 흰 종이 한 줄 — 실 갈래 다섯(갈라짐 · 합쳐짐 · 이름 바꿈 · 방식 미상 · 적지 않음) | 집권 · 연정 · 있던 기간.
/// 자리가 모자라면 뒤에서부터 뺀다(겹침 · 넘침 없이).
class _GroupLegend extends StatelessWidget {
  const _GroupLegend();

  static const items = <(String, String)?>[('split', '갈라짐'), ('merge', '합쳐짐'), ('rename', '이름 바꿈'), ('unknown', '방식 미상'), ('blank', '적지 않음'), null, ('power', '집권'), ('coal', '연정'), ('span', '있던 기간')];

  static double sampleWidth(String kind) => kind == 'span' ? GroupTreeLook.legendSample + 1 : GroupTreeLook.legendSample;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final base = DefaultTextStyle.of(context).style;
      final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
      final style = sheetText(GroupTreeLook.legendText, color: SheetLook.ink60);
      double widthOf(String s) {
        final tp = TextPainter(text: TextSpan(text: s, style: base.merge(style)), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
        final w = tp.width.ceilToDouble();
        tp.dispose();
        return w;
      }

      final kids = <Widget>[];
      var x = 2 * GroupTreeLook.legendPad, lastRule = false;
      for (final it in items) {
        final w = it == null ? 1.0 : sampleWidth(it.$1) + GroupTreeLook.legendGap + widthOf(it.$2);
        final add = (kids.isEmpty ? 0 : GroupTreeLook.legendSpacing) + w;
        if (x + add > box.maxWidth + .01) break;
        if (kids.isNotEmpty) kids.add(const SizedBox(width: GroupTreeLook.legendSpacing));
        kids.add(
          it == null
              ? const SizedBox(width: 1, height: GroupTreeLook.legendRule, child: ColoredBox(color: SheetLook.ink12))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(size: Size(sampleWidth(it.$1), GroupTreeLook.headRow), painter: _LegendGlyph(it.$1)),
                    const SizedBox(width: GroupTreeLook.legendGap),
                    Text(it.$2, maxLines: 1, softWrap: false, style: style),
                  ],
                ),
        );
        lastRule = it == null;
        x += add;
      }
      if (lastRule) kids.removeRange(kids.length - 2, kids.length); // 넘쳐 끝에 남은 가름 금은 뺀다
      if (kids.isEmpty) return const SizedBox.shrink();
      return SheetTag(
        shape: SheetPaperButton.shapeOf(),
        height: GroupTreeLook.headRow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GroupTreeLook.legendPad),
          child: Row(mainAxisSize: MainAxisSize.min, children: kids),
        ),
      );
    },
  );
}

/// 범례 견본(폭 24 · 키 24 · 가운데 12 — 목업 g-sheet-tree `legendGlyph`): 실 다섯 = 마름모 → 그 실 → 구멍(갈라짐은 둘로 · 합쳐짐은 마름모 둘이
/// 매듭에서 모여) · 집권 · 연정 = 흰 층의 칠한 칸 24 × 10 · 있던 기간 = 둥근 끝 꼬리표 25 × 14. 빛깔은 회청([GroupTreeLook.legendColor]).
class _LegendGlyph extends CustomPainter {
  const _LegendGlyph(this.kind);
  final String kind;

  @override
  void paint(Canvas canvas, Size size) {
    const c = GroupTreeLook.legendColor, o = .5, cy = 12.0;
    const w = GroupTreeLook.thread, hw = w / 2;
    final ink = Paint()..color = SheetLook.ink45;
    // 곧은 실 — 네모 칠(양 끝을 반 굵기만큼 늘여 꺾이는 곳을 채움)
    void seg(double ax, double ay, double bx, double by) => canvas.drawRect(Rect.fromLTRB(math.min(ax, bx) - hw, math.min(ay, by) - hw, math.max(ax, bx) + hw, math.max(ay, by) + hw), ink);
    void diamond(double x, double y) => canvas.drawPath(sheetDiamondPath(Offset(x, y)), Paint()..color = SheetLook.diamondInk(c));
    void hole(double x, double y) {
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = SheetLook.paper);
      canvas.drawCircle(
        Offset(x, y),
        2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = SheetLook.ink45,
      );
    }

    switch (kind) {
      case 'split':
        seg(o + 3, cy, o + 8, cy);
        seg(o + 8, cy - 4, o + 8, cy + 4);
        seg(o + 8, cy - 4, o + 19, cy - 4);
        seg(o + 8, cy + 4, o + 19, cy + 4);
        diamond(o + 3, cy);
        hole(o + 21.5, cy - 4);
        hole(o + 21.5, cy + 4);
      case 'merge':
        seg(o + 3, cy - 4, o + 12, cy - 4);
        seg(o + 12, cy - 4, o + 12, cy + 4);
        seg(o + 3, cy + 4, o + 12, cy + 4);
        seg(o + 12, cy, o + 19, cy);
        diamond(o + 3, cy - 4);
        diamond(o + 3, cy + 4);
        canvas.drawCircle(const Offset(o + 12, cy), GroupTreeLook.knot, ink);
        hole(o + 21.5, cy);
      case 'rename' || 'unknown' || 'blank':
        if (kind == 'unknown') {
          for (var x = o + 3; x <= o + 19 + .01; x += GroupTreeLook.dotStep) {
            canvas.drawCircle(Offset(x, cy), GroupTreeLook.dot / 2, ink);
          }
        } else if (kind == 'blank') {
          canvas.drawRect(Rect.fromLTRB(o + 3, cy - GroupTreeLook.faint / 2, o + 19, cy + GroupTreeLook.faint / 2), Paint()..color = SheetLook.ink25);
        } else {
          seg(o + 3, cy, o + 19, cy);
        }
        diamond(o + 3, cy);
        hole(o + 21.5, cy);
      case 'power' || 'coal':
        _ChipPainter.paintChip(canvas, Rect.fromLTWH(0, cy - 5, GroupTreeLook.legendSample, 10), GroupTreeLook.segFill(c, kind == 'coal' ? GroupSegKind.coal : GroupSegKind.power));
      default:
        final box = Rect.fromLTWH(0, cy - 7, size.width, 14);
        canvas.drawPath(sheetTagPath(box, SheetTagKind.key, round: 6.5), Paint()..color = SheetLook.tagFill(c));
        canvas.drawPath(sheetTagRing(box, SheetTagKind.key, round: 6.5), Paint()..color = SheetLook.tagEdge(c));
    }
  }

  @override
  bool shouldRepaint(_LegendGlyph old) => old.kind != kind;
}

/// 집권 칸 견본(흰 층의 칠한 칸 그대로 — 칠 + 테 먹 25).
class _ChipPainter extends CustomPainter {
  const _ChipPainter(this.color, this.kind);
  final Color color;
  final GroupSegKind kind;

  static void paintChip(Canvas canvas, Rect r, Color fill) {
    canvas.drawRect(r, Paint()..color = fill);
    final edge = Paint()..color = SheetLook.ink25;
    canvas.drawRect(Rect.fromLTRB(r.left, r.top, r.right, r.top + 1), edge);
    canvas.drawRect(Rect.fromLTRB(r.left, r.bottom - 1, r.right, r.bottom), edge);
    canvas.drawRect(Rect.fromLTRB(r.left, r.top + 1, r.left + 1, r.bottom - 1), edge);
    canvas.drawRect(Rect.fromLTRB(r.right - 1, r.top + 1, r.right, r.bottom - 1), edge);
  }

  @override
  void paint(Canvas canvas, Size size) => paintChip(canvas, Offset.zero & size, GroupTreeLook.segFill(color, kind));

  @override
  bool shouldRepaint(_ChipPainter old) => old.color != color || old.kind != kind;
}

/// '조명 중' 앞의 작은 표 — 위 연표의 고른 칸 테와 같은 먹 100 · 1.5 둥근 네모 16 × 9(둥근 2).
class _LitMark extends CustomPainter {
  const _LitMark();

  @override
  void paint(Canvas canvas, Size size) {
    const mid = Rect.fromLTWH(.5, .5, 16, 9), h = SheetLook.pickWidth / 2;
    canvas.drawDRRect(
      RRect.fromRectAndRadius(mid.inflate(h), const Radius.circular(2 + h)),
      RRect.fromRectAndRadius(mid.deflate(h), const Radius.circular(2 - h)),
      Paint()..color = SheetLook.pickInk,
    );
  }

  @override
  bool shouldRepaint(_LitMark old) => false;
}

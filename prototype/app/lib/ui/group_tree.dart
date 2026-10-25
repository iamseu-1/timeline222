import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../scene/color_mix.dart';
import '../scene/fonts.dart';
import '../scene/marks.dart';
import '../scene/ruler.dart';
import '../shell/look.dart';
import '../shell/parts.dart';
import 'app_bus.dart';
import 'detail_shell.dart';
import 'shell_keys.dart';

// ════════════════════════════════════════════════════════════════════════════════════════════
//  단체 계보 창 — 설계 D5 결정 4 A '아래쪽 넓은 창 · 가로 시간 나무'(docs/설계-10건/7-8-단체와-렌즈.md 9-1 · 감독-선택.md D5)
//  웹 js/group-tree.js · css/viewer.css의 `.gtree` 절을 옮겼다.
//
//  감독 덧붙임(원문): "집권한 부분에 겉에 아주 얇은 진한 테두리로 살짝 구분." — 막대 안 집권 구간(집권 · 연정 · 실권)에 1px 짙은 테두리.
//  감독 원칙: 띠 · 창의 구분은 글 딱지가 아니라 테두리 · 모양 · 색으로 — 막대 안에는 이름 · 기간 말고 글을 두지 않는다.
//
//  창: 연표 아래쪽에 붙는 넓은 창(연표 폭 그대로 · 위 모서리만 둥근 20px · 높이 min(525px, 56%)).
//      나무의 연도 눈금이 위 연표와 같은 x(연표를 밀거나 당기면 나무도 함께 — 조종부를 듣는다), 왼쪽(연표의 이름 칸 자리)에 고른 단체와 안내 글.
//    · 막대 = 단체 하나(있던 기간 — 단체 색 22% · 그 색의 테두리). 안의 짙은 칠 = 집권(실권도), 중간 칠 = 연정 — 둘 다 1px 짙은 테두리.
//    · 이음선: 갈라짐 = 실선 · 합쳐짐 = 모이는 실선 + 네모 · 이름 바꿈 = 다리(같은 줄로 이어 씀) · 방식 미상 = 2px 점선 + 글 '방식 미상' ·
//      적지 않음 = 옅은 1px 선 · 글 없음.
//    · 막대를 누르면 그 단체를 고름: 위 연표의 그 나라 띠에 집권 덩이마다 조명(bus.slot('spots')) · 왼쪽에 이름 · 기간 · 집권 n번 · 연정 m번과
//      [단체 창] [이 시기로]. 두 번 누르면 단체 창. 이음선을 누르면 그 일의 사건(맺은 사건이 있을 때만).
//    · 그 나라 띠가 창에 가려 있으면 창 위로 데려온다(세로로만 · 이미 보이면 그대로).
//    · 열 때 보기: 나무 전체가 보기 밖이면 나무 전체로, 나무는 보이지만 고른 채로 연 단체가 보기 밖이면 그 단체의 기간으로.
//    · Esc: 상세 창이 열려 있으면 상세 창이 먼저(단축키 부품의 몫), 그다음 이 창.
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
//  2. 생김새 — css/viewer.css의 `.gtree` 절 · js/group-tree.js의 상수
// ────────────────────────────────────────────────────────────────────────────────────────────

abstract final class GroupTreeLook {
  /// 나무 안 첫 줄 위 여백 · 줄 간격 · 막대 높이(웹 TOP · PITCH · BH).
  static const top = 6.0, pitch = 30.0, barHeight = 20.0;

  /// 창의 높이 `min(525px, 56%)` · 위 모서리 둥근 12(시트 · 메뉴 · 창 — HistoryArchive 통일) · 연도 눈금 줄 18.
  static const maxHeight = 525.0, heightRatio = .56, radius = Ui.menuRadius, axisHeight = 18.0;

  /// css `--paper-ink`(먹) · `--surface`(종이) — 막대 색을 섞는 바탕. HistoryArchive 통일(B안) 뒤로 흰 종이 · 검은 잉크다(`Ui.paper` · `Ui.ink`의 값).
  /// 단체 색은 자료라 그대로이고 섞이는 바탕만 바뀐다(전에는 옛 따스한 종이빛 #fcf9f3 · 먹 #1b1a19가 박혀 있어 웹과 색이 어긋났다).
  static const ink = 0xff000000, surface = 0xffffffff;

  /// 이음선(`--text-2` 78%) · 적지 않음(`--text-3` 55%).
  static final line = Color(withAlpha(Ui.text2.toARGB32(), .78)), faint = Color(withAlpha(Ui.text3.toARGB32(), .55));

  /// 막대 바탕(그 색 22%) · 테두리(oklab 84% — 고른 막대는 70% · 2px) · 집권 칠(62%) · 연정 칠(40%) · 집권 테두리(oklab 52% — 감독 덧붙임의 '얇은 진한 테두리') · 이름 글(먹 75%).
  static Color base(Color c) => Color(mixSrgb(c.toARGB32(), surface, .22));
  static Color baseEdge(Color c, {bool here = false}) => Color(mixOklab(c.toARGB32(), ink, here ? .70 : .84));
  static Color segFill(Color c, GroupSegKind k) => Color(mixSrgb(c.toARGB32(), surface, k == GroupSegKind.coal ? .40 : .62));
  static Color segEdge(Color c) => Color(mixOklab(c.toARGB32(), ink, .52));
  static Color nameInk(Color c) => Color(mixSrgb(c.toARGB32(), ink, .25));

  /// 막대 이름(12px · 650) · 기간(10.5px · 500 · `--text-3`) · '방식 미상'(11px · 600 · `--text-2`) · 연도 눈금(10.5px · `--text-3`).
  static TextStyle nameStyle(Color c) => TextStyle(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, fontSize: 12, fontWeight: FontWeight.w700, fontVariations: const [FontVariation('wght', 650)], color: nameInk(c), height: 1.2);
  static const rangeStyle = TextStyle(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, fontSize: 10.5, fontWeight: FontWeight.w500, color: Ui.text3, height: 1.2);
  static const howStyle = TextStyle(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback, fontSize: 11, fontWeight: FontWeight.w600, color: Ui.text2, height: 1.2);
  static const tickStyle = TextStyle(fontSize: 10.5, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]);

  /// 왼쪽 칸의 안내 글(웹 HINT 그대로).
  static const hint = '막대를 누르면 위 연표의 그 나라 띠에 그 단체의 집권 기간이 조명됩니다. 이음선을 누르면 그 일(갈라짐 · 합쳐짐 · 이름 바꿈)의 사건. 연표를 밀거나 당기면 나무도 함께 움직입니다.';

  /// 이음선 갈래의 이름(풍선 · 선 견본).
  static const howWords = {'split': '갈라짐', 'merge': '합쳐짐', 'rename': '이름 바꿈', 'unknown': '방식 미상', 'blank': '적지 않음'};
}

// ────────────────────────────────────────────────────────────────────────────────────────────
//  3. 자리 셈 — 웹 render()의 셈 그대로(화면과 무관 · 검사가 직접 본다)
// ────────────────────────────────────────────────────────────────────────────────────────────

/// 이음선의 꼴: 실선 2px · 옅은 1px · 점선 2px(둥근 점 4.2 간격).
enum GroupLineStyle { solid, faint, dotted }

@immutable
class GroupBarGeo {
  const GroupBarGeo(this.x1, this.x2, this.y, this.row);
  final double x1, x2, y;
  final int row;
  double get cy => y + GroupTreeLook.barHeight / 2;
  Rect get rect => Rect.fromLTRB(x1, y, x2, y + GroupTreeLook.barHeight);
}

/// 꺾인 선 하나(점 목록) — 점선은 꺾여도 무늬가 이어진다.
@immutable
class GroupPolyline {
  const GroupPolyline(this.points, this.style);
  final List<Offset> points;
  final GroupLineStyle style;
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

/// 한 번 그릴 것: 막대 자리 · 이음선 · 네모(매듭) · '방식 미상' 글 · 누르는 자리.
class GroupTreeGeometry {
  GroupTreeGeometry._(this.bars, this.lines, this.knots, this.hows, this.hits, this.height);

  /// 노드 차례 그대로(보이지 않는 줄도 자리는 셈한다 — 누르기 · 검사가 쓴다).
  final List<GroupBarGeo> bars;
  final List<GroupPolyline> lines;

  /// 매듭 네모(이름 바꿈 · 합쳐짐) — 선 위에 그린다.
  final List<Rect> knots;

  /// '방식 미상' 글의 오른쪽 끝 · 바탕선.
  final List<Offset> hows;
  final List<GroupEdgeHit> hits;
  final double height;

  static double yOfRow(int row) => GroupTreeLook.top + row * GroupTreeLook.pitch;

  /// [x]는 분 → 그림 영역 안의 x(px), [width]는 그림 영역의 폭, [rows]는 그릴 줄의 범위(위아래 여유 포함 — 없으면 모두),
  /// [howWidth]는 '방식 미상' 글의 폭(그 자리에 들어갈 때만 글을 둔다).
  factory GroupTreeGeometry.of(GroupTreeData d, double Function(double minute) x, {required double width, ({int lo, int hi})? rows, double howWidth = 48}) {
    const bh = GroupTreeLook.barHeight;
    final h = GroupTreeLook.top + math.max(1, d.rows) * GroupTreeLook.pitch;
    final into = List.generate(d.nodes.length, (_) => <GroupTreeEdge>[]);
    final inEdges = List.generate(d.nodes.length, (_) => <GroupTreeEdge>[]);
    for (final e in d.edges) {
      into[e.from].add(e);
      inEdges[e.to].add(e);
    }
    /* 막대 자리 — 이음선이 닿는 머리는 5px 들여 선이 보이게, 이름 바꿈 다리는 4px씩 비움, 끝에서 아이가 나오면 줄기가 보이게 3px 비움 */
    final bars = <GroupBarGeo>[];
    for (int i = 0; i < d.nodes.length; i++) {
      final g = d.nodes[i];
      var x1 = x(g.lo), x2 = x(g.hi);
      if (inEdges[i].any((e) => e.same)) {
        x1 += 4;
      } else if (inEdges[i].isNotEmpty) {
        x1 += 5;
      }
      if (into[i].any((e) => e.same)) {
        x2 -= 4;
      } else if (into[i].any((e) => !e.same && x(d.nodes[e.to].lo) >= x2 - 1)) {
        x2 -= 3;
      }
      if (x2 - x1 < 2) x2 = x1 + 2;
      bars.add(GroupBarGeo(x1, x2, yOfRow(g.row), g.row));
    }
    bool rowsIn(int ra, int rb) => rows == null || (math.max(ra, rb) >= rows.lo && math.min(ra, rb) <= rows.hi);
    bool xsIn(double xa, double xb) => math.max(xa, xb) >= -40 && math.min(xa, xb) <= width + 40;
    /* 한 부모에서 같은 x로 다른 꼴의 선이 둘 이상이면 뒤의 꼴을 6px 오른쪽으로(선이 포개져 꼴이 섞이지 않게) */
    final shift = <String, List<String>>{};
    final dx = <GroupTreeEdge, double>{};
    for (final e in d.edges) {
      if (e.same || e.kind == 'merge') continue;
      final key = '${e.from}|${x(e.after ? d.nodes[e.from].hi : d.nodes[e.to].lo).round()}';
      final seen = shift.putIfAbsent(key, () => []);
      if (!seen.contains(e.kind)) seen.add(e.kind);
      dx[e] = seen.indexOf(e.kind) * 6.0;
    }
    final lines = <GroupPolyline>[], knots = <Rect>[], hows = <Offset>[], hits = <GroupEdgeHit>[];
    final mergeDone = <int>{};
    GroupLineStyle style(String kind) => kind == 'blank' ? GroupLineStyle.faint : kind == 'unknown' ? GroupLineStyle.dotted : GroupLineStyle.solid;
    for (final e in d.edges) {
      final a = bars[e.from], b = bars[e.to];
      if (!rowsIn(a.row, b.row) || !xsIn(math.min(a.x2, x(d.nodes[e.to].lo)), b.x1)) continue;
      if (e.same) {
        // 이름 바꿈 — 같은 줄: 앞 막대 끝과 뒤 막대 머리 사이 다리
        lines.add(GroupPolyline([Offset(a.x2 + 3, b.cy), Offset(math.max(a.x2 + 3, b.x1 - 3), b.cy)], GroupLineStyle.solid));
        knots.add(Rect.fromLTWH(a.x2 - 2, b.cy - 4, 5, 8));
        knots.add(Rect.fromLTWH(b.x1 - 3, b.cy - 4, 5, 8));
        hits.add(GroupEdgeHit(e, [Offset(a.x2 - 2, b.cy), Offset(b.x1 + 2, b.cy)]));
        continue;
      }
      // 세로 줄기의 x: 합쳐짐은 모이는 자리(뒤 단체의 머리), 부모가 끝난 뒤 시작한 아이는 부모의 끝, 부모 안에서 갈라진 아이는 제 시작
      final after = e.kind != 'merge' && e.after;
      final sx = math.max(x(after ? d.nodes[e.from].hi : d.nodes[e.to].lo), a.x1 + 2) + (dx[e] ?? 0);
      final down = b.row > a.row;
      final inside = sx > a.x1 + 2 && sx < a.x2 - 2;
      final y0 = inside ? (down ? a.y + bh : a.y) : a.cy;
      final lead = !inside && sx > a.x2 + .5 ? [Offset(a.x2, a.cy), Offset(sx, a.cy)] : null;
      if (e.kind == 'merge') {
        if (lead != null) lines.add(GroupPolyline(lead, GroupLineStyle.solid));
        lines.add(GroupPolyline([Offset(sx, y0), Offset(sx, b.cy)], GroupLineStyle.solid));
        hits.add(GroupEdgeHit(e, [...?lead, Offset(sx, y0), Offset(sx, b.cy)]));
        if (mergeDone.add(e.to)) {
          lines.add(GroupPolyline([Offset(sx, b.cy), Offset(b.x1, b.cy)], GroupLineStyle.solid));
          knots.add(Rect.fromLTWH(sx - 4, b.cy - 4, 8, 8)); // 모이는 자리의 네모(선 위에)
        }
        continue;
      }
      final s = e.kind == 'rename' ? GroupLineStyle.solid : style(e.kind);
      if (lead != null) lines.add(GroupPolyline(lead, s));
      final stem = [Offset(sx, y0), Offset(sx, b.cy), Offset(b.x1, b.cy)];
      lines.add(GroupPolyline(stem, s));
      if (e.kind == 'rename') knots.add(Rect.fromLTWH(b.x1 - 6, b.cy - 4, 5, 8));
      hits.add(GroupEdgeHit(e, [...?lead, ...stem]));
      // '방식 미상' 글 — 아이 줄의 선 왼쪽에(그 줄은 아이 막대부터 시작하므로 비어 있음). 보이는 곳에 들어갈 때만
      if (e.kind == 'unknown' && sx - 8 - howWidth >= 2) hows.add(Offset(sx - 8, b.cy + 4));
    }
    return GroupTreeGeometry._(bars, lines, knots, hows, hits, h);
  }

  /// 그 자리의 막대(노드 차례) — 없으면 -1.
  int barAt(Offset p) {
    for (int i = bars.length - 1; i >= 0; i--) {
      if (bars[i].rect.contains(p)) return i;
    }
    return -1;
  }

  /// 그 자리의 이음선(누를 수 있는 것 — 사건이 있는 것만). 없으면 null.
  GroupTreeEdge? edgeAt(Offset p) {
    for (final h in hits.reversed) {
      if (h.edge.ev.isNotEmpty && h.contains(p)) return h.edge;
    }
    return null;
  }
}

/// 막대 이름 — 보이는 부분 안에 들어가는 만큼: 이름 + 기간 → 이름 → 첫 글자 → 없음(잘린 글자 · 돌출 없음 — 웹 label()).
({String name, String range})? groupBarLabel(GroupTreeNode g, double vx1, double vx2, double Function(String text, TextStyle style) widthOf) {
  final room = vx2 - vx1 - 14;
  final nameStyle = GroupTreeLook.nameStyle(g.color);
  final wn = widthOf(g.name, nameStyle);
  final wr = widthOf(g.range, GroupTreeLook.rangeStyle);
  if (g.range.isNotEmpty && wn + 6 + wr <= room) return (name: g.name, range: g.range);
  if (wn <= room) return (name: g.name, range: '');
  final first = g.name.characters.isEmpty ? '' : g.name.characters.first;
  if (first.isNotEmpty && widthOf(first, nameStyle) <= room) return (name: first, range: '');
  return null;
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

class _GroupTreePainter extends CustomPainter {
  _GroupTreePainter({required this.data, required this.geo, required this.x, required this.ticks, required this.selected, required this.hovered, required this.widths, required this.rows});
  final GroupTreeData data;
  final GroupTreeGeometry geo;

  /// 분 → 그림 영역 안 x.
  final double Function(double minute) x;

  /// 세로 눈금선의 x(그림 영역 안).
  final List<double> ticks;
  final int selected, hovered;
  final _TextWidths widths;
  final ({int lo, int hi}) rows;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final w = size.width, h = geo.height;
    /* 연도 눈금선 */
    final grid = Paint()
      ..color = Ui.line
      ..strokeWidth = 1;
    for (final x in ticks) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
    }
    /* 이음선(막대 아래에 먼저) */
    for (final l in geo.lines) {
      _line(canvas, l);
    }
    /* 막대 */
    for (int i = 0; i < data.nodes.length; i++) {
      final g = data.nodes[i], b = geo.bars[i];
      if (b.row < rows.lo || b.row > rows.hi || math.max(b.x1, b.x2) < -40 || math.min(b.x1, b.x2) > w + 40) continue;
      final here = i == selected;
      final dim = i == hovered ? .97 : 1.0; // 올리면 css filter: brightness(.97)
      final base = RRect.fromRectAndRadius(b.rect, const Radius.circular(7));
      canvas.drawRRect(base, Paint()..color = _bright(GroupTreeLook.base(g.color), dim));
      canvas.drawRRect(
        base,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = here ? 2 : 1
          ..color = _bright(GroupTreeLook.baseEdge(g.color, here: here), dim),
      );
      for (final s in g.segs) {
        final a = math.max(x(s.a), b.x1) + .5;
        final z = math.min(x(s.b), b.x2) - .5;
        if (z - a < 1) continue;
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(a, b.y + .5, z - a, GroupTreeLook.barHeight - 1), const Radius.circular(6));
        canvas.drawRRect(r, Paint()..color = GroupTreeLook.segFill(g.color, s.kind));
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = GroupTreeLook.segEdge(g.color),
        );
      }
      final vx1 = math.max(b.x1, 0.0), vx2 = math.min(b.x2, w);
      if (vx2 - vx1 > 4) {
        final label = groupBarLabel(g, vx1, vx2, widths.width);
        if (label != null) {
          final name = widths.painter(label.name, GroupTreeLook.nameStyle(g.color));
          final baseline = b.y + 14;
          name.paint(canvas, Offset(vx1 + 8, baseline - name.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
          if (label.range.isNotEmpty) {
            final range = widths.painter(label.range, GroupTreeLook.rangeStyle);
            range.paint(canvas, Offset(vx1 + 8 + name.width + 6, baseline - range.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
          }
        }
      }
    }
    /* 매듭 네모 · '방식 미상' 글(선 · 막대 위에) */
    final knotFill = Paint()..color = Ui.surface;
    final knotEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = GroupTreeLook.line;
    for (final k in geo.knots) {
      final r = RRect.fromRectAndRadius(k, const Radius.circular(1.5));
      canvas.drawRRect(r, knotFill);
      canvas.drawRRect(r, knotEdge);
    }
    for (final p in geo.hows) {
      final t = widths.painter('방식 미상', GroupTreeLook.howStyle);
      t.paint(canvas, Offset(p.dx - t.width, p.dy - t.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
    }
  }

  static Color _bright(Color c, double k) => k == 1 ? c : Color.fromARGB((c.a * 255).round(), (c.r * 255 * k).round(), (c.g * 255 * k).round(), (c.b * 255 * k).round());

  void _line(Canvas canvas, GroupPolyline l) {
    if (l.points.length < 2) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = l.style == GroupLineStyle.faint ? GroupTreeLook.faint : GroupTreeLook.line
      ..strokeWidth = l.style == GroupLineStyle.faint ? 1 : 2;
    if (l.style != GroupLineStyle.dotted) {
      final path = Path()..moveTo(l.points.first.dx, l.points.first.dy);
      for (final p in l.points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
      return;
    }
    // 점선 — css stroke-dasharray "0 4.2" + 둥근 끝: 4.2px마다 지름 2px 점(꺾여도 무늬가 이어진다)
    final dot = Paint()..color = GroupTreeLook.line;
    var carry = 0.0;
    for (int i = 0; i + 1 < l.points.length; i++) {
      final a = l.points[i], b = l.points[i + 1];
      final len = (b - a).distance;
      var t = carry;
      while (t <= len + 1e-6) {
        canvas.drawCircle(Offset.lerp(a, b, len == 0 ? 0 : t / len)!, 1, dot);
        t += 4.2;
      }
      carry = t - len;
    }
  }

  @override
  bool shouldRepaint(_GroupTreePainter old) => old.geo != geo || old.selected != selected || old.hovered != hovered || old.rows != rows || old.data != data;

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
  final _ruler = Ruler();

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
                child: KeyedSubtree(key: groupTreeKey, child: _sheet(d)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sheet(GroupTreeData d) => DefaultTextStyle(
    // 연표 위에 뜨는 창이라 글꼴을 직접 준다(노선도 카드와 같이 — 앱 틀의 테마 글꼴이 이 층까지 내려오지 않는 자리).
    style: DetailUi.body.copyWith(fontFamily: sceneFontFamily, fontFamilyFallback: sceneFontFallback),
    child: Container(
      decoration: BoxDecoration(
        // 떠 있는 면은 불투명한 종이 + 1px 선 하나(그림자 · 반투명 없음 — HistoryArchive 통일). 뒤의 연표가 비치면 글이 겹쳐 보인다.
        color: Ui.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(GroupTreeLook.radius)),
        boxShadow: Ui.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(d),
          _title(d),
          const _Legend(),
          Expanded(child: _main(d)),
          _foot(d),
        ],
      ),
    ),
  );

  Widget _head(GroupTreeData d) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 12, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (d.polityUid.isNotEmpty) DetailBadge(d.polityName, color: d.polityColor, onTap: () => _bus.select(d.polityUid)),
                const DetailBadge('단체 계보', color: Ui.text3),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        ShellButton(width: 32, padding: EdgeInsets.zero, tooltip: '닫기', onPressed: close, child: const Text('✕', style: TextStyle(fontSize: 13))),
      ],
    ),
  );

  /// 제목 줄 — `단체 계보` + `나라 · 단체 n · 연도 눈금은 연표와 같은 자리`.
  String subOf(GroupTreeData d) => [if (d.polityName.isNotEmpty) d.polityName, '단체 ${d.nodes.length}', '연도 눈금은 연표와 같은 자리'].join(' · ');

  Widget _title(GroupTreeData d) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        const Text('단체 계보', style: TextStyle(fontFamily: Ui.title, fontFamilyFallback: Ui.titleFallback, fontSize: 20, height: 1.4, fontWeight: FontWeight.w700, letterSpacing: -.4, color: Ui.text)), // D2 지정 제목 글꼴 + D5 창 제목 20/28
        const SizedBox(width: 10),
        Expanded(child: Text(subOf(d), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.5, color: Ui.text3))),
      ],
    ),
  );

  Widget _foot(GroupTreeData d) => DecoratedBox(
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Ui.line))),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (d.polityUid.isNotEmpty) IntrinsicWidth(child: DetailSmallButton('◀ 나라 상세', onTap: () => _bus.select(d.polityUid))),
          IntrinsicWidth(child: DetailSmallButton('닫기', onTap: close)),
        ],
      ),
    ),
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

  Widget _main(GroupTreeData d) {
    final plot = plotOf();
    final ticks = _ticks(plot.width);
    return Stack(
      children: [
        if (plot.left >= 120)
          Positioned(
            left: 18,
            top: 18,
            bottom: 6,
            width: math.max(0, plot.left - 34),
            child: SingleChildScrollView(child: _side(d)),
          ),
        Positioned(
          left: plot.left,
          width: plot.width,
          top: 0,
          bottom: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: GroupTreeLook.axisHeight,
                child: ClipRect(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final t in ticks)
                        if (t.label.isNotEmpty && t.x >= 14 && t.x <= plot.width - 14)
                          Positioned(left: t.x, top: 1, child: FractionalTranslation(translation: const Offset(-.5, 0), child: Text(t.label, style: GroupTreeLook.tickStyle, maxLines: 1))),
                    ],
                  ),
                ),
              ),
              Expanded(child: _tree(d, plot.width, [for (final t in ticks) t.x])),
            ],
          ),
        ),
      ],
    );
  }

  /// 연도 눈금 — 연표의 날짜 칸과 같은 눈금 셈(scene/ruler.dart). 글은 해의 첫날에 선 눈금에만(웹: 정수 해만).
  List<({double x, String label})> _ticks(double width) {
    final v = _bus.controller.view;
    final model = _ruler.compute(v.lo, v.hi, v.ppm);
    final out = <({double x, String label})>[];
    for (final t in model.ticks) {
      if (!t.shown) continue;
      final x = xOf(t.minute);
      if (x < -1 || x > width + 1) continue;
      var label = '';
      if (!model.sub) {
        label = t.label;
      } else {
        final y = yearAt(t.minute).roundToDouble();
        if ((minuteOfYear(y) - t.minute).abs() < 1) label = yearLabel(y.toInt());
      }
      out.add((x: x, label: label));
    }
    return out;
  }

  Widget _tree(GroupTreeData d, double width, List<double> ticks) => LayoutBuilder(
    builder: (context, box) {
      final viewH = box.maxHeight.isFinite ? box.maxHeight : 400.0;
      final offset = _scroll.hasClients ? _scroll.offset : 0.0;
      final r0 = ((offset - GroupTreeLook.top) / GroupTreeLook.pitch).floor() - 6;
      final r1 = ((offset + viewH) / GroupTreeLook.pitch).ceil() + 6;
      final rows = (lo: r0, hi: r1);
      final geo = GroupTreeGeometry.of(d, xOf, width: width, rows: rows, howWidth: _widths.width('방식 미상', GroupTreeLook.howStyle));
      final painter = _GroupTreePainter(data: d, geo: geo, x: xOf, ticks: ticks, selected: _selected, hovered: _hovered, widths: _widths, rows: rows);
      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollUpdateNotification && d.rows * GroupTreeLook.pitch > viewH) setState(() {}); // 나무 안 세로 밀기 — 새로 보이는 줄을 그림
          return false;
        },
        child: SingleChildScrollView(
          controller: _scroll,
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
            // 같은 막대를 300ms 안에 다시 누르면 두 번 누름(웹 dblclick — 단체 창).
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

  /// 지난 누름(막대 차례 · 때) — 두 번 누름을 가린다.
  int _lastBar = -1;
  Duration? _lastAt;

  /// 누름 — 막대면 그 단체를 고르고, 사건이 있는 이음선이면 그 사건 창.
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

  Widget _side(GroupTreeData d) {
    const hint = Text(GroupTreeLook.hint, style: TextStyle(fontSize: 12, height: 1.55, color: Ui.text3));
    if (_selected < 0) return hint;
    final g = d.nodes[_selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: g.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 650)])),
                const TextSpan(text: ' '),
                const TextSpan(text: '— 연표에 조명 중', style: TextStyle(fontSize: 10)),
              ],
            ),
            style: const TextStyle(fontSize: 12, height: 1.55, color: Ui.text2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text([g.when, if (g.count.isNotEmpty) g.count].join('\n'), style: const TextStyle(fontSize: 12, height: 1.55, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()])),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              IntrinsicWidth(child: DetailSmallButton('단체 창', onTap: () => _bus.select(g.uid, kind: 'group'))),
              IntrinsicWidth(child: DetailSmallButton('이 시기로', onTap: () => focusOn(g))),
            ],
          ),
        ),
        hint,
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
//  6. 선 견본 — 갈라짐 · 합쳐짐 · 이름 바꿈 · 방식 미상 · 적지 않음 + 막대 견본(집권 · 연정 · 있던 기간)
// ────────────────────────────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend();

  /// 견본 막대의 색(웹 `.gt-sw`) — 어느 단체의 색도 아닌 잉크(상태는 색 없이 잉크의 짙기로 — HistoryArchive 통일).
  static const swatch = Ui.ink;

  @override
  Widget build(BuildContext context) {
    Widget item(Widget mark, String text) => Row(mainAxisSize: MainAxisSize.min, children: [mark, const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 12, height: 1.5, color: Ui.text2))]);
    Widget sw(GroupSegKind? k) => Container(
      width: 18,
      height: 12,
      decoration: BoxDecoration(
        color: k == null ? GroupTreeLook.base(swatch) : GroupTreeLook.segFill(swatch, k),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: k == null ? Ui.ink60 : GroupTreeLook.segEdge(swatch), width: 1),
      ),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      // 카드 꼴(칠한 상자)이 아니라 선과 둥근 6 — 전에는 `surface2`(잉크 8%)의 알파를 .7로 갈아 끼워 상자가 검게 나왔다.
      decoration: BoxDecoration(border: Border.all(color: Ui.line), borderRadius: BorderRadius.circular(Ui.controlRadius)),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final k in const ['split', 'merge', 'rename', 'unknown', 'blank']) item(CustomPaint(size: Size(k == 'rename' ? 26 : 24, 14), painter: _LegendIcon(k)), GroupTreeLook.howWords[k]!),
          item(sw(GroupSegKind.power), '집권'),
          item(sw(GroupSegKind.coal), '연정'),
          item(sw(null), '있던 기간'),
        ],
      ),
    );
  }
}

/// 선 견본 그림 — 웹 legendIcon()의 SVG 경로 그대로.
class _LegendIcon extends CustomPainter {
  const _LegendIcon(this.kind);
  final String kind;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Ui.text2;
    final box = Paint()..color = Ui.surface;
    final boxEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Ui.text2;
    void lines(List<List<Offset>> ps, Paint p) {
      for (final l in ps) {
        final path = Path()..moveTo(l.first.dx, l.first.dy);
        for (final q in l.skip(1)) {
          path.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(path, p);
      }
    }

    switch (kind) {
      case 'split':
        lines([
          [const Offset(2, 7), const Offset(8, 7)],
          [const Offset(8, 2), const Offset(8, 12)],
          [const Offset(8, 2), const Offset(22, 2)],
          [const Offset(8, 12), const Offset(22, 12)],
        ], ink);
      case 'merge':
        lines([
          [const Offset(2, 2), const Offset(14, 2)],
          [const Offset(2, 12), const Offset(14, 12)],
          [const Offset(14, 2), const Offset(14, 12)],
          [const Offset(14, 7), const Offset(22, 7)],
        ], ink);
        final r = RRect.fromRectAndRadius(const Rect.fromLTWH(11, 4, 6, 6), const Radius.circular(1.5));
        canvas.drawRRect(r, box);
        canvas.drawRRect(r, boxEdge);
      case 'rename':
        final a = RRect.fromRectAndRadius(const Rect.fromLTWH(1, 3, 6, 8), const Radius.circular(2));
        final b = RRect.fromRectAndRadius(const Rect.fromLTWH(19, 3, 6, 8), const Radius.circular(2));
        lines([
          [const Offset(7, 7), const Offset(19, 7)],
        ], ink);
        for (final r in [a, b]) {
          canvas.drawRRect(r, box);
          canvas.drawRRect(r, boxEdge);
        }
      case 'unknown':
        final dot = Paint()..color = Ui.text2;
        for (var x = 3.0; x <= 22 + 1e-6; x += 4.2) {
          canvas.drawCircle(Offset(x, 7), 1, dot);
        }
      default:
        canvas.drawLine(
          const Offset(2, 7.5),
          const Offset(22, 7.5),
          Paint()
            ..strokeWidth = 1
            ..color = GroupTreeLook.faint,
        );
    }
  }

  @override
  bool shouldRepaint(_LegendIcon old) => old.kind != kind;
}

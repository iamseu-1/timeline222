import 'package:flutter/foundation.dart';

import '../controller.dart';
import '../scene/layout.dart';
import '../scene/scene.dart';

// 앱의 부품들(상세 창 · 검색 · 필터 · 도구 · 카드 · 단축키)이 서로의 파일을 모른 채 주고받는 길.
// 부품은 이 길만 받아서 일한다: 자료는 [ask]로 묻고, 고르기 · 가기 · 보기 조건은 여기의 값을 바꾸거나 듣는다.
// 값을 실제로 연표에 잇는 일(고른 것의 강조 · 멀리 가기의 움직임 · 조건에 따른 줄 다시 쌓기)은 앱 틀(archive_app.dart)이 이 길을 들으며 한다.

/// 고른 것. [uid]는 항목 기록(entities)의 열쇠, [cell]은 칸 참조('leader:3' · 'era:2' · 'capital:0' …)이고 없으면 항목 전체.
@immutable
class Selection {
  const Selection(this.uid, {this.kind = '', this.cell, this.eventId});
  final String uid, kind;
  final String? cell;

  /// 연표의 사건 번호(저장소의 events.id) — 연표에서 눌러 골랐을 때만 안다.
  final int? eventId;

  @override
  bool operator ==(Object other) => other is Selection && other.uid == uid && other.cell == cell;
  @override
  int get hashCode => Object.hash(uid, cell);
}

/// 가 달라는 부탁: 기간(분)과, 있으면 세로로 데려올 줄. [fly]가 참이면 멀리 가기(물러났다 다가감), 아니면 바로.
@immutable
class GoRequest {
  const GoRequest(this.lo, this.hi, {this.row, this.fly = true, this.ring});
  final double lo, hi;
  final int? row;
  final bool fly;

  /// 도착한 뒤 고리를 한 번 보일 항목(uid).
  final String? ring;
}

class AppBus {
  AppBus({required this.ask, required this.controller, required this.scene});

  /// 자료 처리부에 묻는 길: {"op": …} → 답의 data. 예: {'op':'entity','uid':…} → {uid, kind, json}.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> query) ask;
  final TimelineController controller;
  final TimelineScene scene;

  /// 고른 것(없으면 null). 상세 창은 이것을 듣고 열리고 닫힌다.
  final selection = ValueNotifier<Selection?>(null);

  /// 가 달라는 마지막 부탁. 앱 틀이 듣고 연표를 옮긴다.
  final go = ValueNotifier<GoRequest?>(null);

  /// 보기 조건(켠 단 · 밀도). 앱 틀이 듣고 줄을 다시 쌓는다.
  final conditions = ValueNotifier<ViewConditions>(const ViewConditions());

  /// 부품끼리 알릴 것이 더 있으면 이름을 붙여 여기에 둔다(예: 'filters' · 'lens' · 'marker'). 값의 모양은 그 부품의 파일이 정한다.
  final _slots = <String, ValueNotifier<Object?>>{};
  ValueNotifier<Object?> slot(String name) => _slots[name] ??= ValueNotifier<Object?>(null);

  void select(String uid, {String kind = '', String? cell, int? eventId}) => selection.value = Selection(uid, kind: kind, cell: cell, eventId: eventId);
  void clearSelection() => selection.value = null;
  void goTo(double lo, double hi, {int? row, bool fly = true, String? ring}) => go.value = GoRequest(lo, hi, row: row, fly: fly, ring: ring);

  void dispose() {
    selection.dispose();
    go.dispose();
    conditions.dispose();
    for (final s in _slots.values) {
      s.dispose();
    }
  }
}

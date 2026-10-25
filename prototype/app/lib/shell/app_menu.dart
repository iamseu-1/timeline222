import 'package:flutter/material.dart';

import '../ui/context_menu.dart' show MenuRow, showTimelineMenu;

// 맨 위 줄의 `⋯` 메뉴. 웹 연표의 .ctx-menu와 같은 면이다(paper 바탕 · ink20 선 · 둥근 12 · 그림자 없음).

/// 메뉴의 한 줄. [onSelected]가 없거나 [enabled]가 거짓이면 누를 수 없다(안내 줄).
class AppMenuItem {
  const AppMenuItem(this.label, {this.onSelected, this.enabled = true});
  final String label;
  final VoidCallback? onSelected;
  final bool enabled;
}

/// [anchor]가 가리키는 단추의 왼쪽 아래에 메뉴를 연다. 고른 줄이 있으면 그 줄의 일을 한다.
Future<void> showAppMenu(BuildContext anchor, List<AppMenuItem> items) async {
  if (items.isEmpty) return;
  final button = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox;
  final topLeft = button.localToGlobal(Offset(0, button.size.height + 6), ancestor: overlay);
  await showTimelineMenu(anchor, [for (final item in items) MenuRow(item.label, enabled: item.enabled && item.onSelected != null, onSelected: item.onSelected)], at: topLeft);
}

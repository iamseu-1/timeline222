import 'package:flutter/material.dart';

import '../controller.dart';
import 'line_icon.dart';
import 'look.dart';
import 'parts.dart';

// 오른쪽 아래 확대 단추 묶음(웹 연표의 .zoom-controls): 40×142 · 32×32 단추 넷(둥근 4) · 사이 2 · 안쪽 여백 4 · paper 바탕에 ink20 선 · 둥근 6.
// 기호는 맨 위 줄과 같은 선 아이콘(16 — 건의 8의 1번): 확대 · 축소는 지금 연표의 timeline.zoom(0.6) · zoom(1.6)과 같은 배율, 그다음 전체 보기 · 조감(V).
// 리메이크 2부(목업 서고 frame): [horizontal]이면 맨 위 줄 안의 가로 묶음 — 축소 · 확대 · 전체 보기 · 조감을 높이 36 · paper 바탕 · ink20 선 · 둥근 6 상자에
// 칸 사이 1px 금(ink20)으로 가른다(목업의 − + ⤢ 묶음 · 조감은 목업에 없지만 V와 같은 명령이라 남김).
class ZoomButtons extends StatelessWidget {
  const ZoomButtons({super.key, required this.controller, this.onBird, this.horizontal = false});
  final TimelineController controller;

  /// 맨 위 줄 안의 가로 묶음(리메이크 2부)인가.
  final bool horizontal;

  /// 조감 ↔ 직전 밀도(V와 같은 명령). 주지 않으면 단추가 눌리지 않는다.
  final VoidCallback? onBird;

  Offset get _center => Offset(controller.view.width / 2, controller.view.height / 2);

  Widget _button(LineGlyph glyph, String tooltip, VoidCallback? onPressed) => ShellButton(
    width: Ui.zoomButton,
    height: Ui.zoomButton,
    radius: Ui.innerRadius,
    padding: EdgeInsets.zero,
    tooltip: tooltip,
    onPressed: onPressed,
    child: LineIcon(glyph, size: Ui.menuIcon, color: Ui.ink),
  );

  @override
  Widget build(BuildContext context) => horizontal ? _row() : GlassCard(
    radius: Ui.zoomRadius,
    padding: const EdgeInsets.all(Ui.zoomPad),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(LineGlyph.plus, '확대 (+)', () => controller.wheel(_center, Ui.zoomInWheel)),
        const SizedBox(height: Ui.zoomGap),
        _button(LineGlyph.minus, '축소 (-)', () => controller.wheel(_center, Ui.zoomOutWheel)),
        const SizedBox(height: Ui.zoomGap),
        _button(LineGlyph.expand, '전체 보기 (0)', controller.showAll),
        const SizedBox(height: Ui.zoomGap),
        _button(LineGlyph.bird, '조감 (V)', onBird),
      ],
    ),
  );

  /// 맨 위 줄 안의 가로 묶음 — 칸 34 × 34 · 칸 사이 1px 금.
  Widget _row() {
    Widget cell(LineGlyph glyph, String tooltip, VoidCallback? onPressed) => ShellButton(
      width: 34,
      height: 34,
      radius: 0,
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      onPressed: onPressed,
      child: LineIcon(glyph, size: Ui.menuIcon, color: Ui.ink),
    );
    const rule = SizedBox(width: 1, height: 36, child: ColoredBox(color: Ui.ink20));
    return Container(
      height: 36,
      decoration: BoxDecoration(color: Ui.paper, borderRadius: BorderRadius.circular(Ui.controlRadius), border: Border.all(color: Ui.ink20)),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          cell(LineGlyph.minus, '축소 (-)', () => controller.wheel(_center, Ui.zoomOutWheel)),
          rule,
          cell(LineGlyph.plus, '확대 (+)', () => controller.wheel(_center, Ui.zoomInWheel)),
          rule,
          cell(LineGlyph.expand, '전체 보기 (0)', controller.showAll),
          rule,
          cell(LineGlyph.bird, '조감 (V)', onBird),
        ],
      ),
    );
  }
}

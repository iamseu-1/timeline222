import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../motion.dart';
import 'look.dart';
import 'motion_widgets.dart';

// 앱 틀이 함께 쓰는 작은 부품: 떠 있는 면과 단추. 웹 연표의 .zoom-controls · .filterbar · .icon-btn · .dock-btn와 같은 값이다.

/// 떠 있는 면: 불투명한 paper 바탕 + 1px ink20 선. 그림자와 뒤 흐림은 쓰지 않는다(HistoryArchive의 디자인 — look.dart의 값이 그렇게 정한다).
/// 이름은 예전 '유리 카드' 그대로다. 선은 자르지 않게 바깥에 둔다.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.radius, required this.child, this.color = Ui.glass, this.shadow = Ui.shadowSmall, this.blur = Ui.blur, this.padding});
  final double radius, blur;
  final Color color;
  final List<BoxShadow> shadow;
  final EdgeInsets? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final corner = BorderRadius.circular(radius);
    Widget body = Container(color: color, padding: padding, child: child);
    // 흐림은 0으로 두면 건너뛴다 — 칠하기가 한도를 넘으면 look.dart의 blur 값부터 재 본다.
    if (blur > 0) {
      body = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: body,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: corner, boxShadow: shadow),
      child: ClipRRect(borderRadius: corner, child: body),
    );
  }
}

/// 맨 위 줄 · 확대 묶음의 단추: 바탕 없음 → 올리면 ink8, 누른 상태(메뉴 · 시트가 열려 있음)면 반전 채움(ink 바탕 + paper 글자).
class ShellButton extends StatefulWidget {
  const ShellButton({
    super.key,
    required this.child,
    this.onPressed,
    this.width,
    this.height = Ui.buttonHeight,
    this.radius = Ui.buttonRadius,
    this.tooltip,
    this.expanded = false,
    this.padding = Ui.buttonPadding,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final double? width;

  /// 높이와 둥근 정도 — 맨 위 줄의 단추는 36 · 6, 확대 묶음 안의 단추와 닫기 단추는 32 · 4.
  final double height, radius;
  final String? tooltip;

  /// 이 단추가 연 것(메뉴 · 시트)이 열려 있는 동안 참 — 지금 연표의 `aria-expanded="true"`.
  final bool expanded;
  final EdgeInsets padding;

  @override
  State<ShellButton> createState() => _ShellButtonState();
}

class _ShellButtonState extends State<ShellButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.expanded ? Ui.paper : Ui.ink;
    Widget body = AnimatedContainer(
      duration: const Duration(milliseconds: Motion.microMs),
      curve: Ui.ease,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      decoration: BoxDecoration(color: widget.expanded ? Ui.ink : (_hover ? Ui.ink8 : const Color(0x00000000)), borderRadius: BorderRadius.circular(widget.radius)),
      // 폭을 받지 않았으면 제 글만큼만 넓다(Container의 alignment는 주어진 폭을 다 써서 줄바꿈 줄(Wrap) 안에서 한 줄을 통째로 차지한다).
      child: Align(
        widthFactor: widget.width == null ? 1 : null,
        child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color, height: 20 / 14),
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) body = Tooltip(message: widget.tooltip!, child: body);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: MotionPress(enabled: widget.onPressed != null, child: body),
        ),
      ),
    );
  }
}

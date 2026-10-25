import 'package:flutter/material.dart';

import 'look.dart';
import 'motion_widgets.dart';
import 'parts.dart';

/// `☰ 필터`가 여는 시트(웹 연표의 .filterbar): 맨 위 줄 아래로 내려오는 면 — paper 바탕 · ink20 선 · 둥근 12.
/// 바깥을 누르거나 Esc를 누르면 접힌다. 안에 들어갈 것(트랙 · 분류 · 종류 · 실재성 · 중요도 · 칸/선 켬끔 · 관점)은 묶음 8의 몫이라
/// 지금은 빈 시트를 여닫기만 한다 — 자리와 움직임을 먼저 맞춰 두기 위해서다.
class FilterSheet extends StatelessWidget {
  const FilterSheet({super.key, this.child, this.open = true});
  final bool open;

  /// 시트의 내용. 없으면 안내 글만 보인다.
  final Widget? child;

  @override
  Widget build(BuildContext context) => MotionPresence(
    open: open,
    child: GlassCard(
      radius: Ui.sheetRadius,
      blur: Ui.blurWide,
      shadow: Ui.shadow,
      padding: Ui.sheetPadding,
      child: child ?? const Text('필터와 표시 설정은 묶음 8에서 채웁니다.', style: TextStyle(fontSize: 13, height: 1.5, color: Ui.text2)),
    ),
  );
}

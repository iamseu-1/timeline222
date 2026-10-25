import 'package:flutter/material.dart';

import 'motion_widgets.dart';
import 'sheet_look.dart';
import 'sheet_parts.dart';

/// `☰ 필터`가 여는 시트: 맨 위 줄 아래로 내려오는 서고 폴더 '필터 · 표시'(리메이크 4단계 — 감독 고름 G5 #9 다듬기 판의 필터 시트).
/// 어깨 탭 안 맨 글 12 · 흰 둘레 6(그림자 대신 종이) · 몸통 둥근 10. 자리(앱 틀의 `Ui.sheetLeft` · `Ui.sheetTop`)와
/// 나타남 · 물러남(MotionPresence)은 4단계 전 그대로다. 폭은 속([child])에 맞추고(앱 틀이 1080 안으로 묶음),
/// 키가 앱 틀이 준 자리를 넘으면 폴더 안에서 위아래로 넘긴다. 바깥을 누르거나 Esc를 누르면 접힌다(앱 틀의 몫).
class FilterSheet extends StatelessWidget {
  const FilterSheet({super.key, this.child, this.open = true});
  final bool open;

  /// 시트의 내용. 없으면 안내 글만 보인다.
  final Widget? child;

  @override
  Widget build(BuildContext context) => MotionPresence(
    open: open,
    child: SheetFolder(
      label: '필터 · 표시',
      child: SingleChildScrollView(
        child: child ?? Text('필터와 표시 설정은 묶음 8에서 채웁니다.', style: sheetText(SheetLook.chipText, color: SheetLook.ink60)),
      ),
    ),
  );
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controller.dart';
import '../motion.dart';
import 'look.dart';
import 'motion_widgets.dart';

/// 돋보기 배율 표시: 100%가 아닐 때만 보이는 숫자 칸(paper 바탕 · ink20 선 · 둥근 6). 화면 오른쪽 아래에 선다(확대 단추 묶음은 리메이크 2부부터 도구줄 안).
/// 조종부의 배율만 듣는다 — 움직이는 장면마다 화면 부품을 다시 만들지 않게.
class MagPill extends StatelessWidget {
  const MagPill({super.key, required this.controller});
  final TimelineController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: controller.magnification,
    builder: (context, mag, _) {
      final shown = (mag - 1).abs() > .005;
      return IgnorePointer(
        child: MotionValue(
          target: shown ? 1 : 0,
          enter: MotionToken.enter, exit: MotionToken.exit, maxOvershoot: 0,
          builder: (context, value, child) => Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Ui.paper,
              borderRadius: BorderRadius.circular(Ui.controlRadius),
              border: Border.all(color: Ui.line),
            ),
            child: Text(
              '${(mag * 100).round()}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Ui.text, fontFeatures: [ui.FontFeature.tabularFigures()]),
            ),
          ),
        ),
      );
    },
  );
}

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../scene/viewport.dart' show SceneView;

/// 휴대폰에서는 화면을 '가로 [designWidth]px짜리 창'으로 배치하고 통째로 줄여 그린다.
///
/// 컴퓨터의 배치와 글자 크기의 비례를 그대로 둔 채 좁은 화면(가로 800~930 논리 px · 세로 360~410)에 다 담으려는 **첫 판**이다 —
/// 휴대폰 전용 배치(상세 창의 자리)는 목업으로 고른 뒤에 따로 만든다. 글자와 도형은 벡터라 줄여도 또렷하다.
/// 왼쪽 칸만은 이 배율 그대로 240 → [SceneView.phoneGutter]로 좁힌다(감독 2026-10-16 "지금과 같은 비율로 좀 왼쪽 부분을 좁혔으면").
/// `MaterialApp.builder`에 끼우므로 길잡이 위에 서는 것(오른쪽 클릭 메뉴 · 대화 상자 · 시트)까지 같은 배율로 선다.
/// 안쪽에서 보는 화면 정보(크기 · 기기 배율 · 가장자리 여백 · 자판 높이)도 같은 배율로 고쳐 준다 — 부품은 자기가 1100px 창에 있는 줄 안다.
class PhoneScale extends StatelessWidget {
  const PhoneScale({super.key, required this.child, this.force});

  final Widget child;

  /// 검사용: 참이면 컴퓨터에서도 건다(좁은 창일 때).
  final bool? force;

  static const designWidth = 1100.0;

  /// 그 화면에서의 배율(걸지 않으면 1).
  static double scaleFor(Size screen, {bool? force}) {
    final phone = force ?? (Platform.isAndroid || Platform.isIOS);
    if (!phone || screen.isEmpty || screen.width >= designWidth) return 1;
    return screen.width / designWidth;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = scaleFor(media.size, force: force);
    if (scale == 1) return child;
    // 줄여 그리는 기기에서는 왼쪽 칸도 좁힌다 — 장면은 자료를 받은 뒤에야 배치를 보기에 옮기므로 그 전에 켜 둔다(끄지는 않는다).
    SceneView.phone = true;
    final design = Size(designWidth, media.size.height / scale);
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: design.width,
        height: design.height,
        child: MediaQuery(
          data: media.copyWith(
            size: design,
            devicePixelRatio: media.devicePixelRatio * scale,
            padding: media.padding / scale,
            viewPadding: media.viewPadding / scale,
            viewInsets: media.viewInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}

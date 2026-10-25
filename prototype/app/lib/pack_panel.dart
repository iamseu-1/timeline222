import 'package:flutter/material.dart';

import 'scene/scene.dart';
import 'shell/look.dart';
import 'ui/dlc_manager.dart';

// 옛 이름의 얇은 껍데기 — 알맹이는 `ui/dlc_manager.dart`(DLC 관리 창)로 옮겼다.
// 창으로 띄우는 곳은 `showDlcManager(context, scene, onChanged: …)`를 쓴다.
export 'ui/dlc_manager.dart'
    show DlcCardInfo, DlcManager, DlcManagerBody, DlcSwitch, dlcBaseKey, dlcCardRoute, dlcEmptyText, dlcScreenNote, dlcTimelineEmpty, formatCount, showDlcManager;

/// 2단계의 작은 스위치 목록이 있던 자리. 이제는 DLC 관리 창의 알맹이를 그대로 띄운다 —
/// **마지막 하나도 끌 수 있다**(막지 않는다). 다 끄면 연표가 비고, 그 자리의 안내([dlcEmptyText])는 [onChanged]를 받은 쪽이 세운다.
class PackPanel extends StatelessWidget {
  const PackPanel({super.key, required this.scene, this.onChanged});
  final TimelineScene scene;
  final void Function(Set<int> packs)? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(22, 14, 22, 0),
        child: Text('DLC', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Ui.text2)),
      ),
      Flexible(child: DlcManagerBody(scene: scene, onChanged: onChanged)),
    ],
  );
}

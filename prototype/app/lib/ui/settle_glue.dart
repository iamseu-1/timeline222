import 'dart:ui' show Color;

import '../scene/layout.dart';
import '../scene/row_labels.dart';
import '../scene/scene.dart';
import 'app_bus.dart';
import 'edge_hint.dart';

// 정착을 듣고 가장자리 안내의 보고를 싣는 곳(명세 06의 4-3 · 움직임 원칙 ⑤).
//
// 지금 연표의 `_beginJump`(움직이기 전에 보이던 것을 찍어 둠) · `_settle` → `_announce`(멎은 뒤 한 번)를 그대로 옮겼다:
//  · 움직임이 시작되면(장면이 가라앉음 → 흔들림) 그때 보이던 단위를 찍어 둔다.
//  · **줄 접힘이 다 흐른 뒤**(장면이 다시 가라앉음)의 배치로 밀려난 것을 세어 `bus.slot('edge-hint')`에 싣는다.
//  · 밀려난 것이 없으면 슬롯을 건드리지 않는다(떠 있던 안내는 제 시한에 물러난다 — 지금 연표와 같다).
//
// 화면을 재지 않고 줄 배치(모델)의 자리로만 센다 — 셈 자체는 `edge_hint.dart`의 순수 함수([visibleUnits] · [pushedOut])다.
// 단위의 이름 · 색은 `{"op":"layout"}`이 준 트랙 · 묶음(`tracks[].groups`)과 줄 이름(`{"op":"row_labels"}`)에서 읽는다.
class SettleGlue {
  SettleGlue({required this.bus, RowLabels? labels, this.slotName = EdgeHint.slot}) : labels = labels ?? RowLabels();

  final AppBus bus;

  /// 줄의 대표 정권을 읽는 곳. 왼쪽 칸(그리기 층)이 이미 받아 둔 것을 넘겨주면 같은 것을 두 번 묻지 않는다.
  final RowLabels labels;

  /// 밀려남을 싣는 자리의 이름.
  final String slotName;

  TimelineScene get _scene => bus.scene;

  /// 길마다 하나씩 — 다리(`scene_bridge.dart`)가 옮기기 **전에** [beginJump]를 부르려고 찾는다.
  static final _byBus = Expando<SettleGlue>('정착 잇기');
  static SettleGlue? of(AppBus bus) => _byBus[bus];

  bool _started = false, _settled = true;
  Set<String> _before = const {};

  /// 찍어 둘 때의 보는 기간 — 기간이 달라졌으면 빈 줄 접힘이 다시 셈해진 뒤에 알린다.
  double _lo = 0, _span = 0;

  /// 듣기 시작한다(앱 틀에서 한 줄). 두 번 불러도 한 번만 붙는다.
  void start() {
    if (_started) return;
    _started = true;
    _byBus[bus] = this;
    labels.attach(_scene);
    _settled = _scene.settled;
    _scene.addListener(_onScene);
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    if (identical(_byBus[bus], this)) _byBus[bus] = null;
    _scene.removeListener(_onScene);
  }

  /// **옮기기 전에** 부른다(지금 연표의 `_beginJump`) — 손 · 휠은 장면이 흔들리는 것으로 알지만,
  /// 한 번에 서는 가기 · 접기는 옮긴 뒤에는 옛 자리를 알 길이 없다. 이미 찍어 둔 것이 있으면 그대로 둔다.
  void beginJump() {
    if (!_started || _before.isNotEmpty) return;
    final v = bus.controller.view;
    _before = visibleUnits(placements(), v.top, v.bodyHeight);
    _lo = v.lo;
    _span = v.span;
  }

  void _onScene() {
    final settled = _scene.settled, was = _settled;
    _settled = settled;
    if (!settled) {
      // 움직이기 시작했다 — 지금 보이던 것을 찍어 둔다(한 번의 움직임 동안 다시 찍지 않는다).
      if (was) beginJump();
      return;
    }
    if (_before.isEmpty) return;
    // 장면이 흔들렸다 가라앉았으면 그것이 정착이다. 흔들린 적이 없는데 보는 기간이 달라졌다면
    // 빈 줄 접힘을 아직 다시 묻지 않은 것이라 한 박자 기다린다(세로만 옮긴 것은 접힘이 달라지지 않는다).
    final v = bus.controller.view;
    if (was && (v.lo != _lo || v.span != _span)) return;
    _announce();
  }

  /// 멎은 뒤 한 번: 다 흐른 뒤의 배치로 밀려난 것을 세어 싣는다.
  void _announce() {
    final before = _before;
    _before = const {};
    if (before.isEmpty) return;
    final v = bus.controller.view;
    final report = pushedOut(before: before, after: placements(), viewTop: v.top, viewHeight: v.bodyHeight);
    if (report.isEmpty) return;
    bus.slot(slotName).value = report;
  }

  /// 지금 배치에서 셈할 수 있는 단위 모두 — 트랙 · 민족(대범위) 묶음 · 줄의 대표 정권(지금 연표의 `_visibleUnits`).
  /// 아직 이름을 받지 못한 줄은 함께 물어 둔다(답이 오면 다음 정착부터 든다).
  List<HintPlacement> placements() {
    final layout = _scene.layout, v = bus.controller.view;
    final at = ((v.lo + v.hi) / 2).round();
    final right = v.left + v.plotWidth;
    final out = <HintPlacement>[];
    final rows = <int>[];
    for (int i = 0; i < layout.tracks.length; i++) {
      final track = layout.tracks[i];
      final top = layout.trackTop(i), height = layout.trackHeight(i);
      // 끈 트랙 · 자료집을 끈 트랙은 자리가 없다.
      if (top < 0 || height <= 0) continue;
      final color = Color(0xff000000 | track.color);
      // 칩을 누르면 데려갈 줄: 트랙은 그 트랙에서 처음 보이는 줄(접힌 트랙이면 없다).
      int firstRow = -1;
      for (int r = track.firstRow; r < track.firstRow + track.rowCount && r < layout.rowCount; r++) {
        if (!layout.isVisible(r)) continue;
        firstRow = r;
        break;
      }
      out.add(HintPlacement(
        HintUnit(key: 't:${track.id}', kind: HintKind.track, name: track.name, trackId: track.id, color: color, row: firstRow < 0 ? null : firstRow),
        top,
        height,
      ));
      // 접힌 트랙은 트랙 하나로만 센다(그 안의 줄은 보이지 않는다).
      if (layout.isTrackFolded(track.id)) continue;
      final last = track.firstRow + track.rowCount;
      for (int row = track.firstRow; row < last && row < layout.rowCount; row++) {
        if (!layout.isVisible(row)) continue;
        final rowTop = layout.rowTop(row);
        if (rowTop < 0) continue;
        rows.add(row);
        // 접힌 대범위 가지의 합쳐진 줄에는 **변형 열쇠가 달린** 접힘용 후보뿐이다 — 왼쪽 칸(`paint/gutter.dart`)과 같은 값을 넘겨야
        // 그 줄이 '정권 단위' 칩으로 잘못 잡히지 않는다(11물결 stack3 ㈓).
        final label = labels.pick(row, at: at, xOf: v.xOf, left: v.left, right: right,
            foldedDepth: _foldedDepthOf(layout, row), foldedVariant: layout.foldedVariantOf(row));
        // 이름이 아직 오지 않은 줄 · 그 밖 줄 · 접힌 민족 줄은 정권 단위가 아니다.
        if (label == null || label.kind != RowLabel.band || label.period.isEmpty) continue;
        out.add(HintPlacement(
          HintUnit(
            key: 'p:${label.period}', kind: HintKind.polity, name: label.name.isEmpty ? label.period : label.name,
            trackId: track.id, trackName: track.name, color: Color(0xff000000 | label.color), uid: label.period, row: row,
          ),
          rowTop,
          layout.geo(row).height,
        ));
      }
      for (final group in track.groups) {
        if (group.name.isEmpty) continue;
        int first = -1, lastRow = -1;
        for (int r = group.firstRow; r < group.firstRow + group.rowCount && r < layout.rowCount; r++) {
          if (!layout.isVisible(r)) continue;
          if (first < 0) first = r;
          lastRow = r;
        }
        if (first < 0) continue;
        final y0 = layout.rowTop(first), y1 = layout.rowTop(lastRow) + layout.geo(lastRow).height;
        out.add(HintPlacement(
          HintUnit(
            key: 'g:${layout.groupKeyOf(track, group)}', kind: HintKind.people, name: group.name,
            trackId: track.id, trackName: track.name, color: Color(0xff000000 | group.color),
            // 칩을 누르면 그 묶음에서 처음 보이는 줄로 데려간다(지금 연표의 `_locate`).
            row: first,
            groupFirst: group.firstRow, groupCount: group.rowCount,
            // 대범위 가지는 민족이 아니다(칩에 적는 말이 다르다).
            groupWord: group.kind == 2 ? '대범위' : '민족',
          ),
          y0,
          y1 - y0,
        ));
      }
    }
    if (rows.isNotEmpty) labels.want(rows, at: at);
    return out;
  }

  /// 접힌 민족 줄이면 그 줄에 합쳐진 묶음의 단계(아니면 −1) — 왼쪽 칸과 같은 셈이다.
  static int _foldedDepthOf(SceneLayout layout, int row) {
    if (!layout.isFoldedGroupRow(row)) return -1;
    int best = -1;
    for (final group in layout.trackOf(row).groups) {
      if (group.firstRow != row || !layout.isGroupFolded(group)) continue;
      if (best < 0 || group.depth < best) best = group.depth;
    }
    return best < 0 ? 0 : best;
  }
}

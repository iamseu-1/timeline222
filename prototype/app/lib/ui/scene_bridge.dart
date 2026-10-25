import 'dart:async';

import '../scene/emphasis.dart' as em;
import '../scene/fly.dart';
import '../scene/marks.dart';
import 'app_bus.dart';
import 'app_glue.dart';
import 'settle_glue.dart';

// 앱 틀의 다리(SceneBridge)의 진짜 구현: 멀리 가기는 조종부의 비행(물러났다 다가감 · 세로를 같은 진행값에 실음)으로,
// 밝기 상태(고르기 · 강조 · 조명 · 가문)는 장면 곁의 Emphasis로 넣는다. 맞히기 · 트랙 접기는 바탕 구현을 이어 쓰다가 장면 쪽 길이 생기는 대로 채운다.
class LiveSceneBridge extends BasicSceneBridge {
  LiveSceneBridge(super.bus);

  /// 도착한 그 장면에 한 번 알린다(도착 고리 — GoRequest.ring의 uid). 도중에 누르면 부르지 않는다.
  /// 고리 자체는 [ringAt]이 스스로 건다 — 이 길은 곁들여 할 일이 더 있는 쪽(검사 · 창)을 위한 것이다.
  void Function(String uid)? onArrived;

  /// 늦게 온 답을 버리는 판 번호 — 잇따라 도착하면 마지막 고리만 산다.
  int _ringTurn = 0;

  /// 도착 고리(명세 06의 4-4): 닿은 항목의 uid를 타일의 번호로 바꿔 장면에 건다.
  /// 띠 · 사건이면 그것에, 둘 다 없고 줄만 알면 그 줄의 띠 모두에 두른다. 이름이 없는 것이면 걸지 않는다.
  Future<void> ringAt(String uid) async {
    if (uid.isEmpty) return;
    final turn = ++_ringTurn;
    final place = await _placeOf(uid);
    if (place == null || turn != _ringTurn) return;
    final band = place.band ?? 0, event = place.event ?? 0;
    final scene = bus.scene;
    SceneMarks.of(scene).showRing(
      SceneRing(band: band, event: event, row: band == 0 && event == 0 ? (place.row ?? -1) : -1, at: scene.now),
    );
    scene.requestFrame();
  }

  /// uid 하나의 자리(계약 2-1의 `ids_of` · 모르면 `id_of`). 자료 처리부가 답하지 못하면 null.
  Future<ItemPlace?> _placeOf(String uid) async {
    try {
      return readPlaces(await bus.ask({'op': 'ids_of', 'uids': [uid]}))[uid];
    } catch (_) {
      // ids_of를 아직 모르는 자료 처리부
    }
    try {
      return readPlaces(await bus.ask({'op': 'id_of', 'uid': uid}), single: uid)[uid];
    } catch (_) {
      return null;
    }
  }

  @override
  void go(GoRequest request, {double insetRight = 0}) {
    // 밀려난 것을 알리려면 **옮기기 전에** 지금 보이던 것을 찍어 두어야 한다(명세 06의 4-3).
    SettleGlue.of(bus)?.beginJump();
    final c = bus.controller, v = c.view, layout = bus.scene.layout;
    // 세로: 줄을 주면 그 줄이 화면 가운데에 오게(위에서 떨어질 거리 = max(56 + 탭 11, (몸통 − 줄 높이) / 2)). 접혀 안 보이는 줄이면 가로만 간다 — 도착해 줄이 펴진 뒤 한 번 더 데려온다.
    double? top;
    final row = request.row;
    bool pending = false;
    if (row != null && row >= 0 && row < layout.rowCount) {
      // 가려는 줄이 접힌 트랙 · 접힌 민족 · 켜지 않은 변형(펼치지 않은 소속 · 모으지 않은 대범위) 안이면 먼저 편다 — 다시 쌓기 한 번(계약 3-4).
      // 줄이 제자리로 흐르는 동안 떠나므로, 세로는 도착해서 한 번 더 맞춘다.
      final reveal = layout.revealFor(row);
      if (!identical(reveal, layout.viewState) && bus.scene.applyViewState(reveal)) {
        c.setContentHeight(layout.totalHeight);
        bus.scene.folder.forget();
        if (!request.fly) layout.finishFlow();
        pending = request.fly;
      }
      if (pending) {
        // 도착해서 데려온다
      } else if (layout.isVisible(row)) {
        top = _topFor(row);
        if ((top - v.top).abs() < .5) top = null;
      } else {
        pending = true;
      }
    }
    final inset = insetRight / v.mag;
    void arrived() {
      if (pending && layout.isVisible(row!)) {
        c.scrollTo(_topFor(row));
        onSelfScroll?.call();
      }
      final ring = request.ring;
      if (ring != null && ring.isNotEmpty) {
        unawaited(ringAt(ring));
        onArrived?.call(ring);
      }
    }

    if (top != null) onSelfScroll?.call();
    if (request.fly) {
      c.flyTo(request.lo, request.hi, top: top, insetRight: inset, onArrive: arrived);
    } else {
      // 바로 가기: 같은 도착점을 비행의 셈으로 구해 한 번에 선다.
      final point = request.hi <= request.lo;
      final span = point ? v.span : request.hi - request.lo;
      final plan = Fly.plan(
        fromLo: v.lo, fromSpan: v.span, toLo: point ? request.lo - span / 2 : request.lo, toSpan: span,
        plotWidth: v.plotWidth, insetRight: inset, inset: point ? FlyInset.center : FlyInset.fit, reduceMotion: true,
      );
      final to = plan.destination;
      c.showRange(to.$1, to.$1 + to.$2);
      if (top != null) c.scrollTo(top);
      arrived();
    }
  }

  double _topFor(int row) {
    final v = bus.controller.view, layout = bus.scene.layout;
    final height = layout.geo(row).height;
    final drop = (v.bodyHeight - height) / 2;
    return layout.rowTop(row) - (drop < 67 ? 67 : drop);
  }

  /// 모든 트랙을 접거나 편다. 바뀌었으면 참.
  @override
  bool foldAll(bool folded) {
    SettleGlue.of(bus)?.beginJump();
    final scene = bus.scene, layout = scene.layout;
    // 판을 켠 동안은 판의 접힘으로(접힘 기억은 그대로 — 집합 보기 결정 1 A).
    final next = layout.withAllFoldedState(folded);
    final changed = scene.applyViewState(next);
    if (changed) bus.controller.setContentHeight(layout.totalHeight);
    return changed;
  }

  /// 트랙 하나를 접고 편다(왼쪽 칸의 트랙 이름 · 접힌 트랙의 머리글).
  void toggleTrack(int trackId) {
    SettleGlue.of(bus)?.beginJump();
    final scene = bus.scene, layout = scene.layout;
    scene.applyViewState(layout.withTrackFoldedState(trackId, !layout.isTrackFolded(trackId)));
    bus.controller.setContentHeight(layout.totalHeight);
    onSelfScroll?.call();
  }

  /// 문화권 하나를 접고 편다(왼쪽 칸 · 그림판을 가로지르는 문화권 머리 단 — 리메이크 조각 ②).
  void toggleSphere(String id) {
    SettleGlue.of(bus)?.beginJump();
    final scene = bus.scene, layout = scene.layout;
    scene.applyViewState(layout.viewState.withSphereFolded(id, !layout.isSphereFolded(id)));
    bus.controller.setContentHeight(layout.totalHeight);
    onSelfScroll?.call();
  }

  /// 민족 묶음 하나를 접고 편다(왼쪽 칸의 민족 칸).
  void toggleGroup(int trackIndex, int groupIndex) {
    SettleGlue.of(bus)?.beginJump();
    final scene = bus.scene, layout = scene.layout;
    if (trackIndex < 0 || trackIndex >= layout.tracks.length) return;
    final track = layout.tracks[trackIndex];
    if (groupIndex < 0 || groupIndex >= track.groups.length) return;
    final group = track.groups[groupIndex], key = layout.groupKeyOf(track, group);
    scene.applyViewState(layout.viewState.withGroupFolded(key, !layout.isGroupFolded(group)));
    bus.controller.setContentHeight(layout.totalHeight);
    onSelfScroll?.call();
  }

  /// 켠 대범위의 가지 하나를 접고 편다(왼쪽 칸의 점선 칸 — `GutterHit.uid`가 그 가지의 열쇠 `__scope:<uid>`다).
  void toggleScopeGroup(int trackIndex, String key) {
    if (key.isEmpty) return;
    SettleGlue.of(bus)?.beginJump();
    final scene = bus.scene, layout = scene.layout;
    if (trackIndex < 0 || trackIndex >= layout.tracks.length) return;
    final gkey = layout.variantGroupKeyOf(trackIndex, key);
    scene.applyViewState(layout.viewState.withGroupFolded(gkey, !layout.viewState.isGroupFolded(gkey)));
    bus.controller.setContentHeight(layout.totalHeight);
    onSelfScroll?.call();
  }

  @override
  void emphasize(em.Look look) {
    super.emphasize(look); // 고른 사건의 고리 · 세로 닻의 줄
    em.Emphasis.of(bus.scene).set(look);
    bus.scene.requestFrame();
  }
}

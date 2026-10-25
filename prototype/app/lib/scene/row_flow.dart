// 줄 자리의 흐름과 세로 닻. 줄이 접히고 펴져도 "커졌다 줄어드는 두 단계" 없이 한 번의 이어진 움직임이고
// (움직임 원칙 ③ — 트랙 높이와 줄 높이가 한 시계), 위쪽 높이가 달라져도 보던 줄은 화면에서 제자리다(원칙 ⑧).
//
// 그리는 쪽은 layout.rowTop(row) · geo(row) · isVisible(row)만 읽는다 — 흐르는 동안의 값도 그 접근자들이 돌려준다.
// 줄의 내용은 찌그러지지 않고 제자리에 있고, 줄어든 몫 밖은 layout.rowClip(row)으로 자른다(css의 overflow:hidden과 같은 뜻).

import '../motion.dart';
import '../motion_spring.dart';
import 'layout.dart';

/// 한 번 쌓은 결과. 접힌 줄도 자리를 갖는다(높이 0) — 사라진 자리에서 접히고 그 자리에서 펴지게.
class RowStack {
  RowStack({
    required this.tops,
    required this.heights,
    required this.geos,
    required this.live,
    required this.visible,
    required this.trackTop,
    required this.trackHeight,
    required this.total,
  });

  /// 줄의 몫의 위 자리와 높이(배치 px). 접힌 줄의 높이는 0이다.
  final List<double> tops, heights;

  /// 트랙의 위 자리와 높이(위아래 여백 포함). 끈 트랙은 (-1, 0).
  final List<double> trackTop, trackHeight;
  final List<RowGeo> geos;

  /// 그 줄이 보이는가(켠 자료집이고 접히지 않았는가).
  final List<bool> live;

  /// 보이는 줄 번호(위에서부터).
  final List<int> visible;
  final double total;
}

/// 같은 스프링 행렬로 줄 전체가 흐른다. 다시 누르면 현재 자리와 속도를 함께 이어받는다.
class RowFlow {
  RowFlow(RowStack first) : _from = first, _to = first {
    _settle();
  }

  RowStack _from, _to;
  double _elapsed = 0;
  bool _flowing = false;
  MotionToken _token = MotionToken.move;
  final _progress = MotionSpring(0, epsilon: .0005, maxOvershoot: 0);
  List<MotionSpring> _topMotion = [], _heightMotion = [], _trackTopMotion = [], _trackHeightMotion = [];
  final _totalMotion = MotionSpring(0, epsilon: .05, maxOvershoot: 0);

  // 지금 보이는 값. 흐르지 않을 때는 목표의 배열을 그대로 가리킨다(복사하지 않는다).
  late List<double> _tops, _heights, _trackTop, _trackHeight;
  late List<RowGeo> _geos;
  late List<int> _visible;
  late double _total;
  List<double>? _clip;

  RowStack get target => _to;
  bool get flowing => _flowing;
  double get total => _total;
  List<int> get visible => _visible;

  // ---- 흐름을 읽는 쪽(연출)을 위한 값 — 지금 연표의 `_gatherDraw` · `_squash`가 쓰던 것(계약 3-1절) ----
  //
  // 그리는 층은 이 값으로 "줄마다 어디에서 와서 얼마나 왔는가"를 알 수 있다. 줄 안의 것(띠 하나하나 · 사건)을
  // 따로 옮기는 일은 띠의 옛 줄을 아는 쪽(타일 · 층)의 몫이고, 여기는 **줄 단위**만 맡는다.

  /// 이 흐름이 시작될 때마다 오른다 — 그리는 쪽이 '새 전환'을 알아본다(잔상을 다시 붙이지 않게).
  int get version => _version;
  int _version = 0;

  /// 흐른 시간(ms)과 남은 시간(ms).
  double get elapsed => _flowing ? _elapsed : 0;
  double get remain => _flowing ? (Motion.duration(_token) - _elapsed).clamp(0, Motion.duration(_token)) : 0;

  /// 움직임 곡선을 먹인 진행(0~1 · 흐르지 않으면 1) — 줄과 **같은 시계**에 실으려면 이 값을 쓴다.
  double get progress => _flowing ? _progress.value : 1;

  /// 흐르기 전(옛) 값. 흐르지 않을 때는 지금 값과 같다.
  double fromTopOf(int row) => _from.tops[row];
  double fromHeightOf(int row) => _from.heights[row];
  RowGeo fromGeoOf(int row) => _from.geos[row];
  bool wasLiveOf(int row) => _from.live[row];
  double fromTrackTopOf(int index) => _from.trackTop[index];
  double get fromTotal => _from.total;

  /// 목표(새) 값.
  double toTopOf(int row) => _to.tops[row];
  double toHeightOf(int row) => _to.heights[row];

  /// 그 줄이 옮겨 온 거리(옛 자리 − 새 자리 · 배치 px) — 지금 연표 `_gather`의 줄별 `dy`다.
  /// 옛 자리가 없던 줄(새로 난 줄)은 0이고 [bornOf]가 참이다(옮기지 않고 떠오르기만 한다).
  double shiftOf(int row) => _from.live[row] && _to.live[row] ? _from.tops[row] - _to.tops[row] : 0;

  /// 이번 흐름에서 새로 난 줄 · 사라지는 줄.
  bool bornOf(int row) => _to.live[row] && !_from.live[row];
  bool goneOf(int row) => !_to.live[row] && _from.live[row];

  double topOf(int row) => _tops[row];
  double heightOf(int row) => _heights[row];
  RowGeo geoOf(int row) => _geos[row];
  double trackTopOf(int index) => _trackTop[index];
  double trackHeightOf(int index) => _trackHeight[index];

  /// 흐르는 동안 줄의 내용을 자를 높이. 자를 것이 없으면 null.
  double? clipOf(int row) {
    final clip = _clip;
    return clip == null || clip[row] < 0 ? null : clip[row];
  }

  /// 그 줄이 보이는가 — 목표에서 보이거나, 아직 접히는 중이라 남아 있거나.
  bool liveOf(int row) => _to.live[row] || (_flowing && _from.live[row]);

  /// 새 목표. [instant]면(움직임 줄이기 · 첫 쌓기) 흐르지 않고 바로 간다.
  void retarget(RowStack next, {bool instant = false}) {
    if (instant) {
      _from = _to = next;
      _elapsed = 0;
      _flowing = false;
      _settle();
      return;
    }
    // 도중에 목표가 바뀌면 '지금 보이는 값'이 새 출발점이다.
    _begin(_flowing ? _snapshot() : _to, next, preserveVelocity: _flowing);
  }

  /// 출발 자리를 **밖에서 받아** 새 목표로 흐른다 — 저장소를 다시 지어 뼈대가 통째로 바뀔 때(줄 번호 공간이 달라진다)
  /// 옛 뼈대의 자리를 새 번호 공간으로 옮겨 적은 것(`SceneLayout`의 다리)에서 출발한다. 줄 수 · 트랙 수가 다르면 흐르지 않고 바로 간다.
  void retargetFrom(RowStack from, RowStack next, {bool instant = false}) {
    if (instant || from.tops.length != next.tops.length || from.trackTop.length != next.trackTop.length) {
      retarget(next, instant: true);
      return;
    }
    _begin(from, next);
  }

  void _begin(RowStack from, RowStack next, {bool preserveVelocity = false}) {
    _from = from;
    _to = next;
    _elapsed = 0;
    _flowing = _differs();
    if (!_flowing) {
      _settle();
      return;
    }
    _version++;
    _token = next.total < from.total ? MotionToken.snap : MotionToken.move;
    _progress.jump(0);
    _progress.retarget(1, token: _token);
    // 줄은 맞닿아 쌓인 기하이므로 높이를 넘어 튀면 이웃 줄과 부딪힌다.
    // 배열 전체에 같은 식을 쓰되 목표에 닿으면 멎는 제한을 둔다(컴포넌트에는 넘침 허용).
    // 값별 속도는 재입력 때 그대로 두어 여러 줄이 다른 방향으로 바뀌어도 끊기지 않는다.
    _topMotion = _retargetValues(_topMotion, from.tops, next.tops, preserveVelocity);
    _heightMotion = _retargetValues(_heightMotion, from.heights, next.heights, preserveVelocity);
    _trackTopMotion = _retargetValues(_trackTopMotion, from.trackTop, next.trackTop, preserveVelocity);
    _trackHeightMotion = _retargetValues(_trackHeightMotion, from.trackHeight, next.trackHeight, preserveVelocity);
    if (!preserveVelocity) _totalMotion.jump(from.total);
    _totalMotion.retarget(next.total, token: _token);
    _visible = _union();
    // 흐르는 동안 쓸 자리를 한 번만 잡아 두고 장면마다 덮어쓴다(장면마다 쓰레기를 만들지 않게).
    final rows = _to.tops.length, tracks = _to.trackTop.length;
    final buffer = _buffer;
    if (buffer == null || buffer.$1.length != rows || buffer.$4.length != tracks) {
      _buffer = (List<double>.filled(rows, 0), List<double>.filled(rows, 0), List<double>.filled(rows, -1), List<double>.filled(tracks, -1), List<double>.filled(tracks, 0), List<RowGeo>.of(_to.geos));
    }
    _apply();
  }

  /// 흐르는 동안의 (위 자리 · 높이 · 자를 높이 · 트랙 위 자리 · 트랙 높이 · 생김새).
  (List<double>, List<double>, List<double>, List<double>, List<double>, List<RowGeo>)? _buffer;

  List<MotionSpring> _retargetValues(List<MotionSpring> values, List<double> from, List<double> to, bool preserveVelocity) {
    if (values.length != to.length) {
      values = [for (final value in from) MotionSpring(value, epsilon: .05, maxOvershoot: 0)];
      preserveVelocity = false;
    }
    for (var i = 0; i < values.length; i++) {
      if (!preserveVelocity) values[i].jump(from[i]);
      values[i].retarget(to[i], token: _token);
    }
    return values;
  }

  void tick(double dtMs) {
    if (!_flowing || dtMs <= 0) return;
    _elapsed += dtMs;
    final step = MotionStep(_token, dtMs);
    var active = false;
    for (final values in [_topMotion, _heightMotion, _trackTopMotion, _trackHeightMotion]) {
      for (final value in values) {
        value.step(dtMs, sharedStep: step);
        active = active || value.active;
      }
    }
    _totalMotion.step(dtMs, sharedStep: step);
    _progress.step(dtMs, sharedStep: step);
    if (!active && !_totalMotion.active) {
      finish();
      return;
    }
    _apply();
  }

  /// 흐름을 끝까지 보낸다.
  void finish() {
    if (!_flowing) return;
    _flowing = false;
    _from = _to;
    _elapsed = 0;
    _settle();
  }

  /// 흐르지 않는 상태: 목표의 배열을 그대로 보인다.
  void _settle() {
    _tops = _to.tops;
    _heights = _to.heights;
    _geos = _to.geos;
    _trackTop = _to.trackTop;
    _trackHeight = _to.trackHeight;
    _visible = _to.visible;
    _total = _to.total;
    _clip = null;
  }

  bool _differs() {
    if (_from.tops.length != _to.tops.length || _from.trackTop.length != _to.trackTop.length) return false;
    if ((_from.total - _to.total).abs() > .001) return true;
    for (int r = 0; r < _to.tops.length; r++) {
      if ((_from.tops[r] - _to.tops[r]).abs() > .001 || (_from.heights[r] - _to.heights[r]).abs() > .001) return true;
    }
    // 자리는 같아도 트랙이 새로 나거나 사라지면(높이 0 ↔ 제 높이) 흐른다 — 새 DLC의 트랙이 0에서 자라나는 길.
    for (int i = 0; i < _to.trackTop.length; i++) {
      if ((_from.trackHeight[i] - _to.trackHeight[i]).abs() > .001) return true;
    }
    return false;
  }

  /// 보이는 줄: 목표에서 보이는 줄과 아직 접히는 중인 줄을 줄 번호 차례로.
  List<int> _union() {
    final out = <int>[];
    for (int r = 0; r < _to.live.length; r++) {
      if (_to.live[r] || _from.live[r]) out.add(r);
    }
    return out;
  }

  RowStack _snapshot() => RowStack(
    tops: List.of(_tops),
    heights: List.of(_heights),
    geos: List.of(_geos),
    live: List.of(_from.live),
    visible: List.of(_visible),
    trackTop: List.of(_trackTop),
    trackHeight: List.of(_trackHeight),
    total: _total,
  );



  void _apply() {
    final rows = _to.tops.length, tracks = _to.trackTop.length;
    final (tops, heights, clip, trackTop, trackHeight, geos) = _buffer!;
    for (int r = 0; r < rows; r++) {
      clip[r] = -1;
      tops[r] = _topMotion[r].value;
      heights[r] = _heightMotion[r].value.clamp(0, double.infinity);
      // 접히는 줄은 옛 생김새를 그대로 쓰고(내용이 찌그러지지 않게), 펴지는 줄은 새 생김새를 쓴다.
      final geo = _to.live[r] ? _to.geos[r] : (_from.live[r] ? _from.geos[r] : _to.geos[r]);
      final content = _to.live[r] ? _to.heights[r] : (_from.live[r] ? _from.heights[r] : 0.0);
      geos[r] = (geo.height - heights[r]).abs() < .001 ? geo : geo.withHeight(heights[r]);
      if (heights[r] + .01 < content) clip[r] = heights[r];
    }
    for (int i = 0; i < tracks; i++) {
      final a = _from.trackTop[i], b = _to.trackTop[i];
      // 끈 트랙(-1)은 흐르지 않는다.
      trackTop[i] = a < 0 || b < 0 ? b : _trackTopMotion[i].value;
      trackHeight[i] = _trackHeightMotion[i].value.clamp(0, double.infinity);
    }
    _tops = tops;
    _heights = heights;
    _geos = geos;
    _trackTop = trackTop;
    _trackHeight = trackHeight;
    _total = _totalMotion.value;
    _clip = clip;
  }
}

/// 세로 닻(움직임 원칙 ⑧ · 명세 05 6.6): 줄이 접히고 펴져 위쪽 높이가 바뀌어도 보던 줄은 화면에서 움직이지 않는다.
/// 붙잡는 줄은 고른 사건의 줄, 없으면 화면 가운데 줄(가운데보다 위에 있는 줄 가운데 가장 아래 줄)이다.
/// 손으로 끌거나 관성이 도는 동안에는 쉰다 — 멎은 자리가 새 기준이다.
class RowAnchor {
  int row = -1;

  /// 트랙의 위를 붙잡았으면 그 트랙의 번호(아니면 -1) — 트랙을 접고 펼 때는 누른 트랙의 위가 제자리다
  /// (아래가 밀리고 당겨진다 · 지금 연표의 `_pressHold`).
  int track = -1;
  double offset = 0;

  bool get has => row >= 0 || track >= 0;

  void clear() {
    row = -1;
    track = -1;
    offset = 0;
  }

  /// 다시 쌓기 직전에 붙잡을 줄을 잡아 둔다. [preferred]는 고른 사건의 줄(없으면 -1).
  void capture(SceneLayout layout, double viewTop, double bodyHeight, {int preferred = -1}) {
    int pick = preferred >= 0 && preferred < layout.rowCount && layout.isVisible(preferred) ? preferred : _middleRow(layout, viewTop, bodyHeight);
    if (pick < 0) {
      clear();
      return;
    }
    track = -1;
    row = pick;
    offset = layout.rowTop(pick) - viewTop;
  }

  /// 트랙을 접고 펼 때: 그 트랙의 위를 붙잡는다. 그 트랙이 보이지 않으면 아무것도 붙잡지 않는다.
  void captureTrack(SceneLayout layout, double viewTop, int trackIndex) {
    final top = trackIndex >= 0 && trackIndex < layout.tracks.length ? layout.trackTop(trackIndex) : -1;
    if (top < 0) {
      clear();
      return;
    }
    row = -1;
    track = trackIndex;
    offset = top - viewTop;
  }

  /// 화면 가운데에 걸린 줄 — 가운데보다 위에 있는 줄 가운데 가장 아래 줄(js `_autoAnchor` 1829).
  static int _middleRow(SceneLayout layout, double viewTop, double bodyHeight) {
    final mid = viewTop + bodyHeight / 2;
    int best = -1;
    for (final r in layout.visibleRows(0, layout.rowCount - 1)) {
      if (layout.rowTop(r) > mid) break;
      best = r;
    }
    return best;
  }

  /// 붙잡은 줄이 화면에서 제자리에 머물도록 보기를 맞춘다. 맞춘 자리(몸통 좌표)를 돌려준다(닻이 없거나 쉴 때는 null).
  double? keep(SceneLayout layout) {
    if (track >= 0) {
      final top = track < layout.tracks.length ? layout.trackTop(track) : -1;
      if (top < 0) {
        // 붙잡은 트랙이 꺼져 사라졌다 — 닻을 놓는다.
        clear();
        return null;
      }
      return top - offset;
    }
    if (row < 0 || row >= layout.rowCount) return null;
    final top = layout.rowTop(row);
    if (top < 0) {
      // 붙잡은 줄이 접혀 사라졌다 — 닻을 놓는다(js 1877).
      clear();
      return null;
    }
    return top - offset;
  }
}

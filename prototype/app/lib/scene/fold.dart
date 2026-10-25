// 빈 줄 접기의 판단. 보는 기간에 그릴 것이 없는 줄은 접어 높이 0으로 만든다.
// 규칙은 지금 연표의 _foldRows(js:3039) · _settle(js:5130) 그대로다(명세 05 6.1 · 6.4 · 움직임 원칙 ④):
//  · 화면 폭의 25% 안으로 들어오면 펴지고, 75% 밖으로 나가야 접힌다(히스테리시스 — 가장자리에서 부들거리지 않게).
//  · 첫 장면은 이력이 없으니 near만 본다.
//  · 움직이는 동안과 정착을 기다리는 동안은 '펴지기'만 한다. 접힘은 정착 때 한 번에.
//  · 물음은 보기가 폭의 10% 넘게 옮겨졌거나 배율이 바뀌었을 때만 — 장면마다 묻지 않는다.
// 자료 처리부에는 계약 2절의 {"op":"rows_near"}로 묻고, 늦게 온 답은 판 번호로 버린다.

import 'layout.dart';
import 'viewport.dart';

/// 접힘 규칙(순수 로직). [rows]는 볼 수 있는 줄(켠 자료집의 줄)이고, [near] · [far]는 자료 처리부의 답이다.
/// [first]면 이력 없이 near만 본다. [keepOpen]이면 접지 않는다(펴지기만).
Set<int> foldedRowsOf({
  required Iterable<int> rows,
  required Set<int> near,
  required Set<int> far,
  required Set<int> folded,
  required bool first,
  required bool keepOpen,
}) {
  final out = <int>{};
  for (final r in rows) {
    // js: seen = near || (!first && !hidden.has(r) && (keepOpen || !far))  — 여기서 far 집합은 '내용이 있다'는 쪽이다.
    final seen = near.contains(r) || (!first && !folded.contains(r) && (keepOpen || far.contains(r)));
    if (!seen) out.add(r);
  }
  return out;
}

/// 물어볼 범위(분). near = 보기 ± 폭의 25% · far = ± 75% · fade = 미정인 끝을 넓히는 44px의 몫.
class FoldQuery {
  const FoldQuery(this.nearLo, this.nearHi, this.farLo, this.farHi, this.fade);

  factory FoldQuery.of(SceneView v) {
    final perPx = 1 / v.ppm, width = v.plotWidth;
    final near = width * RowFolder.nearMargin * perPx, far = width * RowFolder.farMargin * perPx;
    return FoldQuery(v.lo - near, v.hi + near, v.lo - far, v.hi + far, RowFolder.fadePx * perPx);
  }

  final double nearLo, nearHi, farLo, farHi, fade;

  Map<String, dynamic> toQuery(List<int> packs) => {
    'op': 'rows_near',
    'near': [nearLo.floor(), nearHi.ceil()],
    'far': [farLo.floor(), farHi.ceil()],
    'fade': fade.ceil(),
    'packs': packs,
  };
}

/// 움직임의 갈래 — 정착까지 얼마나 기다리는가(명세 05 6.4).
enum _Motion {
  /// 아무것도 안 하고 있음.
  none,

  /// 관성(놓은 뒤 미끄러짐) — 멎은 장면에 바로 정착.
  coast,

  /// 휠 · 단추 · 키의 미끄러짐 · 돋보기 · 손에 쥠 — 멎고 300ms 뒤.
  slow,
}

/// 빈 줄 접기를 맡는다. 장면마다 [maybeAsk], 시계마다 [tick]을 부르고, 접힘이 달라지면 [onFolded]로 알린다.
class RowFolder {
  RowFolder({required this.layout, required this.ask, required this.onFolded});

  /// 펴지는 여유 · 접히는 여유(화면 폭의 비율) · 미정인 끝을 넓히는 폭(px) · 다시 묻는 문턱(보기 폭의 비율) · 정착을 기다리는 시간(ms).
  static const nearMargin = .25, farMargin = .75, fadePx = 44.0, askShift = .10, settleWait = 300.0;

  final SceneLayout layout;

  /// 자료 처리부에 묻는 길. 없으면(검사 · 옛 저장소) 접지 않는다.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> query)? ask;

  /// 접힘이 달라졌다 — 부르는 쪽이 [SceneLayout.setFolded]에 넣고 닻을 맞춘다. 그리는 중에는 불리지 않는다.
  final void Function(Set<int> folded) onFolded;

  Set<int> _folded = const {};
  Set<int> _near = const {}, _far = const {};
  /// [_first] 이력 없이 near만 보는 첫 셈인가 · [_fresh] 쓸 수 있는 답을 받았는가.
  bool _first = true, _fresh = false;
  int _inflight = 0, _version = 0, _answered = -1;
  double _askedLo = 0, _askedPpm = 0;
  List<int> _askedPacks = const [];

  _Motion _motion = _Motion.none;
  bool _wasMoving = false, _settleDue = false;
  double _settleAt = -1;

  /// 이번 시계에 정착이 일어났는가 — 정착에 함께 실리는 일(자동 조감)이 본다. [tick]의 처음에 지워진다.
  bool settledNow = false;

  Set<int> get folded => _folded;

  /// 답을 기다리는 물음이 있는가.
  bool get asking => _inflight > 0;

  /// 정착을 기다리는 중(그동안은 펴지기만 한다).
  bool get settleWaiting => _settleDue;

  /// 물음도 미뤄 둔 접힘도 없다 — 그림 뜨기 도구가 기다리는 값.
  bool get settled => _inflight == 0 && !_settleDue;

  /// 자료집 조합이 바뀌었다 — 줄 구성이 달라지므로 접힘의 기억을 버리고 처음부터 셈한다(명세 05 6.3).
  void forget() {
    _first = true;
    _folded = const {};
    _near = const {};
    _far = const {};
    _askedPpm = 0;
    // 돌고 있는 물음의 답은 옛 조합의 것이라 버리고(판 번호를 지금까지 올린다), 새 답이 올 때까지는 접지 않는다.
    _answered = _version;
    _fresh = false;
  }

  /// 정착을 예약한다(기본 300ms 뒤). 움직임이 멎는 것은 [tick]이 알아서 보므로, 밖에서 거는 것은
  /// 그 밖의 때(제자리 확대 · 움직임 줄이기에서의 이동)뿐이다.
  void settleSoon(double nowMs, [double delay = settleWait]) {
    _settleDue = true;
    _settleAt = nowMs + delay;
  }

  /// 지금 곧바로 정착한다(멀리 가기의 도착 · 다시 배치 — 기다림 0).
  void settleNow() {
    _settleDue = false;
    _settleAt = -1;
    _keepOpen = false;
    settledNow = true;
    _refold(keepOpen: false);
  }

  /// 보기 상태(접힌 트랙 · 접힌 민족 · 끈 트랙)가 달라졌다 — 물을 줄이 달라졌으니 지금 아는 답으로 그 자리에서 다시 셈한다.
  /// 그래야 트랙을 펴는 그 장면에 이미 접힌 크기로 태어난다(움직임 원칙 ③ — 커졌다 줄어드는 두 단계 금지).
  void recheck() => _refold(keepOpen: _keepOpen);

  /// 저장소를 제자리에서 고쳐 쓰는 동안(엔진 apply — 계약 2-7) 묻지 않고, 돌고 있는 물음의 답도 버린다 — COMMIT 뒤의 답(새 줄 번호)이
  /// 옛 뼈대의 줄을 접지 않게. 지금 접힌 모습은 그대로 둔다. 풀면 다음 장면부터 보던 자리도 다시 묻는다(새 뼈대면 [forget]이 처음부터).
  bool get paused => _paused;
  bool _paused = false;
  set paused(bool value) {
    // 풀 때는 보던 자리여도 다시 묻는다 — 멈춘 동안의 답을 버렸으니(실패로 풀리면 [forget]이 오지 않는다 · 고침 2회차).
    if (_paused && !value) _askedPpm = 0;
    _paused = value;
    if (value) _answered = _version;
  }

  /// 장면을 그리기 직전에. 물어야 할 때만 묻는다 — 알림을 보내지 않는다(그리는 중이므로).
  void maybeAsk(SceneView v, List<int> packs) {
    final call = ask;
    if (call == null || _paused) return;
    final samePacks = packs.length == _askedPacks.length && packs.every(_askedPacks.contains);
    final moved = (v.lo - _askedLo).abs() > v.span * askShift;
    final scaled = _askedPpm == 0 || (v.ppm / _askedPpm - 1).abs() > 1e-6;
    if (samePacks && !moved && !scaled) return;
    // 한 번에 하나만 묻는다. 확대 · 돋보기 도중에는 배율이 장면마다 바뀌어 물음이 장면마다 나가는데, 큰 저장소에서는 물음 하나가 수백 ms라
    // 자료 처리부가 밀려 타일이 굶는다(100만 건에서 돋보기 구간의 타일이 통째로 비던 까닭). 기다리는 동안 바뀐 것은 답이 온 뒤 그때의 보기로 한 번만 다시 묻는다.
    if (_inflight > 0) {
      _again = true;
      _againView = v;
      _againPacks = packs;
      return;
    }
    _askedLo = v.lo;
    _askedPpm = v.ppm;
    _askedPacks = List.of(packs);
    final version = ++_version;
    _inflight++;
    void next() {
      if (!_again) return;
      _again = false;
      final view = _againView, p = _againPacks;
      if (view != null && p != null) maybeAsk(view, p);
    }

    call(FoldQuery.of(v).toQuery(packs)).then((answer) {
      _inflight--;
      next();
      // 늦게 온 답은 버린다 — 그 사이에 더 새 물음이 답을 받았으면(판 번호).
      if (version <= _answered) return;
      _answered = version;
      _near = {for (final r in (answer['near'] as List? ?? const [])) (r as num).toInt()};
      _far = {for (final r in (answer['far'] as List? ?? const [])) (r as num).toInt()};
      _fresh = true;
      _refold(keepOpen: _keepOpen);
    }).catchError((Object _) {
      _inflight--;
      next();
    });
  }

  bool _again = false;
  SceneView? _againView;
  List<int>? _againPacks;

  bool _keepOpen = false;

  /// 시계마다: 움직임을 보고 정착을 셈한다. [moving]은 손 · 관성 · 쫓아가기 · 돋보기 가운데 하나라도 돌고 있는가.
  void tick({required bool moving, required bool coasting, required double nowMs}) {
    settledNow = false;
    if (moving) {
      _motion = coasting ? _Motion.coast : _Motion.slow;
      _settleDue = true;
      _settleAt = -1;
    } else if (_wasMoving) {
      // 관성이 멎은 장면에는 바로, 휠 · 미끄러짐 · 손을 그냥 놓은 뒤에는 300ms.
      _settleAt = nowMs + (_motion == _Motion.coast ? 0 : settleWait);
      _motion = _Motion.none;
    }
    _wasMoving = moving;
    _keepOpen = moving || _settleDue;
    if (_settleAt >= 0 && nowMs >= _settleAt) {
      _settleAt = -1;
      _settleDue = false;
      _keepOpen = false;
      settledNow = true;
      _refold(keepOpen: false);
    }
  }

  /// 지금 아는 답과 지금 상태로 접힘을 다시 낸다. 달라졌으면 알린다.
  void _refold({required bool keepOpen}) {
    if (!_fresh) return;
    final merged = layout.mergedGroups, mergedRows = layout.mergedRows;
    final next = foldedRowsOf(rows: _liveRows(), near: _merge(_near, merged, mergedRows), far: _merge(_far, merged, mergedRows), folded: _folded, first: _first, keepOpen: keepOpen);
    _first = false;
    if (next.length == _folded.length && next.containsAll(_folded)) return;
    _folded = next;
    onFolded(next);
  }

  /// 접힌 민족 줄은 그 묶음의 줄을 모두 품는다 — 묶음 안 어느 줄에든 내용이 있으면 합쳐진 줄에 내용이 있는 것이다.
  /// 대범위 가지는 드는 줄이 번호 차례가 아니라 [SceneLayout.mergedRows]에만 정확히 담긴다(범위로는 빠질 수 있다 — 11물결 stack3 ㈒).
  static Set<int> _merge(Set<int> answer, Map<int, int> merged, Map<int, List<int>> rows) {
    if (merged.isEmpty && rows.isEmpty) return answer;
    Set<int>? out;
    for (final e in merged.entries) {
      if (answer.contains(e.key)) continue;
      for (int r = e.key + 1; r < e.value; r++) {
        if (!answer.contains(r)) continue;
        (out ??= {...answer}).add(e.key);
        break;
      }
    }
    for (final e in rows.entries) {
      if (answer.contains(e.key) || (out?.contains(e.key) ?? false)) continue;
      for (final r in e.value) {
        if (r == e.key || !answer.contains(r)) continue;
        (out ??= {...answer}).add(e.key);
        break;
      }
    }
    return out ?? answer;
  }

  /// 접을 수 있는 줄 — 켠 자료집 · 켠 트랙의 줄 가운데 접힌 트랙 · 접힌 민족에 합쳐진 줄을 뺀 것.
  /// 그 줄들은 어차피 보이지 않으니 접힘을 묻지 않는다(명세 05 5절).
  Iterable<int> _liveRows() sync* {
    for (int i = 0; i < layout.tracks.length; i++) {
      final t = layout.tracks[i];
      // 켜지 않은 집합 보기의 판 트랙은 자리가 없다(그 줄은 켜지 않은 변형의 줄).
      if (layout.isBoardTrack(i) && i != layout.boardTrackIndex) continue;
      if (!layout.isPackEnabled(t.pack) || layout.isTrackOff(t.id) || layout.isTrackFolded(t.id)) continue;
      for (int r = t.firstRow; r < t.firstRow + t.rowCount; r++) {
        if (layout.isMergedAway(r)) continue;
        yield r;
      }
    }
  }
}

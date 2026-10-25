
import 'package:flutter/foundation.dart';

import '../motion.dart';
import '../motion_spring.dart';

// 고르기 · 강조(흐림) · 기간 조명 · 가문 강조 — 그리기 층이 아는 밝기 상태(명세 06 3절의 다섯 가지).
// 앱 틀이 고르기 · 검색 · 상세 창의 말을 듣고 [Emphasis.set]으로 채우고, 층은 장면마다 밝기만 묻는다.
// 번호는 모두 타일의 번호(띠 = periods.id · 사건 = events.id)다 — uid는 조회 명령 `ids_of`로 앱 틀이 바꿔 온다.
// 상태가 바뀌면 지금 밝기에서 새 밝기로 흐른다(밝아짐 200ms · 어두워짐 160ms — 움직임 원칙의 공통 값). 도중에 또 바뀌어도 지금 값에서 이어진다.

/// 기간 조명 하나: 어느 띠의 어느 구간(분). [cell]은 누른 칸 자신('leader:3' …)이면 그 참조 — 그 칸만 더 짙게.
@immutable
class Spot {
  const Spot(this.band, this.start, this.end, {this.cell, this.glow = 1});
  final int band;
  final double start, end;
  final String? cell;

  /// 조명이 얼마나 켜졌는가(0~1의 진행 — 명세 06의 3-3절 `_litState`). 등장은 200ms에 0 → 1,
  /// 물러남은 160ms에 1 → 0이고, 옮길 때 두 구간에 다 드는 곳은 1 그대로다.
  /// 층은 구간 안의 밝기를 **띠의 밝기와 [Emphasis.spotAlpha] 사이에서 이 값으로 섞으면** 된다
  /// (`alpha = bandAlpha + (spotAlpha − bandAlpha) × glow`). 가라앉은 값은 늘 1이라, 아직 읽지 않는 층은 지금과 똑같이 그린다.
  final double glow;

  Spot withGlow(double value) => Spot(band, start, end, cell: cell, glow: value);

  /// 같은 조명인가 — 띠 · 두 끝 · 칸이 같으면 같은 것이다(옮기는 동안 앞뒤를 견주는 열쇠).
  String get key => '$band|$start|$end|${cell ?? ''}';

  /// 이 구간이 [other]를 통째로 품는가(두 구간에 다 드는 곳을 가린다).
  bool covers(Spot other) => band == other.band && start <= other.start && end >= other.end;
}

/// 한 순간의 상태(불변). 밝기 규칙은 css/common.css 328~337줄 그대로.
@immutable
class Look {
  const Look({this.band, this.event, this.row, this.cell, this.bands, this.events, this.echo, this.layout = true, this.lit = false, this.spots = const [], this.house, this.houses, this.figures, this.twins, this.twinBands});

  /// 고른 띠 · 고른 사건(타일의 번호). 고른 사건 · 인물이 놓인 줄은 [row] — 그 줄의 띠와 사건이 덜 어두워진다.
  final int? band, event, row;

  /// 고른 칸의 참조('leader:3' …). 없으면 항목 전체.
  final String? cell;

  /// 강조에 든 띠 · 사건. 둘 다 null이면 강조 없음(흐림 없음).
  final Set<int>? bands, events;

  /// 같은 시기 타국의 사건(메아리) — 강조 밖이어도 흐리지 않는다.
  final Set<int>? echo;

  /// 강조를 사건 이름 배치에도 쓰는가(왕조 · 인물 창의 메아리 강조는 쓰지 않는다).
  final bool layout;

  /// 흐린 띠 안의 조명 구간을 흐리지 않는가.
  final bool lit;
  final List<Spot> spots;

  /// 가문 강조(가문의 id). 연표를 흐리게 하지 않는다 — 그 가문의 칸 · 막대만 진해진다.
  final String? house;

  /// **가문 조명**(확정 설계 1-2 5-3 · 결정 7 A): 조명된 가문 id 묶음 — 누른 가문과 그 아래 파 모두(가문 기록의 `x_under`,
  /// 없으면 `{자기 id}`). 가문 id는 칸 구역 42의 `text2`와 같은 글(`house:` 앞말이 없는 가문 id)이다. null이면 가문 조명이 없다
  /// ([house] 하나만 주던 지금 꼴은 그대로 — 그 가문의 칸만 진해진다).
  ///
  /// 켜지면(앱 틀이 가문 창 · 성씨 창에서 채운다):
  ///  * 그 구간은 [spots]로 **함께** 온다 — 가문 · 성씨 기록의 `x_spots`(`[{uid, start, end}]` 분)를 띠 번호로 바꾼 `Spot(band, start, end)`(cell 없음).
  ///    띠 안에 조명 칠(띠 색 22% — 추정 빗금 위 · 칸 아래)이 깔리고, 맨 위 날짜 칸 아래에 괄호가 선다(메아리 스위치와 상관없이).
  ///  * 구역 42의 가문 id가 이 묶음에 든 칸은 [house]처럼 진해진다([isHouse]).
  ///  * **조명된 띠**(이 상태의 [spots]에 그 띠의 구간이 있는 띠) 안에서 묶음에 들지 않은 **지도자 칸**은 .55([houseCellAlpha]).
  ///    다른 나라 띠 · 사건 · 막대는 흐리지 않는다(가문 창은 고르는 창이 아니다 — [band] · [bands]는 비운다).
  /// 인물 막대 층(`paint/figures.dart`)은 아직 [house]만 읽으므로 앱 틀은 [house]에 누른 가문 id를 함께 싣는다.
  final Set<String>? houses;

  /// 이 가문 id의 칸이 진해지는가(`is-house`) — [house](누른 그 가문) 또는 [houses](파 포함)에 들면. 빈 글은 늘 거짓이다.
  bool isHouse(String id) => id.isNotEmpty && (id == house || (houses?.contains(id) ?? false));

  /// 가문 조명이 켜졌는가([houses]가 있다).
  bool get housed => houses != null;

  /// 가문 조명이 띠 안의 **지도자 칸**에 주는 밝기: 조명된 띠 안에서 [houses]에 들지 않은 칸(가문이 없는 칸 포함)은 .55, 그 밖은 1.
  /// [houseId]는 그 칸의 구역 42 가문 id(없으면 빈 글).
  double houseCellAlpha(int band, String houseId) {
    final hs = houses;
    if (hs == null || isHouse(houseId)) return 1;
    for (final s in spots) {
      if (s.band == band) return Dim.houseOther;
    }
    return 1;
  }

  /// 강조에 든 **uid** 전부(검색 결과 · 창의 조명 — 앱 틀의 `_buildLook`이 `hits`를 그대로 싣는다).
  /// 띠 · 사건처럼 타일의 번호로 가릴 수 없는 것들이 이 묶음으로 `is-match`를 가린다:
  /// 인물 막대(구역 37 `text2`의 첫 칸) · 왕조 칸 · 기관 칸 · 품은 칸 · 대범위. 없으면(null) uid 강조가 없는 것이다.
  final Set<String>? figures;

  /// 이 uid가 강조에 들었는가(`is-match`). 빈 글은 늘 거짓이다.
  bool matchedUid(String uid) => uid.isNotEmpty && (figures?.contains(uid) ?? false);

  /// **같은 사람의 칸**(건의 8의 6-나 · 2026-10-13): 고른 지도자 칸의 사람이 앉은 모든 자리 — `'<띠 번호>|<칸 참조>'`(StripHit.key와 같은 꼴),
  /// 고른 칸 자신도 든다. 칸 층이 이 칸들에 먹 1.5px 테(둥근 6)를 두르고 고름의 .45 흐림에서 뺀다. 같은 사람이 다른 자리에 없으면 null.
  /// 앱 틀이 칸 창의 `x_persons[칸].others`(슬롯 `twins`)를 띠 번호로 바꿔 싣는다. 커서로 올린 칸의 짝은 [SceneMarks.hotTwins]가 따로 싣는다.
  final Set<String>? twins;

  /// 이 칸이 [twins]에 드는가.
  bool isTwin(int band, String ref) => ref.isNotEmpty && (twins?.contains('$band|$ref') ?? false);

  /// [twins]의 띠들 — 같은 사람이 앉은 나라는 고른 나라처럼 흐리지 않는다(같이 하이라이트: 고른 띠 1 · 강조 밖 .2에서도 뺀다).
  final Set<int>? twinBands;

  bool get picked => band != null || event != null;
  bool get filtered => bands != null || events != null;

  double bandAlpha(int id, int bandRow) {
    final twin = twinBands?.contains(id) ?? false;
    if (filtered && !(bands?.contains(id) ?? false) && !twin) return .2;
    if (!picked) return 1;
    return id == band || twin || (row != null && bandRow == row) ? 1 : .58;
  }

  double eventAlpha(int id, int eventRow) {
    if (filtered && !(events?.contains(id) ?? false) && !(echo?.contains(id) ?? false)) return .2;
    if (!picked) return 1;
    if (id == event) return 1;
    return row != null && eventRow == row ? .7 : .45;
  }

  /// 승계선 · 소속선: 고른 것이 있으면 .14, 고른 띠에 닿는 선만 1.
  double linkAlpha(int from, int to) => !picked ? 1 : (band != null && (from == band || to == band)) ? 1 : .14;

  /// 고른 띠에 닿는 승계선은 색만 짙게(평소 짙기 → 1 · css `.tl.is-picked .tl-link.is-selected { opacity: 1 }`): 짙어진 정도 0 또는 1.
  double linkLift(int from, int to) => band != null && (from == band || to == band) ? 1 : 0;

  /// 인물 막대 · 소속 단추 .5(고른 것만 1) — 고른 것이 있을 때만(C:481 · C:1383).
  double get cellDim => picked ? .5 : 1;

  /// **.45 무리**: 한 css 규칙에 묶여 고른 것이 있으면 다 .45가 되는 것들 —
  /// 칸(`.tl-cell` — 지도자 · 내각 · 시기 · 지위) · 기간 막대 · 띠 안 이름(C:370) · 구슬 · 실 · 가장자리(C:861) ·
  /// 알약(C:1141) · 가문 줄(C:1445) · 발효 마름모(C:1491) · 유령선(C:1850).
  /// 강조(`is-filtered`)만으로는 이 무리가 흐려지지 않는다 — 제 규칙이 없어 띠의 밝기를 그대로 물려받는다.
  double get trimDim => picked ? .45 : 1;

  /// 탭 · 조감의 띠 안 이름 · 속국 이름표 · 이름표 이설선(`.tl-tab` C:1187 · `.tl-bnm` C:1781 · `.tl-hang` C:1724 · `.tl-dep-marks` C:1735).
  /// 이것들은 **줄(`.tl-lane`) 직속**이라 띠의 흐림을 물려받지 않는다 — 고른 동안 .5(제 띠만 1 · **같은 줄은 1이 아니다**) ·
  /// 강조 밖 .25(강조에 든 띠는 1)다. [band]는 제 띠(속국 이름표는 그 속국의 띠) 번호이고, 0이면 모름이다.
  double tabAlpha(int band) => markAlpha(
    // 같은 사람이 앉은 나라(건의 8의 6-나)의 탭도 고른 나라의 탭처럼 — 띠가 흐리지 않으므로.
    mine: band != 0 && (band == this.band || (twinBands?.contains(band) ?? false)),
    matched: band != 0 && ((bands?.contains(band) ?? false) || (twinBands?.contains(band) ?? false)),
    pick: Dim.tabPick,
    dim: Dim.tabDim,
  );

  /// 제 상태(`is-selected` · `is-match` · `is-dim`)를 받는 것들의 흐림 — 요소마다 두 값만 다르다(명세 06의 3-1 · 3-2).
  /// 고른 것이 있으면 [pick](고른 것 자신은 1), 강조가 걸리면 [dim](강조에 든 것은 1)이다.
  /// **강조가 고르기를 덮는다** — css에서 `is-filtered` 규칙이 `is-picked` 규칙보다 뒤에 있다(C:1383~1384 · C:969~970).
  double markAlpha({required bool mine, required bool matched, required double pick, required double dim}) {
    if (filtered) return matched ? 1 : dim;
    if (!picked) return 1;
    return mine ? 1 : pick;
  }

  /// 이름표를 잇는 세로 끈(`.tl-hang-link` C:1724): 제 uid가 없어 `is-selected` · `is-dim`이 붙지 않는다 —
  /// 고른 동안은 언제나 .5이고 강조만 걸렸을 때는 흐려지지 않는다.
  double get hangLinkDim => picked ? Dim.tabPick : 1;
}

/// [Look.markAlpha]에 넣는 (고른 동안, 강조 밖)의 짝 — css의 값 그대로다. 요소마다 이 두 값만 다르다.
abstract final class Dim {
  static const tabPick = .5, tabDim = .25; // .tl-tab · .tl-bnm · .tl-hang · .tl-dep-marks (C:1187 · 1724 · 1735 · 1781)
  static const dynPick = .5, dynDim = .25; // .tl-dyn — 왕조 칸(C:969 · 970)
  static const orgPick = .5, orgDim = 1.0; // .tl-org — 기관 칸 · 구역 탭(C:717 · 강조에는 흐림 규칙이 없다)
  static const depPick = 1.0, depDim = .3; // .tl-dep — 품은 칸(C:1730 · 고르기에는 규칙이 없어 띠를 따른다)
  static const figPick = .5, figDim = .2; // .tl-fig — 인물 막대(C:1383 · 1384)
  static const scopePick = 1.0, scopeDim = .45; // .tl-scope — 대범위 테두리(C:1627)

  /// `.tl-cell`(지도자 · 내각 · 시기 · 지위)이 강조에 든 띠 안에서 갖는 밝기(C:1206)와 기간 조명 구간 안의 밝기(C:1321).
  static const cellMatch = .55, litIn = .55;

  /// 가문 조명(결정 7 A)이 켜진 띠 안에서 다른 가문의 지도자 칸 밝기 — 칸 조명 · 고름의 옅기와 같은 값.
  static const houseOther = .55;

  /// 조명 칠(`.tl-spot`)의 짙기 — 띠 색 22%.
  static const spotFill = .22;
}

class Emphasis extends ChangeNotifier {
  static final _byScene = Expando<Emphasis>('밝기 상태');

  /// 그 장면의 밝기 상태(없으면 만든다). 장면의 밭을 늘리지 않으려고 곁에 매단다 — 그리개가 층마다 걸어 주고, 앱 틀의 다리가 [set]한다.
  static Emphasis of(Object scene) => _byScene[scene] ??= Emphasis();

  Look _now = const Look();
  final _from = <(Look, double, double, double)>[]; // 옛 상태 · 시간 · in 응답 · out 응답. 응답은 장면마다 한 번만 셈한다.
  bool reduceMotion = false;

  /// 층이 묶음(배치)을 다시 만들어야 하는지 가리는 번호 — 상태가 바뀔 때마다 오른다.
  int version = 0;

  Look get look => _now;
  bool get active => _from.isNotEmpty || _litMoving || _pending != null;

  void set(Look next) {
    if (!reduceMotion) {
      _from.add((_now, 0, 0, 0));
    } else {
      _from.clear();
    }
    _now = next;
    // 가문 조명이 실어 온 구간을 적어 둔다 — 꺼지며 옅어지는 동안에도 칠할 구간인지 가린다([isHouseSpot]).
    // 가문 조명이 아닌 상태가 같은 구간을 바라면 그것은 더 이상 가문의 것이 아니다.
    if (next.houses != null) {
      for (final s in next.spots) {
        _houseKeys.add(s.key);
      }
    } else {
      for (final s in next.spots) {
        _houseKeys.remove(s.key);
      }
    }
    _wantSpots(next.spots);
    _pruneHouseKeys();
    version++;
    notifyListeners();
  }

  void clear() => set(const Look());

  /// 장면의 시계가 부른다(지난 시간 ms). 밝아짐과 어두워짐의 길이가 달라 값마다 제 길이로 흐르게 진행은 ms로 쌓는다.
  void tick(double dtMs) {
    final flowing = _from.isNotEmpty, lit = _litMoving || _pending != null;
    if (!flowing && !lit) return;
    final dt = dtMs.clamp(0.0, 50.0);
    if (flowing) {
      for (var i = 0; i < _from.length; i++) {
        final elapsed = _from[i].$2 + dt;
        _from[i] = (_from[i].$1, elapsed, 1 - MotionStep(MotionToken.enter, elapsed).xx, 1 - MotionStep(MotionToken.exit, elapsed).xx);
      }
      _from.removeWhere((f) => f.$2 >= Motion.enter * 2);
    }
    if (lit) _tickLit(dt);
    notifyListeners();
  }

  double _flow(double Function(Look) of) {
    var v = _from.isEmpty ? of(_now) : of(_from.first.$1);
    var low = v, high = v;
    for (var i = 0; i < _from.length; i++) {
      final from = of(_from[i].$1), target = i + 1 < _from.length ? of(_from[i + 1].$1) : of(_now);
      if (target < low) low = target;
      if (target > high) high = target;
      final response = target >= from ? _from[i].$3 : _from[i].$4;
      // 목표 변화의 응답을 더한다. 다시 고른 순간 새 항의 위치와 속도가 0이므로
      // 이전 변화에서 얻은 자리와 속도가 끊기지 않는다.
      v += (target - from) * response;
    }
    return v.clamp(low, high);
  }

  double bandAlpha(int id, int row) => _from.isEmpty ? _now.bandAlpha(id, row) : _flow((l) => l.bandAlpha(id, row));
  double eventAlpha(int id, int row) => _from.isEmpty ? _now.eventAlpha(id, row) : _flow((l) => l.eventAlpha(id, row));
  double linkAlpha(int from, int to) => _from.isEmpty ? _now.linkAlpha(from, to) : _flow((l) => l.linkAlpha(from, to));
  double linkLift(int from, int to) => _from.isEmpty ? _now.linkLift(from, to) : _flow((l) => l.linkLift(from, to));
  double get cellDim => _from.isEmpty ? _now.cellDim : _flow((l) => l.cellDim);
  double get trimDim => _from.isEmpty ? _now.trimDim : _flow((l) => l.trimDim);
  double get hangLinkDim => _from.isEmpty ? _now.hangLinkDim : _flow((l) => l.hangLinkDim);
  double tabAlpha(int band) => _from.isEmpty ? _now.tabAlpha(band) : _flow((l) => l.tabAlpha(band));

  /// [Look.houseCellAlpha]를 흐름에 태운 것 — 가문 조명이 켜지면 옅어지는 쪽이라 160ms([Motion.out])에 .55로,
  /// 꺼지면(창을 닫음) 밝아지는 쪽이라 200ms([Motion.enter])에 1로 돌아간다. 가라앉으면 [Look.houseCellAlpha] 그대로다.
  double houseCellAlpha(int band, String houseId) =>
      _from.isEmpty ? _now.houseCellAlpha(band, houseId) : _flow((l) => l.houseCellAlpha(band, houseId));

  /// 가문 조명(`Look.houses`)이 실어 온 구간의 열쇠([Spot.key]) — 켜져 있거나 꺼지며 아직 옅어지는 것만 남는다.
  final _houseKeys = <String>{};

  /// 이 조명 구간이 가문 · 성씨 조명의 것인가 — 띠 안 조명 칠(22%)은 이 구간에만 깐다(칸 · 인물 · 왕조 조명은 지금 그대로 칠이 없다).
  bool isHouseSpot(Spot s) => _houseKeys.isNotEmpty && _houseKeys.contains(s.key);

  /// 다 꺼진 구간의 열쇠를 버린다(지금 바라는 구간이거나 아직 흐르는 구간만 남긴다).
  void _pruneHouseKeys() {
    if (_houseKeys.isEmpty) return;
    _houseKeys.removeWhere((key) {
      if (_lit.containsKey(key)) return false;
      for (final s in _litNow) {
        if (s.key == key) return false;
      }
      for (final s in _pending ?? const <Spot>[]) {
        if (s.key == key) return false;
      }
      return true;
    });
  }

  /// 가문 조명이 켜졌거나, 꺼지며 아직 흐르는 중인가 — 층이 [houseCellAlpha]를 물을지 가린다(물을 일이 없는 장면에서 칸마다 훑지 않게).
  bool get housing {
    if (_now.houses != null) return true;
    for (final f in _from) {
      if (f.$1.houses != null) return true;
    }
    return false;
  }

  /// [Look.markAlpha]를 흐름에 태운 것. `mine` · `matched`는 지금 상태로 가린 값이라 옛 상태에도 그대로 쓴다
  /// (두 값이 바뀌는 순간은 `set`이 불린 순간이고, 그때 흐름이 새로 시작한다).
  double markAlpha({required bool mine, required bool matched, required double pick, required double dim}) => _from.isEmpty
      ? _now.markAlpha(mine: mine, matched: matched, pick: pick, dim: dim)
      : _flow((l) => l.markAlpha(mine: mine, matched: matched, pick: pick, dim: dim));

  /// 고른 사건의 점 배율(1 → 1.25).
  double dotScale(int id) => _from.isEmpty ? (_now.event == id ? 1.25 : 1) : _flow((l) => l.event == id ? 1.25 : 1);

  /// 이 띠의 조명 구간들과, 그 구간의 밝기(흐린 띠 안에서도 1 — [Look.lit]일 때).
  /// 흐르는 동안에는 켜지는 구간과 꺼지는 구간이 함께 나오고, 저마다 [Spot.glow]에 진행(0~1)을 싣고 있다.
  /// 가라앉으면 [Look.spots] 그대로다(glow 1) — 진행을 읽지 않는 층은 지금과 똑같이 그린다.
  Iterable<Spot> spotsOf(int band) => _litNow.where((s) => s.band == band);
  double spotAlpha(int band, int row) => _now.lit ? 1 : bandAlpha(band, row);

  // ──────────────────────────────── 기간 조명의 흐름(명세 06의 3-3 · 움직임-원칙의 '같은 시기를 타국에도') ────────────────────────────────
  //
  //  나타남   바깥 밝기에서 시작해 조명 구간만 200ms에 1로(glow 0 → 1)
  //  옮김     두 구간에 다 드는 곳은 1 그대로 · 새 구간만 지금 밝기에서 200ms에 1로 · 옛 구간만 1에서 160ms에 0으로
  //  되돌아감 (▶ 뒤 곧바로 ◀) 목표만 뒤집어 지금 진행에서 되돌아간다
  //  또 옮김  셋째 칸으로 또 옮기면 이번 옮김이 가라앉은 뒤에 이어서(한 번에 한 옮김)
  //  물러남   조명 구간을 160ms에 0으로 옅히고 다 가라앉으면 보통 띠로

  /// 흐르는 조명들(켜지는 것 · 꺼지는 것). 열쇠는 [Spot.key]다.
  final _lit = <String, _LitSpot>{};

  /// 층에 줄 지금의 조명 — 흐르지 않을 때는 [Look.spots] 그대로(같은 객체)다.
  List<Spot> _litNow = const [];

  /// 지금 흘러가고 있는 목표와 그 직전의 목표(되돌아감을 가린다), 그리고 가라앉은 뒤에 이어 갈 목표.
  List<Spot> _target = const [], _was = const [];
  List<Spot>? _pending;

  bool get _litMoving {
    for (final l in _lit.values) {
      if (!l.settled) return true;
    }
    return false;
  }

  /// 조명이 흐르는 중인가(검사 · 층이 물을 때).
  bool get litMoving => _litMoving || _pending != null;

  void _wantSpots(List<Spot> want) {
    if (reduceMotion) {
      _lit.clear();
      _pending = null;
      _was = _target;
      _target = want;
      _litNow = want;
      return;
    }
    // 한 번에 한 옮김: 흐르는 중에 또 바뀌면 가라앉은 뒤에 잇는다. 다만 곧바로 되돌아가는 것은 목표만 뒤집는다.
    if (_litMoving && !_same(want, _target) && !_same(want, _was)) {
      _pending = want;
      return;
    }
    _pending = null;
    _apply(want);
  }

  void _apply(List<Spot> want) {
    _was = _target;
    _target = want;
    final keys = {for (final s in want) s.key};
    // 나가는 것: 새 구간이 통째로 품는 것은 그 자리를 물려줄 때까지 1로 버티고(두 구간에 다 드는 곳은 그대로),
    // 나머지는 160ms에 0으로 옅어진다.
    for (final entry in _lit.entries) {
      if (keys.contains(entry.key)) continue;
      entry.value.to(0, handover: want.any((s) => s.covers(entry.value.spot)));
    }
    for (final s in want) {
      final had = _lit[s.key];
      if (had != null) {
        had.spot = s;
        had.to(1);
        continue;
      }
      // 이미 밝은 구간이 품고 있던 자리는 1에서 시작한다(새로 밝아지지 않는다).
      final lit = _lit.values.any((l) => l.glow > .99 && l.spot.covers(s));
      _lit[s.key] = _LitSpot(s, lit ? 1 : 0)..to(1);
    }
    _lit.removeWhere((_, l) => l.done);
    _rebuild();
  }

  void _tickLit(double dtMs) {
    // 흐르는 중에 움직임 줄이기가 켜지면 그 자리에서 도착한다.
    if (reduceMotion) {
      _lit.clear();
      final next = _pending;
      _pending = null;
      if (next != null) _target = next;
      _litNow = _target;
      _pruneHouseKeys();
      return;
    }
    for (final l in _lit.values) {
      l.tick(dtMs);
    }
    _lit.removeWhere((_, l) => l.done);
    _rebuild();
    final next = _pending;
    if (next != null && !_litMoving) {
      _pending = null;
      _apply(next);
    }
    _pruneHouseKeys();
  }

  void _rebuild() {
    if (_lit.isEmpty) {
      _litNow = _target;
      return;
    }
    // 가라앉았고 목표 그대로면 [Look.spots]를 그대로 준다(새 목록을 만들지 않는다).
    if (!_litMoving && _lit.length == _target.length) {
      _litNow = _target;
      return;
    }
    _litNow = [for (final l in _lit.values) l.spot.withGlow(l.glow)];
  }

  static bool _same(List<Spot> a, List<Spot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].key != b[i].key) return false;
    }
    return true;
  }
}

/// 흐르는 조명 하나 — 지금 진행([glow])에서 목표(0 또는 1)로 제 길이에 흐른다.
/// [handover]는 새 구간이 통째로 품어 자리를 물려주는 것이다: 새 구간이 다 밝아질 때까지 1로 버티다가 사라진다
/// (두 구간에 다 드는 곳이 잠깐 어두워지지 않게 — 층이 겹친 구간에서 가장 밝은 값을 쓴다).
class _LitSpot {
  _LitSpot(this.spot, double from) : _spring = MotionSpring(from, epsilon: .002, maxOvershoot: 0);
  Spot spot;
  final MotionSpring _spring;
  double _t = 0;
  bool handover = false;
  double get _target => _spring.target;

  double get glow => handover ? (_t >= Motion.enter * 2 ? 0 : 1) : _spring.value.clamp(0.0, 1.0);

  bool get settled => handover ? _t >= Motion.enter * 2 : !_spring.active;

  /// 다 옅어져 더 그릴 것이 없다.
  bool get done => _target == 0 && settled;

  /// 목표를 바꾼다 — 지금 진행에서 이어 간다.
  void to(double target, {bool handover = false}) {
    if (handover) {
      this.handover = true;
      _spring.jump(1);
      _spring.retarget(0, token: MotionToken.exit);
      _t = 0;
      return;
    }
    if (!this.handover && _target == target && !settled) return; // 같은 목표로 다시 걸어도 흐름은 이어진다
    if (this.handover) _spring.jump(glow);
    this.handover = false;
    _spring.retarget(target, token: target >= _spring.value ? MotionToken.enter : MotionToken.exit);
    _t = 0;
  }

  void tick(double dtMs) {
    if (settled) return;
    _t += dtMs;
    if (!handover) _spring.step(dtMs);
  }
}

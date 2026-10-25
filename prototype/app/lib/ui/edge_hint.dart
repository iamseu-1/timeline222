import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../scene/color_mix.dart';
import '../scene/marks.dart';
import '../scene/viewport.dart';
import '../shell/look.dart';
import '../shell/motion_widgets.dart';
import '../shell/parts.dart';
import 'app_bus.dart';
import 'cards.dart';

// 가장자리 안내(명세 06의 4-3): 확대 · 이동 · 접기로 화면이 갑자기 넘어가 방금까지 보던 것이 위 · 아래로 밀려나면
// 그쪽 가장자리에 작은 알약이 떠서 무엇이 밀려났는지 알린다. 누르면 그 줄로 데려가고 도착하면 고리 한 번.
// 값은 지금 연표의 css(.tl-hints · .tl-hint · .th-*)와 js/timeline.js(_visibleUnits · _announce · _showEdgeHint · _goUnit)에서 읽었다.
//
// 밀려난 것의 셈은 순수 함수([pushedOut])로 따로 두었다 — **화면이 아니라 줄 배치(모델)로 센다**.
// 화면을 재면 막 흐르기 시작한 높이를 읽어 틀린다(명세 9절 ㈐ 12).

/// 밀려남을 셈하는 단위 셋.
enum HintKind {
  /// 줄의 대표 정권.
  polity,

  /// 민족(또는 대범위) 묶음.
  people,

  /// 트랙 통째.
  track,
}

/// 밀려남을 셈하는 단위 하나. [key]가 같으면 같은 것이다(움직이기 전후를 이 열쇠로 견준다).
@immutable
class HintUnit {
  const HintUnit({
    required this.key,
    required this.kind,
    required this.name,
    required this.trackId,
    this.trackName = '',
    this.color = Ui.text3,
    this.uid,
    this.row,
    this.groupFirst = 0,
    this.groupCount = 0,
    this.groupWord = '민족',
    this.count = 0,
  });

  final String key;
  final HintKind kind;
  final String name, trackName;
  final int trackId;
  final Color color;

  /// 정권일 때의 항목 열쇠(도착 고리를 걸 곳). 민족 · 트랙에는 없다.
  final String? uid;

  /// 그 단위가 놓인 줄(전체 줄 번호). 트랙이면 없어도 된다.
  final int? row;

  /// 민족 묶음이 품은 줄의 범위(첫 줄 · 줄 수)와 칩에 적을 말('민족' 또는 '대범위').
  final int groupFirst, groupCount;
  final String groupWord;

  /// 민족 묶음이면 함께 밀려난 정권의 수([pushedOut]이 채운다).
  final int count;

  /// 칩에 붙는 작은 글: 정권이면 트랙 이름 · 민족이면 '민족 · n' · 트랙이면 '트랙'.
  String get small => switch (kind) {
    HintKind.polity => trackName,
    HintKind.people => '$groupWord · $count',
    HintKind.track => '트랙',
  };

  /// 풍선의 글.
  String get tip =>
      '$name · ${switch (kind) {
        HintKind.polity => trackName,
        HintKind.people => '$trackName · $groupWord',
        HintKind.track => '트랙',
      }}${count > 0 ? ' · 정권 $count개' : ''} — 여기로 가기';

  HintUnit withCount(int value) => HintUnit(
    key: key,
    kind: kind,
    name: name,
    trackId: trackId,
    trackName: trackName,
    color: color,
    uid: uid,
    row: row,
    groupFirst: groupFirst,
    groupCount: groupCount,
    groupWord: groupWord,
    count: value,
  );

  @override
  bool operator ==(Object other) => other is HintUnit && other.key == key && other.count == count;
  @override
  int get hashCode => Object.hash(key, count);
}

/// 한 판의 배치에서 그 단위가 놓인 자리(몸통 좌표 px). 화면을 잰 값이 아니라 줄 배치(모델)의 값이다.
@immutable
class HintPlacement {
  const HintPlacement(this.unit, this.top, this.height);
  final HintUnit unit;
  final double top, height;
}

/// 밀려난 것 — 위쪽과 아래쪽. 각각 가까운 순으로 늘어놓았고, 넷까지 보이는 것은 그리는 쪽의 몫이다.
@immutable
class EdgeHintReport {
  const EdgeHintReport({this.up = const [], this.down = const []});
  final List<HintUnit> up, down;

  bool get isEmpty => up.isEmpty && down.isEmpty;

  /// 내용이 그대로인지 가리는 값 — 같으면 안내가 다시 등장하지 않는다.
  String get signature => '${up.map((u) => '${u.key}#${u.count}').join(',')}|${down.map((u) => '${u.key}#${u.count}').join(',')}';
}

/// 그 배치에서 화면(세로 [top] ~ [top]+[height])에 보이는 단위의 열쇠 — "보인다"는 겹친 높이 > min(24, 높이/2).
/// 움직이기 전에 이것을 찍어 두었다가([pushedOut]의 before), 멎은 뒤의 배치와 견준다.
Set<String> visibleUnits(Iterable<HintPlacement> at, double top, double height) {
  final bottom = top + height;
  final out = <String>{};
  for (final p in at) {
    final seen = math.min(bottom, p.top + p.height) - math.max(top, p.top);
    if (seen > math.min(24.0, p.height * .5)) out.add(p.unit.key);
  }
  return out;
}

/// 밀려난 것 셈하기 — 순수 함수.
///
/// [before]는 움직이기 전에 보이던 단위의 열쇠, [after]는 **줄 접힘이 다 흐른 뒤의 배치**에서 자리가 있고
/// 그릴 것도 있는 단위들(그 시기에 그릴 것이 없어 사라진 줄은 넣지 않는다 — 밀려난 것이 아니다),
/// [viewTop] · [viewHeight]는 멎은 뒤의 화면(세로)이다.
///
/// 묶기: 트랙이 통째로 밀렸으면 트랙 하나로 · 민족 묶음이 통째로 밀렸고 그 안의 정권이 셋 이상이면 민족 하나로 ·
/// 민족 안의 민족이 함께 밀렸으면 큰 쪽만.
EdgeHintReport pushedOut({required Set<String> before, required Iterable<HintPlacement> after, required double viewTop, required double viewHeight}) {
  final now = visibleUnits(after, viewTop, viewHeight);
  final placed = {for (final p in after) p.unit.key: p};
  final lost = <HintPlacement>[];
  for (final key in before) {
    if (now.contains(key)) continue;
    final at = placed[key];
    if (at == null) continue; // 그 시기에 그릴 것이 없어 사라진 줄
    lost.add(at);
  }
  if (lost.isEmpty) return const EdgeHintReport();

  final trackLost = {
    for (final p in lost)
      if (p.unit.kind == HintKind.track) p.unit.trackId,
  };
  final peoples = [
    for (final p in lost)
      if (p.unit.kind == HintKind.people && !trackLost.contains(p.unit.trackId)) p,
  ];
  final polities = [
    for (final p in lost)
      if (p.unit.kind == HintKind.polity && !trackLost.contains(p.unit.trackId)) p,
  ];

  bool inside(HintPlacement u, HintUnit g) => u.unit.trackId == g.trackId && u.unit.row != null && u.unit.row! >= g.groupFirst && u.unit.row! < g.groupFirst + g.groupCount;
  List<HintPlacement> membersOf(HintUnit g) => [
    for (final u in polities)
      if (inside(u, g)) u,
  ];

  final counts = {for (final g in peoples) g.unit.key: membersOf(g.unit).length};
  final big = <HintPlacement>[];
  for (final g in peoples) {
    final mine = membersOf(g.unit);
    if (mine.length < 3) continue;
    // 더 큰 묶음이 같이 밀렸으면 그쪽만.
    final covered = peoples.any(
      (h) => h.unit.key != g.unit.key && h.unit.trackId == g.unit.trackId && counts[h.unit.key]! >= 3 && counts[h.unit.key]! > mine.length && mine.every((u) => inside(u, h.unit)),
    );
    if (!covered) big.add(g);
  }
  final bigKeys = {for (final g in big) g.unit.key};

  final show = <HintPlacement>[];
  for (final p in lost) {
    final u = p.unit;
    if (u.kind == HintKind.track) {
      show.add(p);
    } else if (u.kind == HintKind.people) {
      if (bigKeys.contains(u.key)) show.add(HintPlacement(u.withCount(counts[u.key]!), p.top, p.height));
    } else if (!trackLost.contains(u.trackId) && !big.any((g) => g.unit.trackId == u.trackId && inside(p, g.unit))) {
      show.add(p);
    }
  }

  final bottom = viewTop + viewHeight;
  final down = [
    for (final p in show)
      if (p.top >= bottom - 24) p,
  ]..sort((a, b) => a.top.compareTo(b.top));
  final up = [
    for (final p in show)
      if (p.top < bottom - 24) p,
  ]..sort((a, b) => b.top.compareTo(a.top));
  return EdgeHintReport(up: [for (final p in up) p.unit], down: [for (final p in down) p.unit]);
}

/// 가장자리 안내 알약. 연표 영역을 덮는 Stack에 그대로 둔다(Positioned.fill).
///
/// 앱 틀이 멎은 뒤 [pushedOut]으로 셈한 [EdgeHintReport]를 `bus.slot(EdgeHint.slot).value`에 넣으면 이 부품이 알린다.
/// 내용이 그대로면 다시 등장하지 않고, 이미 떠 있던 쪽은 제자리에서 내용만 바뀐다. 6초 뒤 스스로 물러난다
/// (손을 올리면 멈추고, 떼면 3.2초).
class EdgeHint extends StatefulWidget {
  const EdgeHint({
    super.key,
    required this.bus,
    this.slotName = slot,
    this.gutter = SceneView.gutter,
    this.axisHeight = SceneView.rulerHeight,
    this.life = const Duration(seconds: 6),
    this.lifeAfterHover = const Duration(milliseconds: 3200),
    this.onGo,
  });

  /// 앱 틀이 밀려남을 알리는 자리의 이름.
  static const slot = 'edge-hint';

  /// 칩은 넷까지, 나머지는 '외 n'.
  static const maxChips = 4;

  /// 알약의 자리: 위는 날짜 칸 아래 10 · 아래는 바닥에서 16 · 좌우 가운데(왼쪽 칸은 뺀다).
  static const above = 10.0, below = 16.0, height = 32.0;

  final AppBus bus;
  final String slotName;
  final double gutter, axisHeight;
  final Duration life, lifeAfterHover;

  /// 칩을 눌렀을 때. 기본은 보던 기간을 그대로 두고 그 줄만 데려오며, 도착하면 고리를 보인다.
  final void Function(HintUnit unit)? onGo;

  @override
  State<EdgeHint> createState() => _EdgeHintState();
}

class _EdgeHintState extends State<EdgeHint> with TickerProviderStateMixin {
  late final SurfaceMotion _up = _make(), _down = _make();
  SurfaceMotion _make() => SurfaceMotion()..addStatusListener(_finished);
  bool _retiring = false;

  void _finished(AnimationStatus status) {
    if (!_retiring || !mounted || !_up.isDismissed || !_down.isDismissed) return;
    setState(() {
      _upList = const [];
      _downList = const [];
      _signature = '';
      _retiring = false;
    });
  }

  List<HintUnit> _upList = const [], _downList = const [];
  String _signature = '';
  Timer? _timer;

  ValueNotifier<Object?> get _slot => widget.bus.slot(widget.slotName);

  @override
  void initState() {
    super.initState();
    _slot.addListener(_read);
    // 세울 때 이미 알릴 것이 있으면 그대로 싣는다(initState에서는 setState를 부르지 않는다).
    final value = _slot.value;
    if (value is EdgeHintReport && !value.isEmpty) {
      _signature = value.signature;
      _upList = value.up;
      _downList = value.down;
      if (_upList.isNotEmpty) _up.forward();
      if (_downList.isNotEmpty) _down.forward();
      _arm(widget.life);
    }
  }

  @override
  void dispose() {
    _slot.removeListener(_read);
    _timer?.cancel();
    _up.dispose();
    _down.dispose();
    super.dispose();
  }

  void _read() {
    final value = _slot.value;
    _apply(value is EdgeHintReport ? value : null);
  }

  void _apply(EdgeHintReport? report) {
    if (report == null || report.isEmpty) {
      _retire();
      return;
    }
    final wasRetiring = _retiring;
    _retiring = false;
    // 물러나는 중 다시 오면 같은 내용도 현재 자리와 속도에서 되돌아온다.
    if (report.signature == _signature && _shown && !wasRetiring) {
      _arm(widget.life);
      return;
    }
    setState(() {
      _signature = report.signature;
      _upList = report.up;
      _downList = report.down;
    });
    // 이미 떠 있던 쪽은 지금 값에서 이어 가므로 제자리에서 내용만 바뀐다.
    for (final (c, list) in [(_up, _upList), (_down, _downList)]) {
      if (list.isEmpty) {
        c.value = 0;
      } else if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        c.value = 1;
      } else {
        c.forward();
      }
    }
    _arm(widget.life);
  }

  bool get _shown => (_upList.isNotEmpty && _up.value > 0) || (_downList.isNotEmpty && _down.value > 0);

  void _arm(Duration after) {
    _timer?.cancel();
    _timer = Timer(after, _retire);
  }

  /// 물러남: 지금 밝기에서 옅어지고, 다 옅어지면 치운다.
  void _retire() {
    _timer?.cancel();
    if (!_shown) return;
    _retiring = true;
    _up.reverse();
    _down.reverse();
  }

  void _go(HintUnit unit) {
    _retire();
    final go = widget.onGo;
    if (go != null) {
      go(unit);
      return;
    }
    // 세로로만 가는 길: 보던 기간은 그대로 두고 그 줄만 데려온다(앱 틀이 스프링으로 옮기고, 도착하면 고리).
    final bus = widget.bus, view = bus.controller.view;
    bus.goTo(view.lo, view.lo + view.span, row: unit.row, fly: false, ring: unit.uid);
    // 트랙 · 민족에는 항목 열쇠가 없다 — 바로 가기라 도착은 이 자리이므로 그 트랙 · 그 줄에 고리를 바로 건다(명세 06의 4-4).
    if (unit.uid == null) {
      final scene = bus.scene;
      SceneMarks.of(scene).showRing(unit.kind == HintKind.track ? SceneRing(track: unit.trackId, at: scene.now) : SceneRing(row: unit.row ?? -1, at: scene.now));
      scene.requestFrame();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_upList.isEmpty && _downList.isEmpty) return const SizedBox.shrink();
    return Stack(
      children: [
        if (_upList.isNotEmpty) Positioned(left: widget.gutter, right: 0, top: widget.axisHeight + EdgeHint.above, child: _pill(_up, _upList, true)),
        if (_downList.isNotEmpty) Positioned(left: widget.gutter, right: 0, bottom: EdgeHint.below, child: _pill(_down, _downList, false)),
      ],
    );
  }

  Widget _pill(SurfaceMotion enter, List<HintUnit> list, bool up) {
    final shown = list.length > EdgeHint.maxChips ? list.sublist(0, EdgeHint.maxChips) : list;
    final rest = list.length - shown.length;
    return AnimatedBuilder(
      animation: enter,
      builder: (context, child) {
        // 200ms 동안 5px 떠오르며 짙어지고, 160ms에 옅어진다.
        final t = enter.value;
        if (t <= 0) return const SizedBox.shrink();
        return IgnorePointer(
          ignoring: _retiring,
          child: ExcludeSemantics(
            excluding: _retiring,
            child: ExcludeFocus(
              excluding: _retiring,
              child: Opacity(
                opacity: enter.opacity,
                child: Transform.translate(offset: Offset(0, (up ? -5 : 5) * (1 - t)), child: child),
              ),
            ),
          ),
        );
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MouseRegion(
            onEnter: (_) => _timer?.cancel(),
            onExit: (_) => _arm(widget.lifeAfterHover),
            child: GlassCard(
              // 뒤 흐림은 css의 blur(18px) — 알약 창(20)도 작은 알약(16)도 아니라 값을 그대로 적는다.
              radius: Ui.controlRadius,
              blur: 18,
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RoundIconButton(
                    size: 24,
                    label: up ? '위로 가기' : '아래로 가기',
                    background: Ui.accent,
                    onPressed: () => _go(shown.first),
                    child: Text(up ? '↑' : '↓', style: const TextStyle(fontSize: 13, height: 1, fontWeight: FontWeight.w700)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 3, right: 4),
                    child: Text(up ? '위로 밀려남' : '아래로 밀려남', style: const TextStyle(fontSize: 11.5, height: 1.35, color: Ui.text3)),
                  ),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final unit in shown) ...[
                          Flexible(
                            child: _HintChip(unit: unit, onPressed: () => _go(unit)),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  ),
                  if (rest > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('외 $rest', style: const TextStyle(fontSize: 12, height: 1.35, color: Ui.text3)),
                    ),
                  RoundIconButton(
                    size: 22,
                    label: '닫기',
                    onPressed: _retire,
                    child: const Text('✕', style: TextStyle(fontSize: 11, height: 1)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 안내의 칩 하나: [색 표시][이름][작은 글]. 색 표시는 정권 = 원 · 민족 = 둥근 네모 · 트랙 = 3×11 세로 막대.
class _HintChip extends StatefulWidget {
  const _HintChip({required this.unit, this.onPressed});
  final HintUnit unit;
  final VoidCallback? onPressed;

  @override
  State<_HintChip> createState() => _HintChipState();
}

class _HintChipState extends State<_HintChip> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final tone = unit.color.toARGB32();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: Tooltip(
        message: unit.tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTap: () {
            setState(() => _down = false);
            widget.onPressed?.call();
          },
          child: Transform.translate(
            // 올리면 1px 떠오르고, 누르면 제자리에서 .97로 들어간다.
            offset: Offset(0, _hover && !_down ? -1 : 0),
            child: Transform.scale(
              scale: _down ? .97 : 1,
              child: Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: Color(mixSrgb(tone, Ui.surface.toARGB32(), _hover ? .30 : .16)), borderRadius: BorderRadius.circular(Ui.innerRadius)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _mark(unit),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        unit.name,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w600, color: Ui.text),
                      ),
                    ),
                    if (unit.small.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Text(
                          unit.small,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(fontSize: 10, height: 1.35, fontWeight: FontWeight.w500, color: Ui.text3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _mark(HintUnit unit) => switch (unit.kind) {
    HintKind.polity => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: unit.color, shape: BoxShape.circle),
    ),
    HintKind.people => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: unit.color, borderRadius: BorderRadius.circular(2)),
    ),
    HintKind.track => Container(
      width: 3,
      height: 11,
      decoration: BoxDecoration(color: unit.color, borderRadius: BorderRadius.circular(2)),
    ),
  };
}

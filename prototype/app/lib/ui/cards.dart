import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../controller.dart';
import '../scene/color_mix.dart';
import '../scene/paint/strips.dart' show CellKind, StripHit, StripLayer;
import '../scene/viewport.dart';
import '../shell/look.dart';
import '../shell/motion_widgets.dart';
import '../motion.dart';
import '../motion_spring.dart';
import '../shell/parts.dart';
import 'app_bus.dart';
import 'date_text.dart' show minutesOfT, rangeText;
import 'detail_cell.dart' show cellToNow;
import 'detail_shell.dart' show detailColor, detailList, detailNum, detailString;

// 묶음 카드(개수 알약의 사건 목록 · 명세 06의 4-1)와 도착 고리(4-4), 성씨 풍선(확정 설계 1-2 5-2 · 결정 6 A — 지도자 칸 · 왕조 칸에 올림).
// 값은 지금 연표의 css(.tl-card · .tc-* · .is-arrived)와 js/timeline.js(_cardHover · showCard · hideCard · _clusterClick · _ringAt)에서 읽었다.
// 부품은 AppBus만 받아 혼자 선다: 목록은 bus.ask({op:'list', …})로 50개씩 받고, 줄을 누르면 bus.select, '이 구간 확대'는 bus.goTo다.

/// 카드의 치수와 시간 — css의 .tl-card · .tc-*. 값을 고칠 일이 있으면 여기만 본다.
abstract final class CardLook {
  /// 폭 288 · 둥근 12 · 뒤 흐림 없음 · 안쪽 여백 8/6/6.
  static const width = 288.0, radius = Ui.menuRadius, blur = 0.0;
  static const padding = EdgeInsets.fromLTRB(6, 8, 6, 6);

  /// 머리: 높이 20(✕ 단추의 크기) · 아래 여백 6 + 1px 선 + 4.
  static const headHeight = 20.0, headGap = 7.0, headPadding = EdgeInsets.fromLTRB(8, 0, 8, 6), headBelow = 4.0;

  /// 줄: 높이 27(위아래 5 + 글 한 줄 17) · 둥근 8 · 칸 사이 8 · 아홉까지(목록의 최대 높이 264는 아홉 줄 243을 넘으므로 닿지 않는다).
  static const rowHeight = 27.0, rowRadius = 8.0, rowGap = 8.0, rowPadding = EdgeInsets.symmetric(horizontal: 8), maxRows = 9;

  /// 발: 위 여백 4 + 줄 20('이 구간 확대' 단추가 위아래 3 + 글 11.5).
  static const footHeight = 20.0, footAbove = 4.0, footPadding = EdgeInsets.symmetric(horizontal: 8);

  /// 여는 때(처음 160 · 이미 열려 있으면 60) · 닫는 때(220) · 열림 180 / 닫힘 150.
  static const hoverFirst = Duration(milliseconds: 160), hoverAgain = Duration(milliseconds: 60), hoverOut = Duration(milliseconds: 220);
  static const enter = Duration(milliseconds: 180), leave = Duration(milliseconds: 150);

  /// 자리: 알약 아래 4(모자라면 위 4) · 오른쪽 끝에서 10 · 바닥에서 8 · 왼쪽 칸에서 6.
  static const anchorGap = 4.0, edgeGap = 10.0, bottomGap = 8.0, gutterGap = 6.0;

  /// 한 번에 받아 오는 쪽수(한 쪽 50개) — 묶음이 이보다 크면 머리의 개수는 알약이 센 수를 쓴다.
  static const pages = 4;

  /// ★(중요도 3)의 색 — css의 --warn(앱 틀의 [Ui.warn]).
  static const star = Ui.warn;
}

/// 개수 알약 하나가 가리키는 통 — 어느 줄의 어느 기간에 사건이 몇 개 묶였는가.
@immutable
class ClusterSpan {
  const ClusterSpan({required this.key, required this.row, required this.lo, required this.hi, required this.count, this.color = Ui.text3});

  /// 같은 묶음인지 가리는 열쇠(타일이 실어 보낸 알약의 자리 따위). 이 값이 같으면 같은 카드다.
  final String key;
  final int row, count;

  /// 묶인 기간(분).
  final double lo, hi;
  final Color color;

  /// 누르면 고정이 아니라 '이 구간 확대'가 되는가 — 묶인 폭이 가장 좁은 보기의 두 배보다 넓을 때(지금 연표의 MIN_SPAN × 2).
  bool get canZoom => hi - lo > TimelineController.minSpan * 2;

  /// 묶음이 풀릴 만큼 확대했을 때의 보기 — 묶인 폭이 화면의 절반이 되게(지금 연표의 _clusterClick).
  (double, double) get zoomView {
    final width = math.max((hi - lo) * 2, TimelineController.minSpan * 3), mid = (lo + hi) / 2;
    return (mid - width / 2, mid + width / 2);
  }

  @override
  bool operator ==(Object other) => other is ClusterSpan && other.key == key;
  @override
  int get hashCode => key.hashCode;
}

/// 알약 위의 손짓을 카드로 옮기는 것: 여는 때 · 닫는 때 · 고정 · "움직이는 중에는 열지 않는다".
/// 화면 부품이 아니라서 시계만으로 검사할 수 있다. 카드를 실제로 그리는 것은 [ClusterCardLayer]다.
class ClusterCardController extends ChangeNotifier {
  ClusterCardController({required this.bus}) {
    bus.controller.active.addListener(_watchMotion);
  }

  final AppBus bus;

  /// 우리가 세로로 옮긴 직후 이만큼은 손 밑의 알약을 열지 않는다.
  static const quiet = Duration(milliseconds: 200);

  ClusterSpan? _cluster;
  Rect? _anchor;
  bool _pinned = false;
  Timer? _timer, _selfTimer;
  (ClusterSpan, Rect)? _missed;
  bool _selfQuiet = false;

  /// 지금 열려 있는 묶음(없으면 null) · 그 알약의 자리 · 고정되었는가.
  ClusterSpan? get cluster => _cluster;
  Rect? get anchor => _anchor;
  bool get pinned => _pinned;

  /// 우리가 세로로 옮겼다(줄 데려오기 · 세로 닻) — 그 뒤 0.2초는 고요하고, 지나면 손 밑의 알약을 그때 연다.
  void markSelfScroll() {
    _selfQuiet = true;
    _selfTimer?.cancel();
    _selfTimer = Timer(quiet, () {
      _selfQuiet = false;
      motionEnded();
    });
  }

  /// 지금은 열지 않는 때인가 — 움직이는 중이거나, 우리가 세로로 옮긴 직후 0.2초.
  bool get isQuiet => bus.controller.moving || _selfQuiet;

  /// 알약 위로 손이 올라오거나(알약과 그 자리) 벗어났다(null).
  void hover(ClusterSpan? next, {Rect? anchor}) {
    _timer?.cancel();
    if (_pinned) return;
    if (next != null && isQuiet) {
      // 멎은 뒤에도 손이 그 위에 있으면 그때 연다(_hoverMissed).
      _missed = (next, anchor ?? Rect.zero);
      return;
    }
    _missed = null;
    if (next != null) {
      if (_cluster == next) {
        if (anchor != null && anchor != _anchor) {
          _anchor = anchor;
          notifyListeners();
        }
        return;
      }
      _timer = Timer(_cluster == null ? CardLook.hoverFirst : CardLook.hoverAgain, () => _show(next, anchor ?? Rect.zero, false));
    } else if (_cluster != null) {
      _timer = Timer(CardLook.hoverOut, close);
    }
  }

  /// 알약을 눌렀다: 묶인 폭이 넓으면 그 구간 확대, 아니면 카드를 고정한다.
  void press(ClusterSpan next, {required Rect anchor}) {
    _timer?.cancel();
    _missed = null;
    if (next.canZoom) {
      close();
      final (lo, hi) = next.zoomView;
      bus.goTo(lo, hi);
      return;
    }
    _show(next, anchor, true);
  }

  /// 손이 카드 위로 올라왔다 · 카드에서 벗어났다.
  void enterCard() => _timer?.cancel();
  void exitCard() {
    if (_pinned) return;
    _timer?.cancel();
    if (_cluster != null) _timer = Timer(CardLook.hoverOut, close);
  }

  void close() {
    _timer?.cancel();
    if (_cluster == null && !_pinned) return;
    _cluster = null;
    _anchor = null;
    _pinned = false;
    notifyListeners();
  }

  /// 움직임이 멎었다 — 그때까지 미뤄 둔 손 밑의 알약을 이제 연다.
  void motionEnded() {
    final missed = _missed;
    if (missed == null || isQuiet) return;
    _missed = null;
    hover(missed.$1, anchor: missed.$2);
  }

  void _watchMotion() {
    if (!bus.controller.active.value) motionEnded();
  }

  void _show(ClusterSpan next, Rect anchor, bool pin) {
    _cluster = next;
    _anchor = anchor;
    _pinned = pin;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _selfTimer?.cancel();
    bus.controller.active.removeListener(_watchMotion);
    super.dispose();
  }
}

/// [ClusterCardController]를 듣고 카드를 띄우고 물리는 층. 연표 영역을 덮는 Stack의 한 자리에 그대로 둔다.
/// 물러나는 150ms 동안 카드를 붙잡아 두는 일도 여기서 한다.
class ClusterCardLayer extends StatefulWidget {
  const ClusterCardLayer({super.key, required this.bus, required this.cards, this.precision = 0, this.gutter = SceneView.gutter, this.balloons});

  final AppBus bus;
  final ClusterCardController cards;

  /// 성씨 풍선의 손짓(지도자 칸 · 왕조 칸 올림). 주지 않으면 이 층이 장면의 '커서가 올라간 칸'([StripLayer.hoverOf])을 듣는 것을 하나 만든다 —
  /// 앱 틀은 이 층을 지금처럼 두기만 하면 풍선이 함께 선다(올림 카드 층 하나 — 확정 설계 1-2 5-2).
  final HouseBalloonController? balloons;

  /// 머리글 기간의 자세함 — 지금 눈금 단위(0 해 · 1 달 · 2 날 · 3 시).
  final int precision;
  final double gutter;

  @override
  State<ClusterCardLayer> createState() => _ClusterCardLayerState();
}

class _ClusterCardLayerState extends State<ClusterCardLayer> {
  ClusterSpan? _shown;
  Rect _anchor = Rect.zero;
  bool _pinned = false;
  bool _leaving = false;

  // 성씨 풍선 — 떠 있는 칸 · 물러나는 중인가(150ms 대신 웹 풍선의 160ms에 옅어지며 걷힘).
  late HouseBalloonController _balloons = widget.balloons ?? HouseBalloonController(bus: widget.bus);
  StripHit? _balloon;
  bool _balloonLeaving = false;

  @override
  void initState() {
    super.initState();
    widget.cards.addListener(_sync);
    _balloons.addListener(_syncBalloon);
    _take(); // 세울 때는 setState를 부르지 않는다.
    _takeBalloon();
  }

  @override
  void didUpdateWidget(ClusterCardLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.cards, widget.cards)) {
      old.cards.removeListener(_sync);
      widget.cards.addListener(_sync);
      _take();
    }
    // 자료 처리부를 다시 열면(새 버스) 풍선의 손짓 · 받아 둔 기록도 새로 — 옛 장면의 알림을 듣지 않게.
    if (!identical(old.balloons, widget.balloons) || (widget.balloons == null && !identical(old.bus, widget.bus))) {
      _balloons.removeListener(_syncBalloon);
      if (old.balloons == null) _balloons.dispose();
      _balloons = widget.balloons ?? HouseBalloonController(bus: widget.bus);
      _balloons.addListener(_syncBalloon);
      _balloon = null;
      _balloonLeaving = false;
      _takeBalloon();
    }
  }

  @override
  void dispose() {
    widget.cards.removeListener(_sync);
    _balloons.removeListener(_syncBalloon);
    if (widget.balloons == null) _balloons.dispose();
    super.dispose();
  }

  void _syncBalloon() => setState(_takeBalloon);

  void _takeBalloon() {
    final next = _balloons.hit;
    if (next == null) {
      _balloonLeaving = _balloon != null;
    } else {
      _balloon = next;
      _balloonLeaving = false;
    }
  }

  void _sync() => setState(_take);

  void _take() {
    final next = widget.cards.cluster;
    if (next == null) {
      _leaving = _shown != null;
    } else {
      _shown = next;
      _anchor = widget.cards.anchor ?? Rect.zero;
      _pinned = widget.cards.pinned;
      _leaving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown, balloon = _balloon;
    if (shown == null && balloon == null) return const SizedBox.shrink();
    final card = shown == null
        ? null
        : ClusterCard(
            key: ValueKey(shown.key),
            bus: widget.bus,
            cluster: shown,
            anchor: _anchor,
            pinned: _pinned,
            precision: widget.precision,
            gutter: widget.gutter,
            leaving: _leaving,
            onEnter: widget.cards.enterCard,
            onExit: widget.cards.exitCard,
            onClose: widget.cards.close,
            onGone: () => setState(() {
              _shown = null;
              _leaving = false;
            }),
          );
    final tip = balloon == null
        ? null
        : HouseBalloon(
            key: ValueKey('balloon|${balloon.key}'),
            bus: widget.bus,
            hit: balloon,
            records: _balloons,
            gutter: widget.gutter,
            leaving: _balloonLeaving,
            onEnter: _balloons.enterCard,
            onExit: _balloons.exitCard,
            onClose: _balloons.close,
            onGone: () => setState(() {
              _balloon = null;
              _balloonLeaving = false;
            }),
          );
    if (tip == null) return card!;
    if (card == null) return tip;
    return Stack(fit: StackFit.expand, children: [card, tip]);
  }
}

/// 묶음 카드 하나. 목록을 받아 오기 전에는 아무것도 그리지 않고(빈 카드가 깜빡이지 않게), 받으면 180ms에 떠오른다.
/// 자리를 스스로 잡으므로 Stack에 그대로 두면 된다(연표 영역만 한 넓이를 받는다).
class ClusterCard extends StatefulWidget {
  const ClusterCard({
    super.key,
    required this.bus,
    required this.cluster,
    required this.anchor,
    this.pinned = false,
    this.precision = 0,
    this.gutter = SceneView.gutter,
    this.leaving = false,
    this.onClose,
    this.onGone,
    this.onEnter,
    this.onExit,
  });

  final AppBus bus;
  final ClusterSpan cluster;

  /// 개수 알약의 자리(연표 영역 안의 좌표).
  final Rect anchor;

  /// 눌러서 고정된 카드는 ✕로만 닫힌다.
  final bool pinned;

  /// 머리글 기간의 자세함(0 해 · 1 달 · 2 날 · 3 시).
  final int precision;
  final double gutter;

  /// 참이 되면 150ms에 옅어지며 2px 내려앉고 [onGone]을 부른다.
  final bool leaving;

  final VoidCallback? onClose, onGone, onEnter, onExit;

  @override
  State<ClusterCard> createState() => _ClusterCardState();
}

class _ClusterCardState extends State<ClusterCard> with TickerProviderStateMixin {
  late final SurfaceMotion _enter = SurfaceMotion();
  List<Map<String, dynamic>>? _items;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    _enter.addStatusListener(_watch);
    _load();
  }

  @override
  void didUpdateWidget(ClusterCard old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) {
      _enter.reverse();
    } else if (!widget.leaving && old.leaving) {
      _enter.forward();
    }
    if (widget.cluster != old.cluster) _load();
  }

  void _watch(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && widget.leaving) widget.onGone?.call();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  /// 그 통의 사건을 50개씩 받는다 — 이미 있는 명령({op:'list'})을 그대로 쓴다.
  /// 켠 변형을 실은 답(계약 2-4절 — 선반 `shelf:` · 소속 펼치기 · 대범위)은 원래 줄이나 도착 줄이 이 줄인 사건을 싣고 줄(`lane`)은 도착 줄이다.
  /// 그래서 숨은 띠의 사건(줄 −1)과 이 줄에서 다른 줄로 떠난 사건(도착 줄 ≠ 이 줄)도 그대로 온다(빼면 나눠 받기의 `has_more` · `next`가
  /// 흔들려서) — 카드는 **줄이 이 묶음의 줄인 것만** 남긴다(과제 7 걸음 4 · 검토 고침). 다음 쪽은 뺀 것까지 센 받은 차례의 끝에서 잇는다.
  Future<void> _load() async {
    final serial = ++_serial;
    final c = widget.cluster;
    final out = <Map<String, dynamic>>[];
    int after = 0;
    try {
      for (int page = 0; page < CardLook.pages; page++) {
        final data = await widget.bus.ask({'op': 'list', 'lo': c.lo.round(), 'hi': c.hi.round(), 'lane': c.row, 'lanes': 1, 'after': after});
        final items = (data['items'] as List?) ?? const [];
        for (final raw in items) {
          final item = Map<String, dynamic>.from(raw as Map);
          if (_onRow(item, c.row)) out.add(item);
        }
        if (items.isEmpty || data['has_more'] != true) break;
        after = ((data['next'] ?? (items.last as Map)['id']) as num).toInt();
      }
    } catch (_) {
      if (mounted && serial == _serial) widget.onClose?.call();
      return;
    }
    if (!mounted || serial != _serial) return;
    // 차례: 시작 → 중요도 내림차순. 둘 다 같으면 받은 차례 그대로(자바스크립트의 안정 정렬과 같게 — 번호를 함께 들고 견준다).
    final indexed = [for (int i = 0; i < out.length; i++) (i, out[i])];
    indexed.sort((a, b) {
      final at = _startOf(a.$2).compareTo(_startOf(b.$2));
      if (at != 0) return at;
      final by = _importanceOf(b.$2).compareTo(_importanceOf(a.$2));
      return by != 0 ? by : a.$1.compareTo(b.$1);
    });
    setState(() => _items = [for (final e in indexed) e.$2]);
    if (out.isEmpty) {
      widget.onClose?.call();
    } else if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  /// 목록 답의 사건 하나가 이 묶음의 줄 [row]에 그려지는가 — 답의 줄(`lane` — 켠 변형이면 도착 줄)이 [row]. 숨은 띠의 사건(−1 — 계약 2-4절
  /// '숨는 띠' · 엔진 `variant::HIDDEN_ROW`)과 다른 줄로 떠난 사건은 아니다. 줄이 없는 옛 답은 그대로 둔다.
  static bool _onRow(Map<String, dynamic> item, int row) => item['lane'] is! num || (item['lane'] as num).toInt() == row;

  static double _startOf(Map<String, dynamic> item) => ((item['start'] ?? 0) as num).toDouble();
  static int _importanceOf(Map<String, dynamic> item) => ((item['importance'] ?? 2) as num).toInt();

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final shown = items.length > CardLook.maxRows ? items.sublist(0, CardLook.maxRows) : items;
    final total = widget.cluster.count > shown.length ? widget.cluster.count : items.length;
    final rest = total - shown.length;
    final foot = rest > 0 || widget.cluster.canZoom;
    final height =
        CardLook.padding.vertical +
        CardLook.headHeight +
        CardLook.headPadding.bottom +
        1 +
        CardLook.headBelow +
        shown.length * CardLook.rowHeight +
        (foot ? CardLook.footAbove + CardLook.footHeight : 0);

    return LayoutBuilder(
      builder: (context, box) {
        final width = math.min(CardLook.width, box.maxWidth - 20);
        final left = _clamp(widget.anchor.center.dx - width / 2, widget.gutter + CardLook.gutterGap, box.maxWidth - width - CardLook.edgeGap);
        double top = widget.anchor.bottom + CardLook.anchorGap;
        final above = top + height > box.maxHeight - CardLook.bottomGap;
        if (above) top = widget.anchor.top - height - CardLook.anchorGap;
        return Stack(
          children: [
            Positioned(
              left: left,
              top: math.max(4, top),
              width: width,
              height: height,
              child: AnimatedBuilder(
                animation: _enter,
                builder: (context, child) {
                  // 열림 180ms(4px 미끄러지며 .985배에서) · 닫힘 150ms(투명도 + 2px 내려앉음).
                  final t = _enter.value;
                  final dy = (above ? 6 : -6) * (1 - t);
                  return Opacity(
                    opacity: _enter.opacity,
                    child: Transform.translate(
                      offset: Offset(0, dy),
                      child: Transform.scale(scale: .95 + .05 * t, child: child),
                    ),
                  );
                },
                child: MouseRegion(
                  onEnter: (_) => widget.onEnter?.call(),
                  onExit: (_) => widget.onExit?.call(),
                  child: GlassCard(
                    radius: CardLook.radius,
                    blur: CardLook.blur,
                    shadow: Ui.shadow,
                    padding: CardLook.padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _head(total),
                        for (final item in shown) _CardRow(bus: widget.bus, item: item, fallback: widget.cluster.color, onPicked: widget.onClose),
                        if (foot) _foot(rest),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 머리: [색 점 8][사건 n개][기간] + 고정이면 ✕. 기간은 지금 눈금 단위만큼 자세히 적는다.
  Widget _head(int total) {
    final c = widget.cluster;
    final from = stampAt(c.lo, widget.precision), to = stampAt(c.hi, widget.precision);
    return Container(
      height: CardLook.headHeight + CardLook.headPadding.bottom + 1,
      margin: const EdgeInsets.only(bottom: CardLook.headBelow),
      padding: CardLook.headPadding,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ui.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: CardLook.headGap),
          Text(
            '사건 $total개',
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w700, color: Ui.text),
          ),
          const SizedBox(width: CardLook.headGap),
          Expanded(
            child: Text(
              from == to ? from : '$from ~ $to',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, height: 1.35, color: Ui.text3),
            ),
          ),
          if (widget.pinned) ...[
            const SizedBox(width: CardLook.headGap),
            RoundIconButton(
              size: 20,
              label: '닫기',
              onPressed: widget.onClose,
              child: const Text('✕', style: TextStyle(fontSize: 11, height: 1)),
            ),
          ],
        ],
      ),
    );
  }

  /// 발: [외 n개] [⤢ 이 구간 확대].
  Widget _foot(int rest) => Padding(
    padding: CardLook.footPadding.add(const EdgeInsets.only(top: CardLook.footAbove)),
    child: SizedBox(
      height: CardLook.footHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rest > 0 ? '외 $rest개' : '', style: const TextStyle(fontSize: 11, height: 1.35, color: Ui.text3)),
          if (widget.cluster.canZoom)
            _ZoomButton(
              onPressed: () {
                final (lo, hi) = widget.cluster.zoomView;
                widget.onClose?.call();
                widget.bus.goTo(lo, hi);
              },
            ),
        ],
      ),
    ),
  );

  static double _clamp(double value, double lo, double hi) => value.clamp(lo, math.max(lo, hi));
}

/// 카드의 한 줄: [점 7][날짜 11][제목][★]. 누르면 그 사건을 고른다(창이 열린다).
class _CardRow extends StatefulWidget {
  const _CardRow({required this.bus, required this.item, required this.fallback, this.onPicked});
  final AppBus bus;
  final Map<String, dynamic> item;
  final Color fallback;
  final VoidCallback? onPicked;

  @override
  State<_CardRow> createState() => _CardRowState();
}

class _CardRowState extends State<_CardRow> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final id = (item['id'] as num?)?.toInt();
    final uid = (item['uid'] as String?) ?? '';
    final picked = widget.bus.selection.value;
    final selected = picked != null && ((uid.isNotEmpty && picked.uid == uid) || (id != null && picked.eventId == id));
    final rawColor = (item['color'] as num?)?.toInt();
    final color = rawColor == null || rawColor == 0 ? widget.fallback : Color(0xff000000 | rawColor);
    final look = (item['look'] as num?)?.toInt() ?? 0;
    final star = _CardRowState._importance(item) >= 3;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTap: () {
          setState(() => _down = false);
          widget.onPicked?.call();
          widget.bus.select(uid, kind: 'event', eventId: id);
        },
        child: Transform.scale(
          // 눌림: 카드의 줄은 .97로 살짝 들어간다(움직임 원칙의 '작용과 반작용').
          scale: _down ? .97 : 1,
          child: Container(
            height: CardLook.rowHeight,
            padding: CardLook.rowPadding,
            decoration: BoxDecoration(
              color: selected ? Color(withAlpha(Ui.accent.toARGB32(), .16)) : (_hover ? Ui.accentSoft : const Color(0x00000000)),
              borderRadius: BorderRadius.circular(CardLook.rowRadius),
            ),
            child: Row(
              children: [
                // css의 .tc-dot에는 조약(is-treaty) 규칙이 없어 지금 연표도 동그라미로 그린다 — 여기서도 동그라미다.
                SizedBox(
                  width: 8,
                  child: Center(
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  ),
                ),
                const SizedBox(width: CardLook.rowGap),
                Text(
                  cardWhen(item['label'] as String?, _CardRowState._start(item), startUnknown: look & (1 << 22) != 0),
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(fontSize: 11, height: 1.35, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                const SizedBox(width: CardLook.rowGap),
                Expanded(
                  child: Text(
                    '${item['title'] ?? ''}',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, height: 1.35, color: Ui.text),
                  ),
                ),
                if (star) ...[const SizedBox(width: CardLook.rowGap), const Text('★', style: TextStyle(fontSize: 10, height: 1.35, color: CardLook.star))],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double _start(Map<String, dynamic> item) => ((item['start'] ?? 0) as num).toDouble();
  static int _importance(Map<String, dynamic> item) => ((item['importance'] ?? 2) as num).toInt();
}

class _ZoomButton extends StatefulWidget {
  const _ZoomButton({this.onPressed});
  final VoidCallback? onPressed;
  @override
  State<_ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<_ZoomButton> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() {
      _hover = false;
      _down = false;
    }),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        setState(() => _down = false);
        widget.onPressed?.call();
      },
      child: Transform.scale(
        scale: _down ? .97 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: _hover ? Ui.accentSoft : const Color(0x00000000), borderRadius: BorderRadius.circular(6)),
          child: const Text(
            '⤢ 이 구간 확대',
            style: TextStyle(fontSize: 11.5, height: 1, fontWeight: FontWeight.w600, color: Ui.accent),
          ),
        ),
      ),
    ),
  );
}

/// 작은 동그란 아이콘 단추(카드의 ✕ 20 · 안내의 ✕ 22) — 앱 틀의 ShellButton은 높이가 32라 여기에는 쓰지 못한다.
class RoundIconButton extends StatefulWidget {
  const RoundIconButton({super.key, required this.size, required this.child, this.label, this.onPressed, this.color = Ui.text3, this.background});
  final double size;
  final Widget child;
  final String? label;
  final VoidCallback? onPressed;
  final Color color;

  /// 늘 깔려 있는 바탕(안내의 ↑ ↓ 단추). 없으면 올렸을 때만 surface-2가 깔린다.
  final Color? background;

  @override
  State<RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<RoundIconButton> {
  bool _hover = false, _down = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() {
      _hover = false;
      _down = false;
    }),
    child: Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTap: () {
          setState(() => _down = false);
          widget.onPressed?.call();
        },
        child: Transform.scale(
          scale: _down ? .97 : 1,
          child: Container(
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: widget.background ?? (_hover ? Ui.surface2 : const Color(0x00000000)), shape: BoxShape.circle),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: widget.background != null ? const Color(0xffffffff) : (_hover ? Ui.text : widget.color)),
              child: widget.child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 도착 고리 — 멀리 가서 닿은 뒤 한 번(600ms)만 옅어지는 고리. [trigger]가 새 값으로 바뀔 때마다 앞 고리를 걷고 처음부터.
/// 옅어지기만 하므로 '동작 줄이기'에서도 그대로 그린다(css의 .is-arrived와 같다).
class ArrivalRing extends StatefulWidget {
  const ArrivalRing({super.key, required this.child, this.trigger, this.radius = 0, this.inset = 0, this.color = Ui.accent, this.fill});

  static const duration = Duration(milliseconds: 600);

  final Widget child;

  /// 이 값이 바뀌면(그리고 null이 아니면) 고리를 한 번 보인다.
  final Object? trigger;

  /// 고리의 모서리 · 몸통에서 얼마나 안으로(양수) · 밖으로(음수) 그릴 것인가. 띠는 0(띠 밖으로 넘치지 않는다), 사건 점은 -5.
  final double radius, inset;
  final Color color;

  /// 트랙에 걸 때의 옅은 칠(css의 accent 7%). 없으면 고리만.
  final Color? fill;

  @override
  State<ArrivalRing> createState() => _ArrivalRingState();
}

class _ArrivalRingState extends State<ArrivalRing> with SingleTickerProviderStateMixin {
  late final MotionAnimation _ring = MotionAnimation(enter: MotionToken.ring, maxOvershoot: 0);

  @override
  void initState() {
    super.initState();
    if (widget.trigger != null) _ring.forward(from: 0);
  }

  @override
  void didUpdateWidget(ArrivalRing old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger != null) _ring.forward(from: 0);
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ring,
    builder: (context, child) => CustomPaint(
      foregroundPainter: ArrivalRingPainter(
        // 고리는 1에서 0으로 옅어진다(css의 arrive-ring · --ease).
        opacity: _ring.isDismissed ? 0 : 1 - _ring.value.clamp(0.0, 1.0),
        radius: widget.radius,
        inset: widget.inset,
        color: widget.color,
        fill: widget.fill,
      ),
      child: child,
    ),
    child: widget.child,
  );
}

/// 고리를 그리는 붓 — [opacity]가 1에서 0으로 내려간다(검사가 이 값을 읽는다).
class ArrivalRingPainter extends CustomPainter {
  ArrivalRingPainter({required this.opacity, required this.radius, required this.inset, required this.color, this.fill});
  final double opacity, radius, inset;
  final Color color;
  final Color? fill;

  static const stroke = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final box = (Offset.zero & size).deflate(inset);
    if (box.isEmpty) return;
    final corner = BorderRadius.circular(radius + (inset < 0 ? -inset : 0));
    if (fill != null) {
      canvas.drawRRect(corner.toRRect(box), Paint()..color = Color(withAlpha(fill!.toARGB32(), opacity)));
    }
    // 테두리는 상자 안쪽에 그어 띠 밖으로 넘치지 않는다(css의 inset box-shadow).
    canvas.drawRRect(
      corner.toRRect(box.deflate(stroke / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Color(withAlpha(color.toARGB32(), .75 * opacity)),
    );
  }

  @override
  bool shouldRepaint(ArrivalRingPainter old) => old.opacity != opacity || old.radius != radius || old.inset != inset || old.color != color || old.fill != fill;
}

/// 한 시점을 그 자세함만큼 적는다(0 해 · 1 달 · 2 날 · 3 시) — 앱 틀의 rangeLabel과 같은 표기다.
String stampAt(double minute, int precision) {
  final d = DateTime.fromMillisecondsSinceEpoch((minute * 60000).floor(), isUtc: true);
  final out = StringBuffer(d.year > 0 ? '${d.year}년' : '기원전 ${1 - d.year}년');
  if (precision >= 1) out.write(' ${d.month}월');
  if (precision >= 2) out.write(' ${d.day}일');
  if (precision >= 3) out.write(' ${d.hour}시');
  return out.toString();
}

/// 카드 줄의 날짜 글 — 적힌 날짜 글([label])만큼 자세히, 다만 **날까지만** 적는다(지금 연표의 showCard와 같다).
/// 시작이 미정이면 '미정'.
String cardWhen(String? label, double start, {bool startUnknown = false}) {
  if (startUnknown) return '미정';
  final text = label ?? '';
  return stampAt(start, text.contains('일') ? 2 : (text.contains('월') ? 1 : 0));
}

// ════════════════════════════════════════════════════════════════════════════════════════════
//  성씨 풍선 — 확정 설계 1-2 5-2 · 결정 6 A (웹 js/timeline.js `_tipHover` · `_tipHTML` · `_showTip` · css `.tl-htip`과 같은 꼴)
//
//  지도자 칸 · 왕조 칸에 마우스를 올리면 칸 아래 8px에 묶음 카드와 같은 유리 카드:
//    머리 = 이름 · 기간 / 원어 한 줄 / 줄 = 성씨 · 본관 · 가문(가문 색 점 · 파면 본가 길) · 왕조 / 칸의 메모 / 바닥 = 누르는 길 한 줄.
//  없는 줄은 뺀다. 띠 높이는 그대로(연표 위에 뜸)이고, 화면 끝에서는 화면 안으로 비킨다(아래 자리가 없으면 칸 위).
//  가문 줄을 누르면 가문 창(가문 조명 — `house:<id>`), 성씨 줄을 누르면 성씨 창(`surname:<id>`). 풍선의 다른 곳은 누름을 받지 않는다.
//  값은 칸 구역 42의 가문 id로 가문 기록을, 띠 번호로 정권 기록을 자료 처리부에 묻는다(새 조회 없음 — `uid_of` · `entity`).
//  어디서 손짓을 듣나: 칸 층이 장면을 그린 뒤 `StripLayer.hoverOf(scene)`에 커서가 올라간 칸(자리 · 가문)을 싣는다 —
//  이 파일의 [ClusterCardLayer]가 그것을 듣는 [HouseBalloonController]를 스스로 만든다(앱 틀은 고치지 않아도 된다).
// ════════════════════════════════════════════════════════════════════════════════════════════

/// 풍선의 치수와 시간 — 웹 css `.tl-htip`(min 200 · max 340 · 안쪽 9/12/10 · 둥근 14 · 뒤 흐림 22 · 글 12.5 / 1.5).
abstract final class BalloonLook {
  static const minWidth = 200.0, maxWidth = 340.0, radius = 14.0, blur = 22.0;
  static const padding = EdgeInsets.fromLTRB(12, 9, 12, 10);

  /// 칸과의 틈 8 · 칸 왼쪽에서 8 앞 · 왼쪽 칸에서 6 · 오른쪽 끝에서 10 · 위아래 끝에서 8(위로 뒤집을 때는 날짜 칸 아래 4).
  static const gap = 8.0, gutterGap = 6.0, edgeGap = 10.0, bottomGap = 8.0, topGap = 4.0;

  /// 머리(이름 13.5 굵게 · 기간 11.5) 아래 6 + 1px 선 + 6, 줄 사이 3 · 이름표와 값 사이 12, 가문 점 9(값과 6), 메모 위 6, 바닥 위 7.
  static const headGap = 8.0, headBelow = 6.0, rowGap = 3.0, colGap = 12.0, dot = 9.0, dotGap = 6.0, noteAbove = 6.0, footAbove = 7.0;

  /// 나타남 200ms(4px 미끄러지며 — css htip-in) · 물러남 160ms(웹 `--t-out`).
  static const enter = Duration(milliseconds: 200), leave = Duration(milliseconds: 160);

  static const base = TextStyle(fontSize: 12.5, height: 1.5, color: Ui.text);
  static const name = TextStyle(fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w700, color: Ui.text);
  static const sub = TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3);
  static const when = TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3, fontFeatures: [FontFeature.tabularFigures()]);
  static const native = TextStyle(fontSize: 12, height: 1.5, color: Ui.text2);
  static const label = TextStyle(fontSize: 12, height: 1.5, color: Ui.text3);
  static const note = TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text2);
  static const foot = TextStyle(fontSize: 11.5, height: 1.5, color: Ui.text3);
}

/// 풍선 줄 하나 — [label] 성씨 · 본관 · 가문 · 왕조, [text] 값, [dot] 가문 색 점, [open] 누르면 열 항목(uid · 갈래 — 없으면 누를 수 없음).
@immutable
class BalloonRow {
  const BalloonRow(this.label, this.text, {this.dot, this.open, this.kind = ''});
  final String label, text;
  final Color? dot;
  final String? open;
  final String kind;
}

/// 풍선의 글(웹 `_tipHTML`이 짓는 것). [rows]가 비면 머리 · 바닥만.
/// [sub]는 머리 아래 옅은 한 줄(지도자의 묘호 · 시호 · 이름 · 지위 — 웹 `.ht-sub`), [native]는 원어 한 줄(`.ht-names`).
@immutable
class BalloonData {
  const BalloonData({required this.head, this.when = '', this.sub = '', this.native = '', this.rows = const [], this.notes = const [], this.foot = ''});
  final String head, when, sub, native, foot;
  final List<BalloonRow> rows;
  final List<String> notes;

  /// 가문 줄이 있는가 — 바닥 글에 '가문을 누르면 가문 조명'을 붙인다.
  bool get hasHouse => rows.any((r) => r.label == '가문');
}

/// 지도자 칸 · 왕조 칸 위의 손짓을 풍선으로 옮기는 것: 여는 때(처음 160 · 이미 열림 60) · 닫는 때(220) · 풍선 위에 손이 있으면 닫지 않음 ·
/// 움직이는 동안은 열지 않고 열린 것도 걷는다(칸이 풍선 밑에서 달아나지 않게 — 멎은 뒤 손이 그 위면 그때 연다).
/// 화면 부품이 아니라 시계만으로 검사할 수 있다. 정권 · 가문 기록도 여기서 받아 둔다(같은 띠의 칸을 옮겨 다닐 때 다시 묻지 않게).
class HouseBalloonController extends ChangeNotifier {
  HouseBalloonController({required this.bus, ValueListenable<StripHit?>? source}) : source = source ?? StripLayer.hoverOf(bus.scene) {
    this.source.addListener(_onSource);
    bus.controller.active.addListener(_watchMotion);
    // 손이 이미 칸 위에 있는 채로 세워졌으면(층을 다시 세움) 그 칸부터.
    if (this.source.value != null) _onSource();
  }

  final AppBus bus;

  /// 커서가 올라간 칸(칸 층이 장면마다 싣는다).
  final ValueListenable<StripHit?> source;

  StripHit? _hit;
  Timer? _timer;
  bool _overCard = false;

  /// 지금 떠 있는 풍선의 칸(없으면 null).
  StripHit? get hit => _hit;

  /// 풍선이 서는 칸인가 — 지도자 칸 · 왕조 칸(칸 참조가 있는 것).
  static bool wants(StripHit? h) => h != null && (h.kind == CellKind.leader || h.kind == CellKind.dynasty) && h.ref.isNotEmpty;

  void _onSource() => hover(source.value);

  /// 칸 위로 손이 올라오거나(그 칸) 벗어났다(null).
  void hover(StripHit? next) {
    if (!wants(next)) next = null;
    _timer?.cancel();
    if (next != null && bus.controller.moving) {
      // 움직이는 동안은 고요 — 떠 있던 풍선도 그 자리에서 걷는다.
      close();
      return;
    }
    if (next != null) {
      final now = _hit;
      if (now != null && now.key == next.key) {
        if (now.rect != next.rect) {
          _hit = next; // 같은 칸이 자리만 옮겼다(줄 접기 따위) — 따라간다
          notifyListeners();
        }
        return;
      }
      _timer = Timer(now == null ? CardLook.hoverFirst : CardLook.hoverAgain, () => _show(next!));
    } else if (_hit != null && !_overCard) {
      _timer = Timer(CardLook.hoverOut, close);
    }
  }

  /// 손이 풍선 위로 올라왔다 · 풍선에서 벗어났다.
  void enterCard() {
    _overCard = true;
    _timer?.cancel();
  }

  /// 풍선에서 벗어나면 220ms 뒤에 닫는다 — 그 사이 손이 그 칸으로 돌아가면(칸 층이 다시 알림) 닫지 않는다.
  void exitCard() {
    _overCard = false;
    _timer?.cancel();
    if (_hit != null) _timer = Timer(CardLook.hoverOut, close);
  }

  void close() {
    _timer?.cancel();
    _overCard = false;
    if (_hit == null) return;
    _hit = null;
    notifyListeners();
  }

  void _watchMotion() {
    if (bus.controller.active.value) {
      _timer?.cancel();
      close();
    } else {
      hover(source.value);
    }
  }

  void _show(StripHit next) {
    if (bus.controller.moving) return;
    _hit = next;
    notifyListeners();
  }

  // ── 기록 받아 두기 ─────────────────────────────────────────────────────────────────────────

  final _records = <String, Future<Map<String, dynamic>?>>{};
  final _bandUids = <int, Future<String?>>{};

  /// 항목 기록(`{"op":"entity"}`의 json을 푼 것). 없거나 못 받으면 null. 서른 개가 넘으면 처음부터 다시 모은다.
  Future<Map<String, dynamic>?> record(String uid) {
    if (_records.length > 30) _records.clear();
    return _records[uid] ??= () async {
      try {
        final answer = await bus.ask({'op': 'entity', 'uid': uid});
        final raw = answer['json'];
        final v = raw is String ? jsonDecode(raw) : raw;
        return v is Map ? v.cast<String, dynamic>() : null;
      } catch (_) {
        return null;
      }
    }();
  }

  /// 띠 번호 → 그 띠(정권)의 uid(계약 2-1의 `uid_of`).
  Future<String?> bandUid(int band) {
    if (_bandUids.length > 60) _bandUids.clear();
    return _bandUids[band] ??= () async {
      try {
        final answer = await bus.ask({'op': 'uid_of', 'kind': 'band', 'id': band});
        final uid = answer['uid'];
        return uid is String && uid.isNotEmpty ? uid : null;
      } catch (_) {
        return null;
      }
    }();
  }

  @override
  void dispose() {
    _timer?.cancel();
    source.removeListener(_onSource);
    bus.controller.active.removeListener(_watchMotion);
    super.dispose();
  }
}

/// 지도자의 다른 이름들을 한 줄로 — 풍선 머리 아래 옅은 줄(웹 `_tipHTML`의 facts · `HT.leaderFull`과 같은 말): 묘호 · 시호 · 이름 · 지위.
String leaderFacts(Map<String, dynamic> c) {
  final rank = detailString(c, 'rank').isNotEmpty ? detailString(c, 'rank') : detailString(c, 'rankAuto');
  return [
    if (detailString(c, 'temple').isNotEmpty) '묘호 ${detailString(c, 'temple')}',
    if (detailString(c, 'title').isNotEmpty) '시호 ${detailString(c, 'title')}',
    if (detailString(c, 'given').isNotEmpty) '이름 ${detailString(c, 'given')}',
    if (rank.isNotEmpty) '지위 $rank',
  ].join(' · ');
}

/// 이름 줄(`x_names` · `x_cellNames[ref]` = `{main: [{text, lang?, tag?}], other}`)의 앞 이름들을 한 줄로 — 웹 `namesSplit(names).main`.
String balloonNative(Object? xNames) {
  if (xNames is! Map) return '';
  final main = xNames['main'];
  if (main is! List) return '';
  return [
    for (final n in main)
      if (n is Map && n['text'] is String && (n['text'] as String).isNotEmpty) '\u2068${n['text']}\u2069',
  ].join(' · ');
}

/// 본가 길을 짧게 — 넷 이상이면 `뿌리 › … › 위 › 저`(웹 `_tipHTML`).
String balloonChain(List<String> names) {
  if (names.length > 3) return [names.first, '…', names[names.length - 2], names.last].join(' › ');
  return names.join(' › ');
}

/// 풍선의 글을 짓는다 — 웹 `_tipHTML`과 같은 차례 · 같은 글. 정권 기록을 못 받으면 칸에 실린 이름만으로 짓고, 그것도 없으면 null.
Future<BalloonData?> loadBalloon(HouseBalloonController records, StripHit hit) async {
  String head = '', when = '', sub = '', native = '', houseId = hit.houseId, dynName = '';
  final notes = <String>[];
  String foot;
  final bandUid = await records.bandUid(hit.band);
  final p = bandUid == null ? null : await records.record(bandUid);
  final ref = hit.ref, cut = ref.indexOf(':');
  final index = cut < 0 ? -1 : int.tryParse(ref.substring(cut + 1)) ?? -1;
  if (hit.kind == CellKind.leader) {
    final leaders = p == null ? const <Map<String, dynamic>>[] : detailList(p, 'leaders');
    final c = index >= 0 && index < leaders.length ? leaders[index] : null;
    if (c != null) {
      // 머리는 이름 · 기간(목업 결정 6 A) — 묘호 · 시호 · 이름 · 지위는 그 아래 옅은 한 줄.
      head = detailString(c, 'name').isNotEmpty ? detailString(c, 'name') : hit.name;
      sub = leaderFacts(c);
      final startAt = detailString(c, 'startAt'), endAt = detailString(c, 'endAt');
      when = rangeText(
        start: detailNum(c, 'start')?.toDouble(),
        startAt: startAt.isEmpty ? null : startAt,
        end: detailNum(c, 'end')?.toDouble(),
        endAt: endAt.isEmpty ? null : endAt,
        startUnknown: c['startUnknown'] == true,
        endUnknown: c['endUnknown'] == true,
        ongoing: cellToNow(p!, c),
      );
      if (houseId.isEmpty) houseId = detailString(c, 'houseId');
      dynName = detailString(c, 'dynasty');
      if (dynName.isEmpty) dynName = detailString(c, 'dynastyAuto');
      if (dynName.isEmpty) dynName = _dynastyAt(p, detailNum(c, 'start')?.toDouble());
      final cellNames = p['x_cellNames'];
      native = balloonNative(cellNames is Map ? cellNames[ref] : null);
      if (detailString(c, 'note').isNotEmpty) notes.add(detailString(c, 'note'));
    } else {
      head = hit.name;
    }
    foot = '누르면 그 칸';
  } else {
    final y = hit.uid.isEmpty ? null : await records.record(hit.uid);
    head = y == null ? hit.name : detailString(y, 'name');
    if (head.isEmpty) head = hit.name;
    // 그 띠의 다스림 줄(정권 기록 `x_dynasties` — 왕조 uid가 같은 것). 여러 번 다스렸으면 칸의 순번(`dynasty:i`)이 가리키는 줄.
    final rows = p == null
        ? const <Map<String, dynamic>>[]
        : [
            for (final d in detailList(p, 'x_dynasties'))
              if (detailString(d, 'uid') == hit.uid) d,
          ];
    final all = p == null ? const <Map<String, dynamic>>[] : detailList(p, 'x_dynasties');
    final d = index >= 0 && index < all.length && detailString(all[index], 'uid') == hit.uid ? all[index] : (rows.isEmpty ? null : rows.first);
    if (d != null) {
      when = detailString(d, 'when');
      if (detailString(d, 'note').isNotEmpty) notes.add(detailString(d, 'note'));
    }
    if (y != null) {
      if (houseId.isEmpty) houseId = detailString(y, 'houseId');
      native = balloonNative(y['x_names']);
      if (houseId.isEmpty && detailString(y, 'house').isNotEmpty) notes.insert(0, '본가 왕조 ${detailString(y, 'house')}');
    }
    foot = '누르면 그 왕조';
  }
  if (head.isEmpty) return null;

  final rows = <BalloonRow>[];
  final h = houseId.isEmpty ? null : await records.record('house:$houseId');
  if (h != null) {
    // 성씨 · 본관은 저부터 본가 쪽으로 처음 만나는 것(파는 본가의 것을 물려받는다 — 웹과 같음).
    final path = [
      for (final id in (h['path'] is List ? h['path'] as List : const []))
        if (id is String) id,
    ];
    final up = <Map<String, dynamic>>[h];
    for (final id in path.reversed) {
      if (id == houseId) continue;
      final r = await records.record('house:$id');
      if (r != null) up.add(r);
    }
    final sur = up.where((r) => detailString(r, 'surname').isNotEmpty).firstOrNull;
    final seat = up.where((r) => detailString(r, 'seat').isNotEmpty).firstOrNull;
    if (sur != null) {
      final sn = sur['x_surname'] is Map ? (sur['x_surname'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
      final text = detailString(sn, 'name').isNotEmpty ? detailString(sn, 'name') : detailString(sur, 'surname');
      final uid = detailString(sn, 'uid');
      rows.add(BalloonRow('성씨', text, open: uid.isEmpty ? null : uid, kind: 'surname'));
    }
    if (seat != null) rows.add(BalloonRow('본관', detailString(seat, 'seat')));
    final chain = [for (final x in detailList(h, 'x_path')) detailString(x, 'name')];
    final name = chain.length > 1 ? balloonChain(chain) : detailString(h, 'name');
    rows.add(BalloonRow('가문', name, dot: detailColor(h['color'], Color(hit.houseColor == 0 ? 0xff666666 : hit.houseColor)), open: 'house:$houseId', kind: 'house'));
  } else if (houseId.isNotEmpty && hit.houseName.isNotEmpty) {
    rows.add(BalloonRow('가문', hit.houseName, dot: Color(hit.houseColor == 0 ? 0xff666666 : hit.houseColor), open: 'house:$houseId', kind: 'house'));
  }
  if (dynName.isNotEmpty) rows.add(BalloonRow('왕조', dynName));
  final lit = rows.any((r) => r.label == '가문');
  return BalloonData(head: head, when: when, sub: sub, native: native, rows: rows, notes: notes, foot: lit ? '$foot · 가문을 누르면 가문 조명' : foot);
}

/// 그 해(시작)에 이 정권을 다스린 왕조의 이름 — 적은 왕조가 없는 지도자 칸의 `dynastyAuto` 대신(정권 기록 `x_dynasties`의 구간).
String _dynastyAt(Map<String, dynamic>? p, double? start) {
  if (p == null || start == null) return '';
  final at = minutesOfT(start);
  for (final d in detailList(p, 'x_dynasties')) {
    final span = d['span'];
    if (span is List && span.length == 2 && span[0] is num && span[1] is num && (span[0] as num) <= at && at < (span[1] as num)) return detailString(d, 'name');
  }
  return '';
}

/// 성씨 풍선 하나. 글을 받아 오기 전에는 아무것도 그리지 않고(빈 풍선이 깜빡이지 않게), 받으면 200ms에 떠오른다.
/// 자리를 스스로 잡으므로 연표 영역만 한 Stack에 그대로 두면 된다 — 칸 아래 8px(모자라면 칸 위), 칸 왼쪽에서 8px 앞, 연표 안으로 비킴.
class HouseBalloon extends StatefulWidget {
  const HouseBalloon({
    super.key,
    required this.bus,
    required this.hit,
    required this.records,
    this.gutter = SceneView.gutter,
    this.leaving = false,
    this.onEnter,
    this.onExit,
    this.onClose,
    this.onGone,
  });

  final AppBus bus;

  /// 올린 칸 — 자리 [StripHit.rect]는 배치 px(돋보기 배율을 곱해 이 층의 자리로 옮긴다).
  final StripHit hit;

  /// 기록을 받아 두는 곳(손짓을 맡은 것과 같다).
  final HouseBalloonController records;
  final double gutter;

  /// 참이 되면 160ms에 옅어지고 [onGone]을 부른다.
  final bool leaving;
  final VoidCallback? onEnter, onExit, onClose, onGone;

  @override
  State<HouseBalloon> createState() => _HouseBalloonState();
}

class _HouseBalloonState extends State<HouseBalloon> with SingleTickerProviderStateMixin {
  late final SurfaceMotion _enter = SurfaceMotion();
  BalloonData? _data;
  int _serial = 0;
  bool _above = false;

  @override
  void initState() {
    super.initState();
    _enter.addStatusListener(_watch);
    _load();
  }

  @override
  void didUpdateWidget(HouseBalloon old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) {
      _enter.reverse();
    } else if (!widget.leaving && old.leaving) {
      _enter.forward();
    }
  }

  void _watch(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && widget.leaving) widget.onGone?.call();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final serial = ++_serial;
    final data = await loadBalloon(widget.records, widget.hit);
    if (!mounted || serial != _serial) return;
    if (data == null) {
      widget.onClose?.call();
      return;
    }
    setState(() => _data = data);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  void _open(String uid, String kind) {
    widget.onClose?.call();
    widget.bus.select(uid, kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final mag = widget.bus.controller.view.mag;
    final r = widget.hit.rect;
    final anchor = Rect.fromLTRB(r.left * mag, r.top * mag, r.right * mag, r.bottom * mag);
    final head = widget.bus.controller.view.head * mag;
    return CustomSingleChildLayout(
      delegate: _BalloonPlace(anchor, gutter: widget.gutter * mag, head: head, onSide: (above) => _above = above),
      child: AnimatedBuilder(
        animation: _enter,
        builder: (context, child) {
          // 나타남: 4px 미끄러지며(아래에 뜨면 위에서, 위에 뜨면 아래에서) · 물러남: 그 자리에서 옅어짐(웹 hideTip의 opacity).
          final t = _enter.value;
          final dy = (_above ? 6 : -6) * (1 - t);
          return Opacity(
            opacity: _enter.opacity,
            child: Transform.translate(offset: Offset(0, dy), child: child),
          );
        },
        child: MouseRegion(
          onEnter: (_) => widget.onEnter?.call(),
          onExit: (_) => widget.onExit?.call(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: BalloonLook.minWidth, maxWidth: BalloonLook.maxWidth),
            child: IntrinsicWidth(
              child: GlassCard(
                radius: BalloonLook.radius,
                blur: BalloonLook.blur,
                shadow: Ui.shadow,
                padding: BalloonLook.padding,
                child: DefaultTextStyle.merge(style: BalloonLook.base, child: _body(data)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BalloonData data) {
    // 머리 아래 옅은 줄 · 원어 줄은 웹처럼 위로 2px 당겨 붙는다(css `margin: -2px 0 6px`) — 앞 것의 아래 여백을 2px 줄여 같은 자리.
    final lines = [if (data.sub.isNotEmpty) (data.sub, BalloonLook.sub), if (data.native.isNotEmpty) (data.native, BalloonLook.native)];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: BalloonLook.headBelow),
          margin: EdgeInsets.only(bottom: lines.isEmpty ? BalloonLook.headBelow : BalloonLook.headBelow - 2),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Ui.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(data.head, style: BalloonLook.name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
              ),
              if (data.when.isNotEmpty) ...[const SizedBox(width: BalloonLook.headGap), Text(data.when, style: BalloonLook.when, maxLines: 1, softWrap: false)],
            ],
          ),
        ),
        for (int i = 0; i < lines.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < lines.length - 1 ? BalloonLook.headBelow - 2 : BalloonLook.headBelow),
            child: Text(lines[i].$1, style: lines[i].$2, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
          ),
        if (data.rows.isNotEmpty)
          Table(
            columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (int i = 0; i < data.rows.length; i++)
                TableRow(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(right: BalloonLook.colGap, top: i == 0 ? 0 : BalloonLook.rowGap),
                      child: Text(data.rows[i].label, style: BalloonLook.label, maxLines: 1, softWrap: false),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : BalloonLook.rowGap),
                      child: _value(data.rows[i]),
                    ),
                  ],
                ),
            ],
          ),
        for (int i = 0; i < data.notes.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? BalloonLook.noteAbove : 0),
            child: Text(data.notes[i], style: BalloonLook.note),
          ),
        if (data.foot.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: BalloonLook.footAbove),
            child: Text(data.foot, style: BalloonLook.foot, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }

  Widget _value(BalloonRow row) {
    final text = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (row.dot != null) ...[
          Container(
            width: BalloonLook.dot,
            height: BalloonLook.dot,
            decoration: BoxDecoration(color: row.dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: BalloonLook.dotGap),
        ],
        Flexible(child: Text(row.text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis)),
      ],
    );
    final open = row.open;
    if (open == null) return Align(alignment: Alignment.centerLeft, child: text);
    return Align(
      alignment: Alignment.centerLeft,
      child: _BalloonLink(onTap: () => _open(open, row.kind), child: text),
    );
  }
}

/// 풍선의 가문 · 성씨 줄 — 누를 수 있다(올리면 밑줄 · 손가락 모양). 웹 `.ht-link`.
class _BalloonLink extends StatefulWidget {
  const _BalloonLink({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_BalloonLink> createState() => _BalloonLinkState();
}

class _BalloonLinkState extends State<_BalloonLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: DefaultTextStyle.merge(
        style: TextStyle(decoration: _hover ? TextDecoration.underline : TextDecoration.none, decorationColor: Ui.text),
        child: widget.child,
      ),
    ),
  );
}

/// 풍선의 자리(웹 `_showTip`): 가로는 칸 왼쪽에서 8px 앞 — 왼쪽 칸에서 6 · 오른쪽 끝에서 10 안으로, 세로는 칸 아래 8px —
/// 아래가 모자라고 위에 자리가 있으면 칸 위 8px(날짜 칸 아래 4px보다 위로는 가지 않는다).
class _BalloonPlace extends SingleChildLayoutDelegate {
  _BalloonPlace(this.anchor, {required this.gutter, required this.head, required this.onSide});
  final Rect anchor;
  final double gutter, head;
  final void Function(bool above) onSide;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: math.max(0, constraints.maxWidth - gutter - BalloonLook.gutterGap - BalloonLook.edgeGap), maxHeight: constraints.maxHeight);

  @override
  Offset getPositionForChild(Size size, Size child) {
    final lo = gutter + BalloonLook.gutterGap, hi = math.max(lo, size.width - child.width - BalloonLook.edgeGap);
    final left = (anchor.left - BalloonLook.gap).clamp(lo, hi);
    var top = anchor.bottom + BalloonLook.gap;
    var above = false;
    if (top + child.height > size.height - BalloonLook.bottomGap && anchor.top - BalloonLook.gap - child.height >= head + BalloonLook.topGap) {
      top = anchor.top - BalloonLook.gap - child.height;
      above = true;
    }
    onSide(above);
    return Offset(left, math.max(head + BalloonLook.topGap, top));
  }

  @override
  bool shouldRelayout(_BalloonPlace old) => old.anchor != anchor || old.gutter != gutter || old.head != head;
}

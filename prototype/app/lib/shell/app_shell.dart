import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../motion_spring.dart';
import 'motion_widgets.dart';
import 'app_menu.dart';
import 'detail_panel.dart';
import 'dock.dart';
import 'filter_sheet.dart';
import 'look.dart';
import 'mag_pill.dart';
import 'zoom_buttons.dart';

// 앱 틀: 지금 연표와 같은 모습으로 연표가 창 전체를 쓰고 그 위에 부품이 떠 있다.
//   창 맨 위 60px  — 바탕(#f4eee4)에 알약 창(기간 글 · 검색 칸 · ☰ 필터 · ⋯)이 뜬다(집중 모드면 0으로 줄어 연표가 화면 전체를 쓴다)
//   그 아래        — 연표(맨 위에 1px 선). 오른쪽 아래에 확대 단추 묶음과 배율 알약, 고를 때만 오른쪽에 상세 창.
//   알약 창 아래   — 검색 결과 목록 · 필터 시트 · 작은 알약(측정 중 안내 · 기간 재기)
// 자료 처리부를 알지 못한다: 목록 · 상세 창 · 시트의 속은 부르는 쪽이 위젯으로 넘긴다.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    required this.timeline,
    required this.searchController,
    this.searchFocus,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.searchResults,
    this.onCloseResults,
    this.detail,
    this.detailOpen,
    this.detailBare = false,
    this.detailFoot,
    this.onCloseDetail,
    this.stageOverlay,
    this.filterSheet,
    this.filterOpen,
    this.onFilterOpen,
    this.dockButtons = const <Widget>[],
    this.layers = const <Widget>[],
    this.menuItems = const <AppMenuItem>[],
    this.onMenu,
    this.onBird,
    this.notice,
    this.dockAfterFilter = const <Widget>[],
    this.stageBottomInset,
    this.pills = const <Widget>[],
    this.float,
    this.topLeft,
    this.top = Ui.top,
    this.ownKeys = true,
    this.frozen = false,
  });

  /// 오른쪽 아래 확대 묶음의 조감 단추(V와 같은 명령).
  final VoidCallback? onBird;

  final TimelineController controller;

  /// 연표 몸통(전용 그리기). 창 폭 전체를 쓴다.
  final Widget timeline;

  final TextEditingController searchController;
  final FocusNode? searchFocus;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;

  /// 알약 창 아래로 내려오는 목록. null이면 내려오지 않는다.
  final Widget? searchResults;
  final VoidCallback? onCloseResults;

  /// 상세 창의 내용. null이면 창이 아예 없고 연표가 창 폭 전체를 쓴다.
  final Widget? detail;

  /// 상세 창이 **열려 있는가**. 주지 않으면 `detail != null`로 본다.
  /// 늘 걸려 있는 부품(`DetailHost`)을 넣을 때는 내용을 늘 주고 이 값으로 여닫는다.
  final bool? detailOpen;

  /// 상세 창의 머리 · 여백을 속이 스스로 그리는가(`DetailHost(framed: false)`).
  final bool detailBare;

  /// 상세 창 맨 아래에 붙는 줄(원문 단추).
  final Widget? detailFoot;
  final VoidCallback? onCloseDetail;

  /// 상세 창과 같은 자리에 겹쳐 놓을 것(같은 해 보기 창).
  final Widget? stageOverlay;

  /// 필터 시트의 속. 주지 않으면 시트가 빈 채로 열린다.
  final Widget? filterSheet;

  /// 시트가 열려 있는가 — 주면 밖에서 다스린다(기억과 한 값으로 두려고).
  final bool? filterOpen;
  final ValueChanged<bool>? onFilterOpen;

  /// 독의 `☰ 필터` 앞에 서는 단추들(집합 보기의 `🗂` 단추).
  final List<Widget> dockButtons;

  /// 독 위에 겹쳐 놓을 층(독 단추에 매달리는 목록 — 닫혀 있으면 빈 것). 독보다 나중에 그려 단추의 고리를 따른다.
  final List<Widget> layers;

  /// `⋯` 메뉴의 줄(간단한 메뉴를 쓸 때).
  final List<AppMenuItem> menuItems;

  /// `⋯`가 부를 것. 주면 [menuItems] 대신 이것으로 연다.
  final Future<void> Function(BuildContext buttonContext)? onMenu;

  /// 알약 창 아래 작은 알약에 띄울 글(측정 중 안내 · 알림 한 줄). null이면 없다.
  final String? notice;

  /// 독의 `☰ 필터` 다음에 서는 단추들(렌즈의 `◎ 렌즈`).
  final List<Widget> dockAfterFilter;

  /// 연표 아래쪽을 차지한 창(단체 계보 창 — 감독 선택 D5 결정 4 A)의 높이를 연표 영역의 높이에서 셈하는 길. 확대 단추와 상세 칸이 그만큼 위로 비켜
  /// 창과 겹치지 않는다(웹 `.stage.has-gtree .zoom-controls` · `.detail`의 `--gt-h`). 창이 없으면 null(또는 0을 돌려준다).
  final double Function(double stageHeight)? stageBottomInset;

  /// 그 줄에 함께 서는 다른 알약(기간 재기의 결과 알약).
  final List<Widget> pills;

  /// 떠 있는 것(알약 창 · 필터 시트)을 감싸는 껍데기 — 집중 모드에서 위로 물러나게 할 때 쓴다.
  final Widget Function(Widget child)? float;

  /// 창 왼쪽 위 (8, 8)에 놓을 것(집중 모드 나가기 단추).
  final Widget? topLeft;

  /// 맨 위 바탕 띠의 높이. 집중 모드면 0으로 줄인다(400ms).
  final double top;

  /// 틀이 Esc와 `/`를 스스로 맡는가. 단축키 부품(`ui/shell_keys.dart`)을 함께 쓸 때는 거짓으로 둔다 —
  /// 그 둘은 그 부품에도 있어 같은 키가 두 번 실행되기 때문이다(명세 9 ㈐-20).
  /// `0`(전체 보기)은 연표도 그 부품도 맡지 않으므로 늘 여기서 받는다.
  final bool ownKeys;

  /// 참이면 틀의 부품이 입력을 받지 않는다 — 측정 중에 사람 손이 장면을 바꾸지 않게.
  final bool frozen;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  final _searchLink = LayerLink();
  late final MotionAnimation _detailMotion = MotionAnimation(maxOvershoot: 6 / Ui.detailWidth);
  late final MotionAnimation _topMotion = MotionAnimation(value: widget.top, maxOvershoot: 0);
  Widget? _lastResults;

  /// 연표를 감싸는 초점 묶음. 떠 있는 창이 닫히면 여기로 초점을 돌려 준다(연표의 `+ - ← →`가 다시 듣게).
  final _timelineScope = FocusScopeNode(debugLabel: '연표');
  FocusNode? _ownSearchFocus;
  bool _filterOpenLocal = false;

  FocusNode get _searchFocus => widget.searchFocus ?? (_ownSearchFocus ??= FocusNode(debugLabel: '검색'));

  /// 검사와 뒤의 작업자가 읽는 값: 필터 시트가 열려 있는가.
  bool get filterOpen => widget.filterOpen ?? _filterOpenLocal;

  /// 상세 창이 열려 있는가.
  bool get _detailOpen => widget.detail != null && (widget.detailOpen ?? true);

  @override
  void initState() {
    super.initState();
    if (widget.ownKeys) HardwareKeyboard.instance.addHandler(_escape);
    if (_detailOpen) _detailMotion.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      // 실제 상세 위치는 이 공유 값을 읽는다. 도중에 줄이기를 켜도 칸과 확대 단추가 함께 도착한다.
      _detailMotion.value = _detailOpen ? 1 : 0;
      _topMotion.value = widget.top;
    }
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_detailOpen != (oldWidget.detail != null && (oldWidget.detailOpen ?? true))) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _detailMotion.value = _detailOpen ? 1 : 0;
      } else if (_detailOpen) {
        _detailMotion.forward();
      } else {
        _detailMotion.reverse();
      }
    }
    if (widget.top != oldWidget.top) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _topMotion.value = widget.top;
      } else if (widget.top > oldWidget.top) {
        _topMotion.animateTo(widget.top);
      } else {
        _topMotion.animateBack(widget.top);
      }
    }
    if (widget.ownKeys == oldWidget.ownKeys) return;
    if (widget.ownKeys) {
      HardwareKeyboard.instance.addHandler(_escape);
    } else {
      HardwareKeyboard.instance.removeHandler(_escape);
    }
  }

  @override
  void dispose() {
    if (widget.ownKeys) HardwareKeyboard.instance.removeHandler(_escape);
    _detailMotion.dispose();
    _topMotion.dispose();
    _timelineScope.dispose();
    _ownSearchFocus?.dispose();
    super.dispose();
  }

  void _setFilter(bool open) {
    if (filterOpen == open) return;
    if (widget.filterOpen != null) {
      widget.onFilterOpen?.call(open);
    } else {
      setState(() => _filterOpenLocal = open);
      widget.onFilterOpen?.call(open);
    }
    if (!open) _timelineScope.requestFocus();
  }

  void _toggleFilter() => _setFilter(!filterOpen);

  /// 시트를 여닫는다(밖에서도 부른다 — `☰`와 `F`가 한 길로 가게).
  void toggleFilterSheet() => _toggleFilter();

  void _closeFilter() => _setFilter(false);

  void _closeDetail() {
    widget.onCloseDetail?.call();
    _timelineScope.requestFocus();
  }

  /// 연표로 초점을 돌려 준다(떠 있던 것이 닫혔을 때 — 밖에서도 부른다).
  void focusTimeline() => _timelineScope.requestFocus();

  /// Esc는 초점을 따지지 않고 먼저 받는다: 연표가 Esc를 제 것(움직임 멈춤)으로 쓰기 때문에
  /// 초점이 연표에 있으면 목록 · 시트 · 상세 창이 영영 닫히지 않는다. 위에 뜬 창(메뉴 · 대화상자)이 있으면 그쪽 몫이므로 비켜 준다.
  bool _escape(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!mounted || (Navigator.maybeOf(context)?.canPop() ?? false)) return false;
    return closeTopMost();
  }

  /// 떠 있는 것을 차례로 하나 닫는다(목록 → 시트 → 창). 닫을 것이 있었으면 참.
  /// 단축키 부품이 Esc를 맡을 때는 그쪽이 낸 `Cmd.close`가 이것을 부른다.
  bool closeTopMost() {
    if (widget.searchResults != null && widget.onCloseResults != null) {
      widget.onCloseResults!();
      if (_searchFocus.hasFocus) _timelineScope.requestFocus();
      return true;
    }
    if (filterOpen) {
      _closeFilter();
      return true;
    }
    if (_detailOpen) {
      _closeDetail();
      return true;
    }
    return false;
  }

  /// 틀의 단축키. 연표가 이미 `+ - ← →`와 Ctrl 조합을 처리하므로 겹치지 않는 것만 맡는다.
  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // 검색 칸에 글을 치는 동안에는 글자가 단축키가 되지 않는다.
    if (_searchFocus.hasFocus) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.slash) {
      if (!widget.ownKeys) return KeyEventResult.ignored;
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) && !HardwareKeyboard.instance.isControlPressed) {
      widget.controller.showAll();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: _key,
    canRequestFocus: false,
    child: LayoutBuilder(
      builder: (context, box) {
        final results = widget.searchResults;
        if (results != null) _lastResults = results;
        final float = widget.float ?? (Widget child) => child;
        return Stack(
          children: [
            // 맨 위 바탕 띠 + 그 아래 연표 영역(연표 맨 위에 1px 선).
            Positioned.fill(
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: _topMotion,
                    builder: (context, _) => SizedBox(
                      height: _topMotion.value.clamp(0, Ui.top),
                      child: const ColoredBox(color: Ui.bg, child: SizedBox.expand()),
                    ),
                  ),
                  Expanded(child: _stage(box)),
                ],
              ),
            ),
            if (widget.notice != null || widget.pills.isNotEmpty)
              Positioned(
                left: Ui.noticeLeft,
                top: Ui.noticeTop,
                right: Ui.noticeLeft,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (widget.notice != null) StatusPill(text: widget.notice!),
                      ...widget.pills,
                    ],
                  ),
                ),
              ),
            // 필터 시트: 바깥을 누르면 접힌다.
            if (filterOpen)
              Positioned.fill(
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _closeFilter),
              ),
            Positioned(
              left: Ui.sheetLeft,
              top: Ui.sheetTop,
              right: Ui.sheetLeft,
              child: float(
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: Ui.sheetWidth, maxHeight: box.maxHeight * .64),
                    child: FilterSheet(open: filterOpen, child: widget.filterSheet),
                  ),
                ),
              ),
            ),
            Positioned(
              left: Ui.dockLeft,
              top: Ui.dockTop,
              child: float(
                IgnorePointer(
                  ignoring: widget.frozen,
                  child: DockBar(
                    controller: widget.controller,
                    searchController: widget.searchController,
                    searchFocus: _searchFocus,
                    searchLink: _searchLink,
                    onSearchChanged: widget.onSearchChanged,
                    onSearchSubmitted: widget.onSearchSubmitted,
                    filterOpen: filterOpen,
                    onFilter: _toggleFilter,
                    buttons: widget.dockButtons,
                    menuItems: widget.menuItems,
                    onMenu: widget.onMenu,
                    maxWidth: math.max(240, box.maxWidth - 2 * Ui.dockLeft),
                    afterFilter: widget.dockAfterFilter,
                    zoom: ZoomButtons(controller: widget.controller, onBird: widget.onBird, horizontal: true),
                  ),
                ),
              ),
            ),
            // 검색 결과: 검색 칸의 왼쪽 아래에 붙는다(아래 +8).
            if (_lastResults != null)
              Positioned(
                left: 0,
                top: 0,
                child: CompositedTransformFollower(
                  link: _searchLink,
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: Ui.resultsOffset,
                  showWhenUnlinked: false,
                  child: IgnorePointer(
                    ignoring: widget.frozen,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: math.min(box.maxHeight * .6, Ui.resultsMaxHeight)),
                      child: MotionPresence(open: results != null, child: _lastResults!),
                    ),
                  ),
                ),
              ),
            for (final layer in widget.layers) Positioned.fill(child: IgnorePointer(ignoring: widget.frozen, child: layer)),
            if (widget.topLeft != null) Positioned(left: 8, top: 8, child: widget.topLeft!),
          ],
        );
      },
    ),
  );

  /// 연표 영역: 연표가 바닥을 채우고 그 위에 확대 단추 묶음이 뜨고, 상세 칸은 오른쪽에 붙는다(위 · 오른쪽 · 아래 틈 없음).
  Widget _stage(BoxConstraints box) {
    final detail = widget.detail;
    final open = _detailOpen;
    final width = math.min(Ui.detailWidth, math.max(220.0, box.maxWidth - 2 * Ui.detailInset));
    // [box]는 틀 전체의 크기다 — 단체 계보 창이 차지한 높이는 연표 아래에 비워 둔다.
    final sheet = widget.stageBottomInset?.call(box.maxHeight - widget.top) ?? 0.0;
    return AnimatedBuilder(
      animation: _detailMotion,
      builder: (context, _) => Stack(
        children: [
          Positioned.fill(
            // 맨 위 1px 선은 날짜 칸이 제 높이(409) 안에 품어 그린다(지금 연표의 .tl 윗테두리) — 여기서 또 그리면 연표가 통째로 1px 내려간다.
            child: FocusScope(node: _timelineScope, child: widget.timeline),
          ),
          Positioned(
            right: Ui.zoomRight + width * _detailMotion.value,
            bottom: Ui.zoomBottom + sheet,
            child: IgnorePointer(
              ignoring: widget.frozen,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                // 확대 묶음은 맨 위 줄로 옮겼다(리메이크 2부 — 목업 서고). 돋보기 배율 알약만 여기 남는다.
                children: [
                  MagPill(controller: widget.controller),
                ],
              ),
            ),
          ),
          if (widget.stageOverlay != null)
            Positioned(
              top: Ui.detailInset,
              right: Ui.detailInset,
              bottom: Ui.detailBottom + sheet,
              width: width,
              child: IgnorePointer(ignoring: widget.frozen, child: widget.stageOverlay!),
            ),
          if (detail != null)
            Positioned(
              top: Ui.detailInset,
              right: Ui.detailInset,
              bottom: Ui.detailBottom + sheet,
              width: width,
              child: IgnorePointer(
                ignoring: widget.frozen,
                child: DetailPanel(open: open, progress: _detailMotion, slide: width, bare: widget.detailBare, foot: widget.detailFoot, onClose: _closeDetail, child: detail),
              ),
            ),
        ],
      ),
    );
  }
}

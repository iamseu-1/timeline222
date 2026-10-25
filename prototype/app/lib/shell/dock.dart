import 'package:flutter/material.dart';

import '../controller.dart';
import '../scene/viewport.dart' show SceneView;
import 'app_menu.dart';
import 'line_icon.dart';
import 'look.dart';
import 'parts.dart';
import 'range_roll.dart';

// 맨 위 줄(웹 연표의 .dock): 창 맨 위 60px를 화면 폭으로 차지하고, 보는 시기 글(왼쪽 240 · 휴대폰 160) · 검색 칸(남는 만큼, 720까지) · 오른쪽 끝의 기호 단추
// (집합 보기 · 필터 · 렌즈 · 더 보기 — 글자 없이 선 아이콘만, 건의 8의 1번 꼴 A · 2026-10-13)가 한 줄로 든다.
// 떠 있던 알약 창을 HistoryArchive의 맨 위 줄 꼴로 바꾼 것이다(감독 결정 2026-10-13 · B안 — css/viewer.css 끝의 'HistoryArchive 통일' 절). 이름은 예전 그대로 둔다.

class DockBar extends StatefulWidget {
  const DockBar({
    super.key,
    required this.controller,
    required this.searchController,
    required this.searchFocus,
    required this.searchLink,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.filterOpen = false,
    this.onFilter,
    this.buttons = const <Widget>[],
    this.menuItems = const <AppMenuItem>[],
    this.onMenu,
    this.maxWidth = double.infinity,
    this.afterFilter = const <Widget>[],
    this.zoom,
  });

  final TimelineController controller;
  final TextEditingController searchController;
  final FocusNode searchFocus;

  /// 검색 칸의 자리를 알려 주는 고리 — 검색 결과 목록이 이 칸의 왼쪽 아래에 매달린다.
  final LayerLink searchLink;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final bool filterOpen;
  final VoidCallback? onFilter;

  /// 필터 단추 앞에 서는 단추들(집합 보기의 겹친 판 단추 — 제 일이 없으면 스스로 자리를 비운다).
  final List<Widget> buttons;
  final List<AppMenuItem> menuItems;

  /// `⋯`가 부를 것(단추의 자리를 받는다). 주면 [menuItems] 대신 이것으로 연다 —
  /// 앱은 명세 8-2의 메뉴(`ui/context_menu.dart`)를 여기에 잇는다.
  final Future<void> Function(BuildContext buttonContext)? onMenu;
  final double maxWidth;

  /// 필터 다음 · 더 보기 앞에 서는 단추들(렌즈의 눈동자 단추 — 감독 선택 D5 결정 6 B). 없으면 예전 그대로.
  final List<Widget> afterFilter;

  /// 확대 묶음(리메이크 2부 — 검색 칸 뒤 · 기호 단추 앞). 없으면 그 자리가 없다.
  final Widget? zoom;

  @override
  State<DockBar> createState() => _DockBarState();
}

class _DockBarState extends State<DockBar> {
  final _menuKey = GlobalKey();
  bool _menuOpen = false;

  Future<void> _openMenu() async {
    final anchor = _menuKey.currentContext;
    final open = widget.onMenu;
    if (anchor == null || (open == null && widget.menuItems.isEmpty)) return;
    setState(() => _menuOpen = true);
    if (open != null) {
      await open(anchor);
    } else {
      await showAppMenu(anchor, widget.menuItems);
    }
    if (mounted) setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.maxWidth.isFinite ? widget.maxWidth : null,
    height: Ui.dockHeight,
    child: Padding(
      padding: Ui.dockPadding,
      child: Row(
        children: [
          DockRange(controller: widget.controller),
          const SizedBox(width: Ui.dockGap),
          // 검색 칸은 남는 폭을 다 쓰되 720까지만 — 그 뒤의 빈 자리가 단추들을 오른쪽 끝으로 민다.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Ui.searchWidth),
                child: CompositedTransformTarget(
                  link: widget.searchLink,
                  child: _SearchField(
                    controller: widget.searchController,
                    focus: widget.searchFocus,
                    onChanged: widget.onSearchChanged,
                    onSubmitted: widget.onSearchSubmitted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: Ui.dockGap),
          // 확대 묶음(리메이크 2부 — 목업 서고처럼 맨 위 줄 오른쪽, 기호 단추들 앞).
          if (widget.zoom != null) ...[widget.zoom!, const SizedBox(width: Ui.dockGap * 3)],
          ...widget.buttons,
          DockIconButton(glyph: LineGlyph.menu, on: widget.filterOpen, onPressed: widget.onFilter, tooltip: '필터 (F)', semantics: '필터와 표시 설정'),
          for (final button in widget.afterFilter) ...[const SizedBox(width: Ui.dockIconGap), button],
          const SizedBox(width: Ui.dockIconGap),
          DockIconButton(key: _menuKey, glyph: LineGlyph.more, on: _menuOpen, onPressed: _openMenu, tooltip: '더 보기'),
        ],
      ),
    ),
  );
}

/// 맨 위 줄 왼쪽의 보는 시기 글("240년 ~ 340년") — 줄 이름 칸과 같은 폭(240 · 휴대폰 160 — 넘치면 RangeRoll이 줄여 그린다). 보기가 움직이는 장면마다가 아니라 **글이 바뀔 때만** 다시 짓는다.
class DockRange extends StatefulWidget {
  const DockRange({super.key, required this.controller});
  final TimelineController controller;

  /// 검사용: 글을 다시 지은 횟수.
  @visibleForTesting
  static int builds = 0;

  @override
  State<DockRange> createState() => _DockRangeState();
}

class _DockRangeState extends State<DockRange> {
  late String _label = _read();

  String _read() => rangeLabel(widget.controller.view.lo, widget.controller.view.hi);

  void _sync() {
    final next = _read();
    if (next != _label && mounted) setState(() => _label = next);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    DockRange.builds++;
    return Container(
      width: SceneView.gutterNow,
      padding: Ui.dockRangePadding,
      alignment: Alignment.centerLeft,
      child: RangeRoll(label: _label),
    );
  }
}

/// 검색 칸: 높이 44 · 폭은 받은 만큼 · paper 바탕에 ink20 테두리(초점은 ink) · 둥근 6 · 왼쪽 13에 15×15 돋보기 그림 · 글은 왼쪽 40부터.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focus, this.onChanged, this.onSubmitted});
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String>? onChanged, onSubmitted;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: Ui.searchHeight,
    // 테두리는 글 칸(TextField)이 아니라 이 상자가 그린다 — 글 칸의 제 테두리는 글 한 줄 높이만 감싸서 44px 칸을 채우지 못한다. 초점이 오면 ink 선.
    child: ListenableBuilder(
      listenable: focus,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: Ui.paper,
          borderRadius: BorderRadius.circular(Ui.searchRadius),
          border: Border.all(color: focus.hasFocus ? Ui.ink : Ui.ink20),
        ),
        child: child,
      ),
      child: Stack(
        children: [
          // 칸을 꽉 채운다 — 글이 세로 한가운데 오고, 검색 결과 목록이 이 칸의 아래에 매달린다.
          Positioned.fill(
            child: TextField(
              controller: controller,
              focusNode: focus,
              maxLines: 1,
              textAlignVertical: TextAlignVertical.center,
              cursorColor: Ui.ink,
              style: const TextStyle(fontSize: 14, height: 20 / 14, color: Ui.text),
              // 회색 예시 글자는 두지 않는다.
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.fromLTRB(40, 0, 12, 0), border: InputBorder.none),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          const Positioned(
            left: 13,
            top: 0,
            bottom: 0,
            child: IgnorePointer(child: Center(child: CustomPaint(size: Size(15, 15), painter: _Magnifier()))),
          ),
        ],
      ),
    ),
  );
}

/// 검색 칸의 돋보기 그림(지금 연표의 css가 깔아 둔 svg 그대로: 반지름 4.8의 원 + 3.3 길이의 손잡이 · 굵기 2 · 둥근 끝).
class _Magnifier extends CustomPainter {
  const _Magnifier();

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Ui.searchIcon;
    canvas.drawCircle(const Offset(6.5, 6.5), 4.8, pen);
    canvas.drawLine(const Offset(10.2, 10.2), const Offset(13.5, 13.5), pen);
  }

  @override
  bool shouldRepaint(_Magnifier oldDelegate) => false;
}

/// 맨 위 줄 아래 작은 알림 칸(웹 연표의 .status-pill): paper 바탕 · ink20 선 · 둥근 6. 지금은 측정 중 안내만 쓴다.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => GlassCard(
    radius: Ui.controlRadius,
    blur: Ui.blurLight,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w600, color: Ui.text),
    ),
  );
}

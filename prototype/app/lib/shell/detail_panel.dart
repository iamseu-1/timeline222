import 'package:flutter/material.dart';

import '../motion.dart';
import '../motion_spring.dart';
import 'look.dart';
import 'parts.dart';

/// 고를 때만 연표 영역 오른쪽에 붙는 칸(웹 연표의 .detail — HistoryArchive의 보조 칸과 같은 꼴):
/// paper 바탕 · 왼쪽 1px ink20 선 · 모서리와 그림자 없음. 상세 칸과 확대 묶음이 같은 move/snap 진행값으로 움직인다.
///
/// 두 가지로 쓴다:
///  · [bare]가 거짓 — 이 창이 머리(✕)와 안쪽 여백까지 그린다(내용만 넘길 때).
///  · [bare]가 참   — 속을 `ui/detail_shell.dart`의 `DetailHost(framed: false)`가 채운다. 그 부품이 제 머리 · 여백 · ✕를 그리므로
///    여기서는 바탕과 미끄러져 들어오기만 맡는다. 그때는 [open]으로 여닫는다 — 창을 **떼어 내지 않고** 숨긴다
///    (떼면 고른 것을 듣던 부품이 사라져 다시 열리지 않는다).
class DetailPanel extends StatefulWidget {
  const DetailPanel({super.key, required this.child, this.onClose, this.open = true, this.bare = false, this.foot, this.progress, this.slide = Ui.detailWidth});
  final Animation<double>? progress;
  final double slide;
  final Widget child;
  final VoidCallback? onClose;

  /// 창이 보이는가. 거짓이면 투명해지고 손도 받지 않되 속은 살아 있다.
  final bool open;

  /// 머리 · 안쪽 여백을 속이 스스로 그리는가.
  final bool bare;

  /// 창 맨 아래에 1px 선과 함께 붙는 줄(원문 단추). 없으면 그 칸이 없다.
  final Widget? foot;

  @override
  State<DetailPanel> createState() => _DetailPanelState();
}

class _DetailPanelState extends State<DetailPanel> {
  late final MotionAnimation _enter = MotionAnimation(maxOvershoot: 6 / widget.slide);
  late final MotionAnimation _fade = MotionAnimation(enter: MotionToken.enter, exit: MotionToken.exit, maxOvershoot: 0);
  Animation<double> get _position => widget.progress ?? _enter;

  void _aim() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _enter.value = _fade.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      if (widget.progress == null) _enter.forward();
      _fade.forward();
    } else {
      if (widget.progress == null) _enter.reverse();
      _fade.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      if (widget.progress == null) _enter.forward();
      _fade.forward();
    }
  }

  @override
  void didUpdateWidget(DetailPanel old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    _aim();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 움직임 줄이기면 미끄러지지 않고 바로 자리에.
    _aim();
  }

  @override
  void dispose() {
    _enter.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !widget.open,
    child: ExcludeFocus(
      excluding: !widget.open,
      child: AnimatedBuilder(
        animation: Listenable.merge([_position, _fade]),
        builder: (context, child) => ExcludeSemantics(
          excluding: !widget.open,
          child: Opacity(
            opacity: _fade.value.clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(widget.slide * (1 - _position.value), 0), child: child),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(top: 0, bottom: 0, left: 0, right: -6, child: ColoredBox(color: Ui.detailGlass)),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: Ui.detailGlass,
                border: Border(left: BorderSide(color: Ui.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.bare)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 10, 0),
                      child: Row(
                        children: [
                          const Spacer(),
                          ShellButton(
                            width: 32,
                            height: 32,
                            padding: EdgeInsets.zero,
                            tooltip: '닫기',
                            onPressed: widget.onClose,
                            child: const Text('✕', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400)),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: widget.bare ? widget.child : Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 16), child: widget.child),
                  ),
                  if (widget.foot != null)
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Ui.line)),
                      ),
                      child: Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 12), child: widget.foot!),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

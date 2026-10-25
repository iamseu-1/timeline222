import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../motion_spring.dart';
import 'look.dart';

// 감독의 움직임 목업(2026-10-13): 부품은 값의 주인만 맡고, 시간과 식은 MotionStage 한 곳에서 받는다.
// 같은 값에 새 목표를 적어 도중에 다시 눌러도 현재 자리와 속도를 보존한다.
mixin _ControlMotion<T extends StatefulWidget> on State<T> {
  final _springs = <MotionSpring>[];

  MotionSpring spring(
    double value, {
    double epsilon = .001,
    double maxOvershoot = 6,
  }) {
    final result = MotionSpring(
      value,
      epsilon: epsilon,
      maxOvershoot: maxOvershoot,
    );
    _springs.add(result);
    MotionStage.instance.attach(result, _changed);
    return result;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void aim(MotionSpring value, double target, MotionToken token) {
    if ((MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        token != MotionToken.enter &&
        token != MotionToken.exit) {
      value.jump(target);
    } else {
      value.retarget(target, token: token);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) return;
    for (final value in _springs) {
      if (value.token != MotionToken.enter && value.token != MotionToken.exit) {
        value.jump(value.target);
      }
    }
  }

  @override
  void dispose() {
    for (final value in _springs) {
      MotionStage.instance.detach(value);
    }
    super.dispose();
  }
}

/// 키보드와 접근성에서도 같은 선택 동작. 눌림의 크기를 바꾸는 주인은 각 부품에 하나뿐이다.
class _ControlAction extends StatelessWidget {
  const _ControlAction({
    required this.child,
    required this.onTap,
    this.onDown,
    this.onUp,
    this.label,
    this.selected,
    this.toggled,
  });
  final Widget child;
  final VoidCallback? onTap, onDown, onUp;
  final String? label;
  final bool? selected, toggled;

  @override
  Widget build(BuildContext context) => Semantics(
    button: toggled == null,
    enabled: onTap != null,
    label: label,
    excludeSemantics: label != null,
    selected: selected,
    toggled: toggled,
    onTap: onTap,
    child: FocusableActionDetector(
      enabled: onTap != null,
      mouseCursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onTap?.call();
            return null;
          },
        ),
      },
      child: MouseRegion(
        onExit: (_) => onUp?.call(),
        child: Listener(
          onPointerDown: onTap == null ? null : (_) => onDown?.call(),
          onPointerUp: onTap == null ? null : (_) => onUp?.call(),
          onPointerCancel: (_) => onUp?.call(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: onTap,
            onTapCancel: onUp,
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// 둥근 6의 42×24 틀과 둥근 4의 18×18 손잡이. 손잡이의 이동/눌림은 한 Transform으로 합친다.
class MotionToggle extends StatefulWidget {
  const MotionToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label, hint;

  @override
  State<MotionToggle> createState() => _MotionToggleState();
}

class _MotionToggleState extends State<MotionToggle>
    with _ControlMotion<MotionToggle> {
  late final _position = spring(widget.value ? 18 : 0, epsilon: .02);
  late final _fill = spring(widget.value ? 1 : 0, maxOvershoot: 0);
  late final _scale = spring(1, maxOvershoot: 6 / 18);

  @override
  void initState() {
    super.initState();
    _position;
    _fill;
    _scale;
  }

  @override
  void didUpdateWidget(covariant MotionToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    aim(_position, widget.value ? 18 : 0, MotionToken.pop);
    aim(
      _fill,
      widget.value ? 1 : 0,
      widget.value ? MotionToken.enter : MotionToken.exit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fill = _fill.value.clamp(0.0, 1.0);
    final toggle = SizedBox(
      width: 42,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Ui.ink20),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: fill,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Ui.ink,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          Positioned(
            left: 3,
            top: 3,
            child: Transform(
              key: const ValueKey('motion-toggle-knob'),
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translateByDouble(_position.value, 0, 0, 1)
                ..scaleByDouble(_scale.value, _scale.value, 1, 1),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Color.lerp(Ui.ink40, Ui.paper, fill),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Widget body = _ControlAction(
      onTap: widget.onChanged == null
          ? null
          : () => widget.onChanged!(!widget.value),
      onDown: () => aim(_scale, .86, MotionToken.snap),
      onUp: () => aim(_scale, 1, MotionToken.pop),
      label: widget.label,
      toggled: widget.value,
      child: widget.label == null
          ? toggle
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                toggle,
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.label!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Ui.text2,
                    ),
                  ),
                ),
              ],
            ),
    );
    if (widget.hint != null) body = Tooltip(message: widget.hint!, child: body);
    return body;
  }
}

/// 여럿 고르기: 채움이 안에서 자라며 나타나고, 뺄 때는 작아지며 옅어진다.
class MotionChip extends StatefulWidget {
  const MotionChip({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.color,
    this.hint,
  });
  final String label;
  final bool value;
  final VoidCallback onTap;
  final Color? color;
  final String? hint;

  @override
  State<MotionChip> createState() => _MotionChipState();
}

class _MotionChipState extends State<MotionChip>
    with _ControlMotion<MotionChip> {
  // 눌림과 안쪽 채움이 동시에 넘쳐도 600px 칩의 양옆 넘침 합성은 각각 6px 이내다.
  static final _overshoot = math.sqrt(1 + 12 / 600) - 1;
  late final _size = spring(widget.value ? 1 : .7, maxOvershoot: _overshoot);
  late final _alpha = spring(widget.value ? 1 : 0, maxOvershoot: 0);
  late final _press = spring(1, maxOvershoot: _overshoot);
  bool _hover = false;
  bool _down = false;

  void _pressTo(bool down) {
    if (_down == down) return;
    _down = down;
    aim(_press, down ? .95 : 1, down ? MotionToken.snap : MotionToken.pop);
    if (!down && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _press.kick(1.2 * Motion.releaseKick);
    }
  }

  @override
  void initState() {
    super.initState();
    _size;
    _alpha;
    _press;
  }

  @override
  void didUpdateWidget(covariant MotionChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    aim(
      _size,
      widget.value ? 1 : .7,
      widget.value ? MotionToken.pop : MotionToken.snap,
    );
    aim(
      _alpha,
      widget.value ? 1 : 0,
      widget.value ? MotionToken.enter : MotionToken.exit,
    );
  }

  Widget _label(Color color, {bool inverse = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.color != null) ...[
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
        const SizedBox(width: 6),
      ],
      if (inverse)
        Flexible(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              text: widget.label,
              style: DefaultTextStyle.of(context).style.copyWith(
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        )
      else
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    Widget body = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: _ControlAction(
        onTap: widget.onTap,
        onDown: () => _pressTo(true),
        onUp: () => _pressTo(false),
        label: widget.label,
        selected: widget.value,
        child: Transform.scale(
          scale: _press.value,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: Duration(milliseconds: Motion.micro.round()),
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                constraints: const BoxConstraints(maxWidth: 600),
                decoration: BoxDecoration(
                  border: Border.all(color: _hover ? Ui.ink40 : Ui.ink20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  widthFactor: 1,
                  child: _label(_hover ? Ui.ink : Ui.ink60),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Opacity(
                      opacity: _alpha.value.clamp(0.0, 1.0),
                      child: Transform.scale(
                        key: const ValueKey('motion-chip-fill'),
                        scale: _size.value,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Ui.ink,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: _label(Ui.paper, inverse: true),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (widget.hint != null) body = Tooltip(message: widget.hint!, child: body);
    return body;
  }
}

@immutable
class MotionChoice<T> {
  const MotionChoice(this.value, this.label);
  final T value;
  final String label;
}

/// 하나 고르기: 움직이는 반전 면 위에서도 글자는 제자리에 남는다.
/// 항목이 많은 자료에서도 선택을 버리지 않도록 좁은 화면에서는 옆으로 넘겨 본다.
class MotionSegmented<T> extends StatefulWidget {
  const MotionSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.label,
    this.hint,
  });
  final T value;
  final List<MotionChoice<T>> options;
  final ValueChanged<T>? onChanged;
  final String label;
  final String? hint;

  @override
  State<MotionSegmented<T>> createState() => _MotionSegmentedState<T>();
}

class _MotionSegmentedState<T> extends State<MotionSegmented<T>>
    with _ControlMotion<MotionSegmented<T>> {
  late final _position = spring(0, epsilon: .02);
  double _width = 56;
  bool _placed = false;
  int get _index => math.max(
    0,
    widget.options.indexWhere((option) => option.value == widget.value),
  );

  @override
  void initState() {
    super.initState();
    _position;
  }

  @override
  void didUpdateWidget(covariant MotionSegmented<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _measure();
    final target = _index * _width;
    aim(_position, target, Motion.near((target - _position.target).abs()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measure();
  }

  void _measure() {
    const style = TextStyle(
      fontSize: 13,
      height: 1,
      fontWeight: FontWeight.w600,
    );
    double width = 56;
    for (final option in widget.options) {
      final painter = TextPainter(
        text: TextSpan(
          text: option.label,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      width = math.max(width, painter.width + 20);
      painter.dispose();
    }
    if (!_placed || width != _width) {
      _width = width;
      // 초기 배치와 글꼴 배율은 움직임의 목표 변경이 아니다.
      _position.jump(_index * width);
      _placed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    const style = TextStyle(
      fontSize: 13,
      height: 1,
      fontWeight: FontWeight.w600,
    );
    final width = _width, total = _width * widget.options.length;
    Widget labels(Color color, {bool action = false}) => Row(
      children: [
        for (final option in widget.options)
          SizedBox(
            width: width,
            height: 28,
            child: action
                ? _ControlAction(
                    onTap: widget.onChanged == null
                        ? null
                        : () => widget.onChanged!(option.value),
                    label: option.label,
                    selected: option.value == widget.value,
                    child: Center(
                      child: Text(
                        option.label,
                        style: style.copyWith(color: color),
                      ),
                    ),
                  )
                : Center(
                    child: RichText(
                      text: TextSpan(
                        text: option.label,
                        style: DefaultTextStyle.of(context).style
                            .merge(style)
                            .copyWith(color: color),
                      ),
                    ),
                  ),
          ),
      ],
    );
    Widget body = LayoutBuilder(
      builder: (context, box) => SizedBox(
        width: math.min(total + 6, box.maxWidth),
        height: 34,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Ui.ink20),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: SizedBox(
                  width: total,
                  height: 28,
                  child: Stack(
                    children: [
                      labels(Ui.ink60, action: true),
                      Positioned(
                        key: const ValueKey('motion-segment-indicator'),
                        left: _position.value,
                        top: 0,
                        width: width,
                        height: 28,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: ColoredBox(
                                color: Ui.ink,
                                child: OverflowBox(
                                  alignment: Alignment.topLeft,
                                  minWidth: total,
                                  maxWidth: total,
                                  child: Transform.translate(
                                    offset: Offset(-_position.value, 0),
                                    child: labels(Ui.paper),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    body = Semantics(label: widget.label, child: body);
    if (widget.hint != null) body = Tooltip(message: widget.hint!, child: body);
    return body;
  }
}

/// 중요도: 8 · 14 · 20px 막대가 밑에서 자란다. 올라갈 때 40ms씩 이어지는 예약도 같은 시계를 쓴다.
class MotionSteps extends StatefulWidget {
  const MotionSteps({
    super.key,
    required this.value,
    required this.onChanged,
    required this.labels,
    this.label = '중요도 필터',
  });
  final int value;
  final ValueChanged<int> onChanged;
  final List<String> labels;
  final String label;

  @override
  State<MotionSteps> createState() => _MotionStepsState();
}

class _MotionStepsState extends State<MotionSteps>
    with _ControlMotion<MotionSteps> {
  late final _bars = [
    for (int i = 0; i < 3; i++)
      spring(i < widget.value ? 1 : 0, maxOvershoot: 6 / 20),
  ];
  final _pending = <Object>[];

  @override
  void initState() {
    super.initState();
    _bars;
  }

  @override
  void didUpdateWidget(covariant MotionSteps oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final pending in _pending) {
      MotionStage.instance.cancel(pending);
    }
    _pending.clear();
    for (int i = 0; i < 3; i++) {
      final on = i < widget.value;
      void target() =>
          aim(_bars[i], on ? 1 : 0, on ? MotionToken.pop : MotionToken.snap);
      if (on && i > oldWidget.value) {
        _pending.add(
          MotionStage.instance.schedule((i - oldWidget.value) * 40.0, target),
        );
      } else {
        target();
      }
    }
  }

  @override
  void dispose() {
    for (final pending in _pending) {
      MotionStage.instance.cancel(pending);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 24,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Tooltip(
                  message: widget.labels[i],
                  child: _ControlAction(
                    onTap: () => widget.onChanged(i + 1),
                    label: widget.labels[i],
                    selected: widget.value == i + 1,
                    child: SizedBox(
                      width: 14,
                      height: 24,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: 14,
                          height: (8 + i * 6).toDouble(),
                          decoration: BoxDecoration(
                            color: Ui.ink20,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Transform.scale(
                            scaleY: math.max(0, _bars[i].value),
                            alignment: Alignment.bottomCenter,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Ui.ink,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          widget.labels[widget.value.clamp(1, 3) - 1],
          style: const TextStyle(fontSize: 12, color: Ui.ink60),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import '../motion.dart';
import '../motion_spring.dart';

/// 단순 표시값도 같은 장의 스프링을 쓴다. 부모가 목표만 바꾸고 상태는 유지한다.
class MotionValue extends StatefulWidget {
  const MotionValue({
    super.key,
    required this.target,
    required this.builder,
    this.child,
    this.enter = MotionToken.move,
    this.exit = MotionToken.snap,
    this.maxOvershoot = 6,
  });
  final double target, maxOvershoot;
  final MotionToken enter, exit;
  final Widget Function(BuildContext, double, Widget?) builder;
  final Widget? child;
  @override
  State<MotionValue> createState() => _MotionValueState();
}

class _MotionValueState extends State<MotionValue> {
  late final _value = MotionAnimation(
    value: widget.target,
    enter: widget.enter,
    exit: widget.exit,
    maxOvershoot: widget.maxOvershoot,
  );
  void _aim() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _value.value = widget.target;
    } else if (widget.target >= _value.value) {
      _value.animateTo(widget.target);
    } else {
      _value.animateBack(widget.target);
    }
  }

  @override
  void didUpdateWidget(MotionValue old) {
    super.didUpdateWidget(old);
    _aim();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _aim();
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _value,
    builder: (context, child) => widget.builder(context, _value.value, child),
    child: widget.child,
  );
}

/// 하나의 면에서 크기·자리와 불투명도를 혼동하지 않게 묶는다.
/// 호출부는 한 번만 여닫고, 두 값은 같은 장면 시계에서 각 토큰을 따른다.
class SurfaceMotion extends MotionAnimation {
  SurfaceMotion({
    super.enter = MotionToken.pop,
    super.exit = MotionToken.snap,
    super.maxOvershoot = .1,
  }) {
    _fade.addListener(notifyListeners);
  }
  final _fade = MotionAnimation(
    enter: MotionToken.enter,
    exit: MotionToken.exit,
    maxOvershoot: 0,
  );
  double get opacity => _fade.value.clamp(0.0, 1.0);

  @override
  set value(double next) {
    super.value = next;
    _fade.value = next;
  }

  @override
  void forward({double? from}) {
    super.forward(from: from);
    _fade.forward(from: from);
  }

  @override
  void reverse({double? from}) {
    super.reverse(from: from);
    _fade.reverse(from: from);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }
}

/// 떠 있는 면의 자리·크기와 밝기를 각각 한 값으로 맡는다.
/// 닫는 도중 다시 열어도 같은 스프링과 같은 내용을 이어 쓴다.
class MotionPresence extends StatefulWidget {
  const MotionPresence({
    super.key,
    required this.open,
    required this.child,
    this.alignment = Alignment.topLeft,
  });
  final bool open;
  final Widget child;
  final Alignment alignment;

  @override
  State<MotionPresence> createState() => _MotionPresenceState();
}

class _MotionPresenceState extends State<MotionPresence> {
  final _place = MotionAnimation(
    enter: MotionToken.pop,
    exit: MotionToken.snap,
    maxOvershoot: .1,
  );
  final _fade = MotionAnimation(
    enter: MotionToken.enter,
    exit: MotionToken.exit,
    maxOvershoot: 0,
  );
  late final Listenable _changes = Listenable.merge([_place, _fade]);
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    _aim();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _aim();
  }

  @override
  void didUpdateWidget(MotionPresence old) {
    super.didUpdateWidget(old);
    if (old.open != widget.open) _aim();
  }

  void _aim() {
    if (_reduce) {
      _place.value = widget.open ? 1 : 0;
      _fade.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _place.forward();
      _fade.forward();
    } else {
      _place.reverse();
      _fade.reverse();
    }
  }

  @override
  void dispose() {
    _place.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !widget.open,
    child: ExcludeSemantics(
      excluding: !widget.open,
      child: ExcludeFocus(
        excluding: !widget.open,
        child: AnimatedBuilder(
          animation: _changes,
          child: RepaintBoundary(child: widget.child),
          builder: (context, child) {
            if (!widget.open && _fade.isDismissed && !_place.isAnimating) {
              return const SizedBox.shrink();
            }
            return Opacity(
              opacity: _fade.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -6 * (1 - _place.value)),
                child: Transform.scale(
                  scale: .95 + .05 * _place.value,
                  alignment: widget.alignment,
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// 누르는 순간 snap으로 들어가고 놓으면 pop으로 돌아온다.
/// 클릭의 실행은 기존 단추가 맡고, 이 부품은 크기 하나만 맡는다.
class MotionPress extends StatefulWidget {
  const MotionPress({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<MotionPress> createState() => _MotionPressState();
}

class _MotionPressState extends State<MotionPress> {
  final _scale = MotionAnimation(
    value: 1,
    enter: MotionToken.pop,
    exit: MotionToken.snap,
    maxOvershoot: .02,
  );
  bool _down = false;

  void _press(bool down) {
    if (_down == down) return;
    _down = down;
    final target = down ? .95 : 1.0;
    if (!widget.enabled ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _scale.value = 1;
    } else if (down) {
      _scale.animateBack(target);
    } else {
      _scale.animateTo(target);
      _scale.kick(1.2 * Motion.releaseKick);
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onExit: (_) => _press(false),
    child: Listener(
      onPointerDown: (_) => _press(true),
      onPointerUp: (_) => _press(false),
      onPointerCancel: (_) => _press(false),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    ),
  );
}

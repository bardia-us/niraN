import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/vpn/app_controller.dart';

/// A transform-only desktop interaction. It keeps hover work on the compositor
/// and becomes a plain child when Performance Mode is enabled.
class InteractiveDepth extends ConsumerStatefulWidget {
  const InteractiveDepth({
    required this.child,
    super.key,
    this.enabled = true,
    this.radius = 14,
  });

  final Widget child;
  final bool enabled;
  final double radius;

  @override
  ConsumerState<InteractiveDepth> createState() => _InteractiveDepthState();
}

class _InteractiveDepthState extends ConsumerState<InteractiveDepth> {
  Offset _tilt = Offset.zero;
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = ref.watch(performanceModeProvider);
    if (reduced || !widget.enabled) return widget.child;
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, .0012)
      ..rotateX(-_tilt.dy * .020)
      ..rotateY(_tilt.dx * .020)
      ..scaleByDouble(
        _pressed
            ? .975
            : _hovered
            ? 1.018
            : 1,
        _pressed
            ? .975
            : _hovered
            ? 1.018
            : 1,
        1,
        1,
      );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
        _tilt = Offset.zero;
      }),
      onHover: (event) {
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return;
        final local = box.globalToLocal(event.position);
        final next = Offset(
          ((local.dx / math.max(1, box.size.width)) - .5) * 2,
          ((local.dy / math.max(1, box.size.height)) - .5) * 2,
        );
        if ((next - _tilt).distanceSquared > .0025) {
          setState(() => _tilt = next);
        }
      },
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: Duration(milliseconds: _pressed ? 70 : 170),
          curve: Curves.easeOutCubic,
          transform: matrix,
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .13),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

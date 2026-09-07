import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A transform-only desktop interaction. It keeps hover work on the compositor
/// and becomes a plain child when Performance Mode is enabled.
class InteractiveDepth extends StatefulWidget {
  const InteractiveDepth({
    required this.child,
    super.key,
    this.enabled = true,
    this.pressEnabled = true,
    this.reducedEffects = false,
    this.radius = 14,
  });

  final Widget child;
  final bool enabled;
  final bool pressEnabled;
  final bool reducedEffects;
  final double radius;

  @override
  State<InteractiveDepth> createState() => _InteractiveDepthState();
}

class _InteractiveDepthState extends State<InteractiveDepth> {
  Offset _tilt = Offset.zero;
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.reducedEffects) return widget.child;
    final effectsEnabled = widget.enabled;
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, .0012)
      ..rotateX(effectsEnabled ? -_tilt.dy * .012 : 0)
      ..rotateY(effectsEnabled ? _tilt.dx * .012 : 0)
      ..scaleByDouble(
        !effectsEnabled
            ? 1
            : _pressed
            ? .982
            : _hovered
            ? 1.010
            : 1,
        !effectsEnabled
            ? 1
            : _pressed
            ? .982
            : _hovered
            ? 1.010
            : 1,
        1,
        1,
      );
    return MouseRegion(
      onEnter: effectsEnabled ? (_) => setState(() => _hovered = true) : null,
      onExit: effectsEnabled
          ? (_) => setState(() {
              _hovered = false;
              _pressed = false;
              _tilt = Offset.zero;
            })
          : null,
      onHover: effectsEnabled
          ? (event) {
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
            }
          : null,
      child: Listener(
        onPointerDown: widget.pressEnabled && effectsEnabled
            ? (_) => setState(() => _pressed = true)
            : null,
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: Duration(milliseconds: _pressed ? 70 : 170),
          curve: Curves.easeOutCubic,
          transform: matrix,
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: effectsEnabled && _hovered
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

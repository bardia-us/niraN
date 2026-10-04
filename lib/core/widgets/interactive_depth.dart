import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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
    this.tiltEnabled = true,
  });

  final Widget child;
  final bool enabled;
  final bool pressEnabled;
  final bool reducedEffects;
  final double radius;
  final bool tiltEnabled;

  @override
  State<InteractiveDepth> createState() => _InteractiveDepthState();
}

class _InteractiveDepthState extends State<InteractiveDepth> {
  Offset _tilt = Offset.zero;
  Offset _stretch = Offset.zero;
  Offset _translation = Offset.zero;
  Offset _pressOrigin = Offset.zero;
  bool _hovered = false;
  bool _pressed = false;

  void _updateStretch(Offset position) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final drag = position - _pressOrigin;
    final delta = drag / math.max(1, box.size.shortestSide);
    _stretch = delta / math.max(1, delta.distance);
    _translation = Offset(
      (drag.dx * .12).clamp(-5, 5),
      (drag.dy * .12).clamp(-4, 4),
    );
  }

  void _release() => setState(() {
    _stretch = Offset.zero;
    _translation = Offset.zero;
    _pressed = false;
  });

  @override
  void didUpdateWidget(covariant InteractiveDepth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || !widget.pressEnabled || widget.reducedEffects) {
      _stretch = Offset.zero;
      _translation = Offset.zero;
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reducedEffects || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    final effectsEnabled = widget.enabled;
    final stretch = effectsEnabled && _pressed ? _stretch.distance * .08 : 0.0;
    final direction = _stretch.direction;
    final matrix = Matrix4.identity()
      ..translateByDouble(
        effectsEnabled ? _translation.dx : 0,
        effectsEnabled ? _translation.dy : 0,
        0,
        1,
      )
      // Keep resting/flat controls on Impeller's pixel-snapped glyph path.
      // A perspective entry is needed only while actually tilting in 3D.
      ..setEntry(
        3,
        2,
        effectsEnabled && widget.tiltEnabled && _tilt != Offset.zero ? .0012 : 0,
      )
      ..rotateX(effectsEnabled && widget.tiltEnabled ? -_tilt.dy * .012 : 0)
      ..rotateY(effectsEnabled && widget.tiltEnabled ? _tilt.dx * .012 : 0)
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
    // Stretch along the drag and compress perpendicular to it. Reciprocal
    // scales keep the area bounded. Deform around the centre while the bounded
    // translation follows the pointer, independently of the control's size.
    matrix
      ..rotateZ(direction)
      ..scaleByDouble(1 + stretch, 1 / (1 + stretch), 1, 1)
      ..rotateZ(-direction);
    return MouseRegion(
      onEnter: effectsEnabled ? (_) => setState(() => _hovered = true) : null,
      onExit: effectsEnabled
          ? (_) => setState(() {
              _hovered = false;
              _tilt = Offset.zero;
            })
          : null,
      onHover: effectsEnabled && widget.tiltEnabled
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
      child: GestureDetector(
        // Own the pan gesture so a drag cancels descendant button taps. Raw
        // pointer events below drive the material even before pan slop.
        onPanUpdate: widget.pressEnabled && effectsEnabled ? (_) {} : null,
        onPanEnd: widget.pressEnabled && effectsEnabled
            ? (_) => _release()
            : null,
        onPanCancel: widget.pressEnabled && effectsEnabled ? _release : null,
        child: Listener(
          onPointerDown: widget.pressEnabled && effectsEnabled
              ? (event) => setState(() {
                  _pressOrigin = event.position;
                  _stretch = Offset.zero;
                  _translation = Offset.zero;
                  _pressed = true;
                })
              : null,
          onPointerMove: widget.pressEnabled && effectsEnabled
              ? (event) {
                  if (!_pressed) return;
                  setState(() => _updateStretch(event.position));
                }
              : null,
          onPointerUp: widget.pressEnabled ? (_) => _release() : null,
          onPointerCancel: widget.pressEnabled ? (_) => _release() : null,
          child: AnimatedContainer(
            duration: Duration(milliseconds: _pressed ? 70 : 260),
            curve: _pressed ? Curves.easeOutCubic : const _DepthReturnCurve(),
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
      ),
    );
  }
}

class _DepthReturnCurve extends Curve {
  const _DepthReturnCurve();

  static final _spring = SpringSimulation(
    const SpringDescription(mass: 1, stiffness: 420, damping: 32),
    0,
    1,
    0,
  );

  @override
  double transformInternal(double t) => _spring.x(t * .46);
}

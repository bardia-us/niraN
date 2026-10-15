import 'dart:async';

import 'package:flutter/material.dart';

import 'snapshot_glass.dart';
import '../render_mode.dart';

/// Keep the captured image alive through the final reverse-transition frame,
/// without delaying the caller's normal Navigator.pop result.
Future<T?> showSnapshotGlassRoute<T>({
  required BuildContext context,
  required RoutePageBuilder pageBuilder,
  required Duration transitionDuration,
  RouteTransitionsBuilder? transitionBuilder,
  bool barrierDismissible = true,
  Rect? captureRegion,
  bool useLiveBackdrop = false,
  bool captureBackdrop = true,
  Future<GlassSnapshot?> Function(BuildContext context, {Rect? region})
      snapshotPreparation =
      prepareGlassSnapshot,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final barrierLabel = MaterialLocalizations.of(
    context,
  ).modalBarrierDismissLabel;
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final lightweight = lightweightRenderingOf(context);
  final snapshot = lightweight || useLiveBackdrop || !captureBackdrop
      ? null
      : await snapshotPreparation(context, region: captureRegion);
  if (!context.mounted || !navigator.mounted) {
    snapshot?.dispose();
    return null;
  }
  final route = RawDialogRoute<T>(
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: Colors.transparent,
    transitionDuration: transitionDuration,
    transitionBuilder: transitionBuilder,
    pageBuilder: (routeContext, animation, secondaryAnimation) {
      final page = pageBuilder(routeContext, animation, secondaryAnimation);
      final child = lightweight ? LightweightModalScope(child: page) : page;
      return themes.wrap(
        snapshot == null
            ? child
            : SnapshotGlassScope(
                snapshot: snapshot,
                repaint: animation,
                child: child,
              ),
      );
    },
  );
  try {
    final result = navigator.push(route);
    unawaited(route.completed.whenComplete(() => snapshot?.dispose()));
    return await result;
  } on Object {
    snapshot?.dispose();
    rethrow;
  }
}

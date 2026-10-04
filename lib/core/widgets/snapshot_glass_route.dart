import 'dart:async';

import 'package:flutter/material.dart';

import 'snapshot_glass.dart';

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
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final barrierLabel = MaterialLocalizations.of(
    context,
  ).modalBarrierDismissLabel;
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final snapshot = useLiveBackdrop
      ? null
      : await prepareGlassSnapshot(context, region: captureRegion);
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
      final child = pageBuilder(routeContext, animation, secondaryAnimation);
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/glass_menu.dart';
import 'package:niran/core/widgets/glass_dialog.dart';
import 'package:niran/core/widgets/snapshot_glass.dart';

void main() {
  testWidgets(
    'menu snapshot survives pop result until reverse transition ends',
    (tester) async {
      final boundary = GlobalKey();
      int? result;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: GlassSnapshotSource(
              boundaryKey: boundary,
              child: GlassSnapshotBoundary(
                key: boundary,
                child: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () async {
                        result = await showGlassMenu<int>(
                          context: context,
                          position: const Offset(300, 200),
                          items: const [
                            GlassMenuItem(
                              value: 7,
                              icon: Icons.done,
                              label: 'Return result',
                            ),
                          ],
                        );
                      },
                      child: const Text('Open menu'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open menu'));
      await tester.pump();
      // Image readback and FragmentProgram loading use real engine work.
      await tester.runAsync(() async {
        await warmSnapshotGlass();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byType(SnapshotGlassScope), findsOneWidget);
      final image = tester
          .widget<SnapshotGlassScope>(find.byType(SnapshotGlassScope))
          .snapshot;
      expect(image.isDisposed, isFalse);
      await tester.tap(find.text('Return result'));
      await tester.pump(const Duration(milliseconds: 20));
      expect(result, 7);
      expect(
        image.isDisposed,
        isFalse,
        reason: 'Route is still drawing closing frames',
      );
      await tester.pumpAndSettle();
      expect(image.isDisposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dialog without a capture source retains safe ordinary glass', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showNirangDialog<void>(
                  context: context,
                  builder: (context) =>
                      const NirangAlertDialog(title: Text('Fallback dialog')),
                ),
                child: const Text('Open dialog'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Fallback dialog'), findsOneWidget);
    expect(find.byType(SnapshotGlassScope), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

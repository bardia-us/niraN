import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/glass_menu.dart';
import 'package:niran/core/widgets/glass_surface.dart';
import 'package:niran/core/widgets/glass_dialog.dart';

void main() {
  testWidgets(
    'popup has no dim and its anchor does not move during animation',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showGlassMenu(
                    context: context,
                    position: const Offset(400, 300),
                    items: const [
                      GlassMenuItem(
                        value: 1,
                        icon: Icons.edit,
                        label: 'Popup item',
                      ),
                    ],
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      final barriers = tester.widgetList<ModalBarrier>(
        find.byType(ModalBarrier),
      );
      expect(barriers.every((b) => (b.color?.a ?? 0) == 0), isTrue);
      final positioned = tester.getTopRight(find.byType(Positioned).last);
      final glassRect = tester.getRect(find.byType(GlassSurface));
      expect(
        tester.widget<GlassSurface>(find.byType(GlassSurface)).liveLiquid,
        isTrue,
        reason: 'Config menus must opt in to the live lens too',
      );
      await tester.pumpAndSettle();
      expect(tester.getTopRight(find.byType(Positioned).last), positioned);
      expect(
        tester.getRect(find.byType(GlassSurface)),
        glassRect,
        reason: 'Animate menu contents, not the live backdrop sampling bounds',
      );
      expect(find.text('Popup item'), findsOneWidget);
    },
  );
  testWidgets('settings dialogs opt in to the same live material', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: NirangAlertDialog(
              title: Text('Language'),
              content: Text('English / فارسی'),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<GlassSurface>(find.byType(GlassSurface)).liveLiquid,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}

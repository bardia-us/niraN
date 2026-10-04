import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:niran/core/widgets/glass_surface.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/main.dart';
import 'home_canvas_test.dart' show CanvasController;

void main() {
  testWidgets(
    'Servers header and action control request the live lens, rows stay flat',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(() => CanvasController()),
          ],
          child: const NirangApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Servers').last);
      await tester.pumpAndSettle();
      final header = find.ancestor(
        of: find.byKey(const Key('servers-toolbar')),
        matching: find.byType(GlassSurface),
      );
      final button = find.descendant(
        of: find.byKey(const Key('servers-menu-button')),
        matching: find.byType(GlassSurface),
      );
      expect(tester.widget<GlassSurface>(header).liveLiquid, isTrue);
      expect(tester.widget<GlassSurface>(button).liveLiquid, isTrue);
      // Real consumers must forward the midpoint recipe, not just opt into a
      // renderer whose isolated unit test happened to receive the right values.
      expect(tester.widget<GlassSurface>(header).blur, 2.4);
      expect(
        find.descendant(
          of: find.byKey(const Key('servers-menu-button')),
          matching: find.byType(glass.GlassMenu),
        ),
        findsOneWidget,
      );
      final rowSurfaces = tester.widgetList<GlassSurface>(
        find.ancestor(
          of: find.byKey(const ValueKey('server-row-a')),
          matching: find.byType(GlassSurface),
        ),
      );
      expect(rowSurfaces, isNotEmpty);
      expect(
        rowSurfaces.every((s) => s.style == GlassSurfaceStyle.flat),
        isTrue,
      );
      expect(rowSurfaces.every((s) => !s.liveLiquid), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

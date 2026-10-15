import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/detail_page_header.dart';
import 'package:niran/core/widgets/glass_surface.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/core/widgets/simple_frosted_surface.dart';
import 'package:niran/core/widgets/snapshot_glass_route.dart';
import 'package:niran/core/widgets/clay_surface.dart';
import 'package:niran/core/widgets/interactive_depth.dart';
import 'package:niran/core/widgets/glass_dialog.dart';
import 'package:niran/core/widgets/glass_menu.dart';

Widget _app(
  Widget child, {
  bool lightweight = true,
  Brightness brightness = Brightness.light,
}) => ProviderScope(
  overrides: [performanceModeProvider.overrideWithValue(lightweight)],
  child: MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(body: child),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    for (final menu in [false, true]) {
      testWidgets(
        'lightweight ${menu ? 'menu' : 'settings dialog'} is fully opaque in $brightness',
        (tester) async {
          await tester.pumpWidget(
            _app(
              Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    if (menu) {
                      showGlassMenu(
                        context: context,
                        position: const Offset(180, 100),
                        items: const [
                          GlassMenuItem(
                            value: 1,
                            icon: Icons.edit,
                            label: 'Choice',
                          ),
                        ],
                      );
                    } else {
                      showNirangDialog(
                        context: context,
                        builder: (_) => const NirangAlertDialog(
                          title: Text('Choice'),
                          content: Text('Settings content'),
                        ),
                      );
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
              brightness: brightness,
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final panel =
              tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: find.byType(GlassSurface),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration;
          expect(panel.color!.a, 1);
          expect(find.byType(BackdropFilter), findsNothing);
          expect(find.text('Choice'), findsOneWidget);
        },
      );
    }
  }

  testWidgets(
    'lightweight server row preserves normal palette and selected tint',
    (tester) async {
      const row = GlassSurface(
        style: GlassSurfaceStyle.flat,
        overlayColor: Color(0x331234FF),
        child: Text('Selected server'),
      );
      BoxDecoration rowDecoration() =>
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(GlassSurface),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      await tester.pumpWidget(_app(row, lightweight: false));
      final normal = rowDecoration();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(row));
      expect(rowDecoration().color, normal.color);
      expect(rowDecoration().border, normal.border);
      expect(find.byType(BackdropFilter), findsNothing);
    },
  );
  testWidgets(
    'all lightweight modal callers skip background capture by default',
    (tester) async {
      var captures = 0;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showSnapshotGlassRoute<void>(
                context: context,
                transitionDuration: const Duration(milliseconds: 180),
                snapshotPreparation: (context, {region}) async {
                  captures++;
                  return null;
                },
                pageBuilder: (context, animation, secondary) =>
                    const Center(child: Text('Panel ready')),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Panel ready'), findsOneWidget);
      expect(captures, 0);
    },
  );
  testWidgets('lightweight operation messages do not blur the backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const SimpleFrostedSurface(child: Text('Done'))),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });
  testWidgets('lightweight detail header alone has a clipped modest blur', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const DetailPageHeader(title: 'Details')));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(BackdropFilter),
        matching: find.byType(ClipRect),
      ),
      findsWidgets,
    );
    expect(find.text('Details'), findsOneWidget);
  });

  testWidgets(
    'lightweight raised controls retain clay depth without soft shadows',
    (tester) async {
      await tester.pumpWidget(
        _app(const ClaySurface(raised: true, child: Text('Proxy'))),
      );
      final box =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(ClaySurface),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(box.gradient, isA<LinearGradient>());
      expect(box.border, isNotNull);
      expect(box.boxShadow, isNotEmpty);
      expect(box.boxShadow!.every((shadow) => shadow.blurRadius == 0), isTrue);
      expect(find.byType(BackdropFilter), findsNothing);
    },
  );

  testWidgets('lightweight press has transform feedback and retains tap', (
    tester,
  ) async {
    var clicks = 0;
    await tester.pumpWidget(
      _app(
        Center(
          child: InteractiveDepth(
            child: TextButton(
              onPressed: () => clicks++,
              child: const Text('Run'),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Run')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final animated = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(InteractiveDepth),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(animated.transform!.entry(0, 0), lessThan(1));
    final decoration = animated.decoration as BoxDecoration;
    expect(
      decoration.boxShadow?.every((shadow) => shadow.blurRadius == 0) ?? true,
      isTrue,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(clicks, 1);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('lightweight glass keeps subtle transparency without filtering', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const GlassSurface(child: Text('Readable'))));
    final surface = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(GlassSurface),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = surface.decoration as BoxDecoration;
    expect(decoration.color!.a, lessThan(1));
    expect(decoration.color!.a, greaterThan(.8));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Readable'), findsOneWidget);
  });
}

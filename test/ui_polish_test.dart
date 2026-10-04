import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:niran/core/localization/app_strings.dart';
import 'package:niran/core/theme/app_theme.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/features/vpn/home_screen.dart';
import 'package:niran/features/logs/logs_screen.dart';

import 'home_canvas_test.dart' show CanvasController;

class UsageController extends CanvasController {
  @override
  Future<AppSnapshot> build() async => (await super.build()).copyWith(
    usage: const SubscriptionUsage(used: 25, total: 100, remaining: 75),
  );
}

Future<void> mount(
  WidgetTester tester,
  Widget body, {
  bool usage = false,
  CanvasController? controller,
}) async {
  tester.view.physicalSize = const Size(1180, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appControllerProvider.overrideWith(
          () => controller ?? (usage ? UsageController() : CanvasController()),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(body: body),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Logs allows manual text selection instead of only selecting a row',
    (tester) async {
      await mount(tester, const LogsScreen());
      expect(find.byType(SelectionArea), findsWidgets);
    },
  );
  testWidgets('log ink is owned and clipped by its own row', (tester) async {
    await mount(tester, const LogsScreen());
    final text = find.text('Recorded event 29');
    final material = tester.widget<Material>(
      find.ancestor(of: text, matching: find.byType(Material)).first,
    );
    expect(material.clipBehavior, isNot(Clip.none));
  });
  testWidgets(
    'subscription summary has no internal scroll and replay returns to actual usage',
    (tester) async {
      await mount(tester, const HomeScreen(), usage: true);
      final tile = find.byKey(const Key('home-tile-subscription'));
      expect(
        find.descendant(of: tile, matching: find.byType(Scrollable)),
        findsNothing,
      );
      final progress = find.descendant(
        of: tile,
        matching: find.byType(LinearProgressIndicator),
      );
      expect(tester.widget<LinearProgressIndicator>(progress).value, .25);
      await tester.tap(progress);
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester.widget<LinearProgressIndicator>(progress).value,
        lessThan(.25),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<LinearProgressIndicator>(progress).value, .25);
      expect(tester.takeException(), isNull);
    },
  );
}

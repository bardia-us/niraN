import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/localization/app_strings.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/features/settings/settings_screen.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/features/vpn/app_shell.dart';

class _Controller extends AppController {
  int updates = 0, restarts = 0;
  @override
  Future<AppSnapshot> build() async => const AppSnapshot();
  @override
  Future<void> updateSettings(Map<String, Object?> values) async {
    updates++;
    state = AsyncData(
      state.asData!.value.copyWith(
        settings: state.asData!.value.settings.withUpdates(values),
      ),
    );
  }

  @override
  Future<void> restartApplication() async => restarts++;
}

Future<void> _open(WidgetTester tester, _Controller controller) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith(() => controller)],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [AppStrings.delegate],
        home: Scaffold(body: SettingsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lightweight shell never requests optional snapshot programs', (
    tester,
  ) async {
    var preparations = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => _Controller()),
          performanceModeProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppStrings.delegate],
          home: AppShell(
            prepareSnapshot: () async {
              preparations++;
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
    expect(preparations, 0);
    expect(find.byType(BackdropFilter), findsOneWidget); // Upper header only.
  });
  testWidgets(
    'performance change requires confirmation before saving or restart',
    (tester) async {
      final controller = _Controller();
      await _open(tester, controller);
      expect(find.text('Performance Mode'), findsOneWidget);
      await tester.tap(find.byKey(const Key('performance-mode-switch')));
      await tester.pumpAndSettle();
      expect(controller.updates, 0);
      expect(controller.restarts, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.updates, 0);
      expect(controller.restarts, 0);
    },
  );

  testWidgets(
    'confirmed performance change saves before restart without hot rendering swap',
    (tester) async {
      final controller = _Controller();
      await _open(tester, controller);
      await tester.tap(find.byKey(const Key('performance-mode-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply & restart'));
      await tester.pumpAndSettle();
      expect(controller.updates, 1);
      expect(controller.restarts, 1);
      expect(controller.state.asData!.value.settings.performanceMode, true);
      final context = tester.element(find.byType(SettingsScreen));
      expect(
        ProviderScope.containerOf(context).read(performanceModeProvider),
        false,
      );
    },
  );
}

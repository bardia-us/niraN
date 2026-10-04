import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/desktop_feedback.dart';
import 'package:niran/core/widgets/glass_dialog.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/main.dart';

import 'home_refinement_test.dart' show HomeController;
import 'support/pump_glass_route.dart';

void main() {
  setUpAll(() async {
    await warmGlassRouteTests();
    await DesktopFeedback.cueForStyle('notification');
  });
  late List<MethodCall> audioCalls;
  const channel = MethodChannel('dev.niran.windows/host');
  setUp(() {
    audioCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'showDesktopFeedback') audioCalls.add(call);
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'sound choice Cancel preserves settings and Apply saves Classic',
    (tester) async {
      final controller = HomeController();
      await _mountAppearance(tester, controller);
      audioCalls.clear();
      await _openSoundChoice(tester);
      final dialog = find.byType(NirangAlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Soft pop')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Classic niraN')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Classic niraN')),
      );
      await tester.pump();
      expect(controller.saves, 0);
      expect(
        controller.state.asData!.value.settings.soundStyle,
        'notification',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(controller.saves, 0);
      expect(
        controller.state.asData!.value.settings.soundStyle,
        'notification',
      );
      expect(audioCalls.length, 0);

      await _openSoundChoice(tester);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Classic niraN')),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(controller.saves, 1);
      expect(controller.state.asData!.value.settings.soundStyle, 'classic');
      expect(find.byType(NirangAlertDialog), findsNothing);
      expect(find.text('Classic niraN'), findsOneWidget);
      expect(audioCalls, hasLength(1));
      _expectClassicPayload(audioCalls.single);

      await _openSoundChoice(tester);
      final classicTile = find.ancestor(
        of: find.descendant(of: dialog, matching: find.text('Classic niraN')),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: classicTile,
          matching: find.byIcon(Icons.radio_button_checked_rounded),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(controller.saves, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Preview sends the selected Classic cue to the native channel', (
    tester,
  ) async {
    final controller = HomeController();
    await _mountAppearance(tester, controller);
    await controller.updateSettings({'soundStyle': 'classic'});
    await tester.pumpAndSettle();
    audioCalls.clear();
    await tester.tap(find.byTooltip('Preview sound'));
    await tester.pumpAndSettle();
    expect(audioCalls, hasLength(1));
    _expectClassicPayload(audioCalls.single);
    expect(controller.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mute disables sound choice and Preview without sending audio', (
    tester,
  ) async {
    final controller = HomeController();
    await _mountAppearance(tester, controller);
    audioCalls.clear();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Interaction sounds'));
    await tester.pumpAndSettle();
    expect(controller.state.asData!.value.settings.soundEffects, false);
    expect(controller.saves, 1);
    final preview = find.ancestor(
      of: find.byIcon(Icons.play_circle_outline_rounded),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(preview).onPressed, isNull);
    final choice = find.ancestor(
      of: find.text('Feedback sound'),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(choice).enabled, false);
    await tester.tap(find.byTooltip('Preview sound'));
    await tester.tap(find.text('Feedback sound'));
    await tester.pumpAndSettle();
    expect(audioCalls.length, 0);
    expect(find.byType(NirangAlertDialog), findsNothing);
    expect(controller.state.asData!.value.settings.soundStyle, 'notification');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mountAppearance(
  WidgetTester tester,
  HomeController controller,
) async {
  tester.view.physicalSize = const Size(1180, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith(() => controller)],
      child: const NirangApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('APPEARANCE'),
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(
    tester.element(find.text('APPEARANCE')),
    alignment: .4,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('APPEARANCE'));
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(
    tester.element(find.text('Feedback sound')),
    alignment: .4,
  );
  await tester.pumpAndSettle();
}

Future<void> _openSoundChoice(WidgetTester tester) async {
  await tester.tap(find.text('Feedback sound'));
  await pumpGlassRoute(tester, find.byType(NirangAlertDialog));
}

void _expectClassicPayload(MethodCall call) {
  expect(call.method, 'showDesktopFeedback');
  final arguments = call.arguments as Map;
  expect(arguments['notification'], false);
  // The generator itself is independently covered by the PCM tests. This
  // boundary verifies that UI selection reaches native playback unchanged.
  expect(arguments['sound'], isA<Uint8List>());
  expect(arguments['sound'], orderedEquals(DesktopFeedback.classicCue()));
}

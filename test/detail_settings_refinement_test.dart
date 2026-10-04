import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/localization/app_strings.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/features/servers/server_information_screen.dart';
import 'package:niran/features/servers/server_profile_settings_screen.dart';
import 'package:niran/features/settings/settings_screen.dart';
import 'package:niran/features/vpn/app_controller.dart';

ServerInfo _server(String security) => ServerInfo(
  id: 'sample',
  name: 'Sample',
  country: 'DE',
  protocol: 'VLESS',
  transport: 'TCP',
  security: security,
  port: 443,
  selected: true,
  status: 'idle',
  fingerprint: 'chrome',
  cipherSuites: 'TLS_AES_128_GCM_SHA256',
  finalMask: '{"tcp":[]}',
  realityPublicKeyMasked: 'masked-key',
  shortIdMasked: 'masked-id',
);

class _Controller extends AppController {
  _Controller({this.settings = const NativeSettings()});

  final NativeSettings settings;
  Map<String, String>? profileUpdate;

  @override
  Future<AppSnapshot> build() async => AppSnapshot(settings: settings);

  @override
  Future<void> updateServerProfile(
    String id,
    Map<String, String> values,
  ) async {
    profileUpdate = values;
  }
}

Widget _app(Widget child, {_Controller? controller, bool dark = false}) =>
    ProviderScope(
      overrides: [
        if (controller != null)
          appControllerProvider.overrideWith(() => controller),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppStrings.delegate],
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('TLS fields are visible after general info without expansion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        ServerInformationScreen(
          server: _server('TLS'),
          controller: _Controller(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(
      tester.getTopLeft(find.text('General information')).dy,
      lessThan(tester.getTopLeft(find.byType(TextField).first).dy),
    );
    // One flat section owns the editor; it does not nest card surfaces.
    final editor = find.byType(ServerProfileSettingsScreen);
    expect(
      find.ancestor(of: editor, matching: find.byType(Card)),
      findsOneWidget,
    );
  });

  testWidgets('Reality exposes only fingerprint and preserves hidden options', (
    tester,
  ) async {
    final controller = _Controller();
    await tester.pumpWidget(
      _app(
        ServerProfileSettingsScreen(
          server: _server('Reality'),
          controller: controller,
          embedded: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('FinalMask JSON'), findsNothing);
    await tester.enterText(find.byType(TextField), 'firefox');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.profileUpdate, {
      'fp': 'firefox',
      'cs': 'TLS_AES_128_GCM_SHA256',
      'fm': '{"tcp":[]}',
    });
  });

  testWidgets('Reality rejects the TLS-only unsafe fingerprint', (
    tester,
  ) async {
    final controller = _Controller();
    await tester.pumpWidget(
      _app(
        ServerProfileSettingsScreen(
          server: _server('Reality'),
          controller: controller,
          embedded: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'unsafe');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.profileUpdate, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.errorText,
      isNotNull,
    );
  });

  for (final dark in [false, true]) {
    testWidgets('dark canvas editor follows effective brightness: $dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _Controller(
        settings: const NativeSettings(themeMode: 'system'),
      );
      await tester.pumpWidget(
        _app(const SettingsScreen(), controller: controller, dark: dark),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('APPEARANCE'),
        700,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('APPEARANCE'));
      await tester.pumpAndSettle();
      final tile = find.ancestor(
        of: find.text('Dark canvas'),
        matching: find.byType(ListTile),
      );
      final widget = tester.widget<ListTile>(tile);
      expect(widget.enabled, dark);
      expect(widget.onTap == null, !dark);
      expect(find.text('Performance Mode'), findsNothing);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/localization/app_strings.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/features/servers/server_information_screen.dart';
import 'package:niran/features/servers/server_profile_settings_screen.dart';
import 'package:niran/features/settings/settings_screen.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/core/widgets/profile_choice_field.dart';
import 'package:niran/core/widgets/detail_page_header.dart';
import 'package:niran/core/widgets/glass_surface.dart';
import 'package:niran/core/widgets/settings_group.dart';
import 'package:niran/core/windows_update_manager.dart';

ServerInfo _server(String security, {String fingerprint = 'chrome'}) =>
    ServerInfo(
      id: 'sample',
      name: 'Sample',
      country: 'DE',
      protocol: 'VLESS',
      transport: 'TCP',
      security: security,
      port: 443,
      selected: true,
      status: 'idle',
      fingerprint: fingerprint,
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
  testWidgets(
    'first Settings mount consumes an already requested download focus',
    (tester) async {
      WindowsUpdateManager.instance.requestManagerFocus();
      await tester.pumpWidget(
        _app(const SettingsScreen(), controller: _Controller()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check for updates'), findsOneWidget);
    },
  );
  testWidgets(
    'selected badge gives a short pulse without changing profile data',
    (tester) async {
      final controller = _Controller();
      await tester.pumpWidget(
        _app(
          ServerInformationScreen(
            server: _server('none'),
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selected = find.text('Selected');
      final before = tester.getRect(selected);
      await tester.tap(selected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getRect(selected).width, greaterThan(before.width));
      await tester.pumpAndSettle();
      expect(tester.getRect(selected).width, closeTo(before.width, .1));
      expect(controller.profileUpdate, isNull);
    },
  );
  testWidgets('detail header uses plain translucency without liquid optics', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(ServerInformationScreen(server: _server('none'))),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DetailPageHeader),
        matching: find.byType(GlassSurface),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(DetailPageHeader),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
  });
  for (final security in ['', 'none']) {
    testWidgets('unencrypted $security profile has no TLS editor', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ServerInformationScreen(
            server: _server(security),
            controller: _Controller(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ServerProfileSettingsScreen), findsNothing);
      expect(find.text('ECH Config List'), findsNothing);
    });
  }

  testWidgets('TLS selection is a compact rounded glass panel', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        ServerProfileSettingsScreen(
          server: _server('TLS'),
          controller: _Controller(),
          embedded: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-alpn')));
    await tester.pumpAndSettle();
    final option = find.text('http/1.1');
    expect(option, findsOneWidget);
    expect(tester.getSize(option).width, lessThan(400));
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    final ink = tester.widget<InkWell>(
      find.ancestor(of: option, matching: find.byType(InkWell)).first,
    );
    expect(ink.borderRadius, isNotNull);
  });

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
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.byType(ProfileChoiceField), findsNWidgets(2));
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
    await tester.tap(find.byKey(const Key('profile-fingerprint')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('firefox').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.profileUpdate, {
      'fp': 'firefox',
      'cs': 'TLS_AES_128_GCM_SHA256',
      'fm': '{"tcp":[]}',
      'sni': '',
    });
  });

  testWidgets('Reality rejects the TLS-only unsafe fingerprint', (
    tester,
  ) async {
    final controller = _Controller();
    await tester.pumpWidget(
      _app(
        ServerProfileSettingsScreen(
          server: _server('Reality', fingerprint: 'unsafe'),
          controller: controller,
          embedded: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dropdown = tester.widget<ProfileChoiceField>(
      find.byType(ProfileChoiceField),
    );
    expect(dropdown.values.contains('unsafe'), isFalse);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.profileUpdate, isNull);
    expect(
      tester
          .widget<ProfileChoiceField>(find.byType(ProfileChoiceField))
          .errorText,
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
      expect(
        find.descendant(
          of: find.widgetWithText(SettingsGroup, 'APPEARANCE'),
          matching: find.text('Performance Mode'),
        ),
        findsNothing,
      );
    });
  }
}

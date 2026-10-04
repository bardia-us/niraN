import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/features/vpn/home_screen.dart';
import 'package:niran/main.dart';

class HomeController extends AppController {
  HomeController({
    this.legacyPerformance = false,
    this.language = 'en',
    this.connection = const ConnectionInfo(),
  });
  final bool legacyPerformance;
  final String language;
  final ConnectionInfo connection;
  int operationCalls = 0;
  @override
  Future<void> connect() async {
    operationCalls++;
  }

  @override
  Future<void> clearSystemProxy() async {
    operationCalls++;
  }

  int saves = 0;
  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    appVersion: '',
    connection: connection,
    settings: NativeSettings(
      performanceMode: legacyPerformance,
      performanceModePrompted: true,
      themeMode: 'light',
      language: language,
    ),
    servers: const [
      ServerInfo(
        id: 'a',
        name: '🇮🇷 آلمان نیم بها 🇩🇪',
        country: 'DE',
        port: 443,
        protocol: 'VLESS',
        transport: 'XHTTP',
        security: 'TLS',
        selected: true,
        ping: 92,
        status: 'success',
      ),
    ],
  );
  @override
  Future<void> updateSettings(Map<String, Object?> values) async {
    saves++;
    final app = state.asData!.value;
    state = AsyncData(app.copyWith(settings: app.settings.withUpdates(values)));
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    HomeController controller, {
    Size size = const Size(1180, 760),
  }) async {
    tester.view.physicalSize = size;
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
  }

  for (final size in [
    const Size(800, 600),
    const Size(1180, 760),
    const Size(1920, 1080),
  ]) {
    testWidgets('Home stays bounded without outer scrolling at $size', (
      tester,
    ) async {
      await mount(tester, HomeController(), size: size);
      expect(
        find.ancestor(
          of: find.byKey(const Key('home-desktop-grid')),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      final content = tester.getRect(find.byKey(const Key('home-content')));
      expect(content.width, lessThanOrEqualTo(1160));
      expect(content.height, lessThanOrEqualTo(760));
    });
  }
  testWidgets('legacy Windows performance flag does not disable effects', (
    tester,
  ) async {
    await mount(tester, HomeController(legacyPerformance: true));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    expect(container.read(performanceModeProvider), isFalse);
    expect(find.text('Performance mode'), findsNothing);
  });
  testWidgets(
    'Persian connected edit mode fits minimum Windows size and Cancel stays unsaved',
    (tester) async {
      final controller = HomeController(
        language: 'fa',
        connection: const ConnectionInfo(
          state: 'connected',
          publicIp: '2001:db8:1:2:3:4:5:6',
          publicCountry: 'DE',
          publicCity: 'Frankfurt',
          publicIpChecked: true,
          error:
              'A retained diagnostic with a long explanation that must not overflow',
        ),
      );
      await mount(tester, controller, size: const Size(800, 600));
      await tester.tap(find.byKey(const Key('customize-home')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('cancel-home-edit')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('remove-home-logs')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('cancel-home-edit')));
      await tester.pumpAndSettle();
      expect(controller.saves, 0);
      expect(find.byKey(const Key('home-tile-logs')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

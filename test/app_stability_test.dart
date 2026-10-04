import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/core/widgets/glass_dialog.dart';
import 'package:niran/core/widgets/country_flag_badge.dart';
import 'package:niran/core/widgets/glass_surface.dart';
import 'package:niran/core/widgets/interactive_depth.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/main.dart';

import 'support/pump_glass_route.dart';

const _serverA = ServerInfo(
  id: 'a',
  name: 'Server A',
  country: 'DE',
  protocol: 'VLESS',
  transport: 'TCP',
  security: 'Reality',
  port: 443,
  selected: true,
  status: 'success',
  ping: 120,
);

const _serverB = ServerInfo(
  id: 'b',
  name: 'Server B',
  country: 'US',
  protocol: 'VLESS',
  transport: 'XHTTP',
  security: 'TLS',
  port: 443,
  selected: false,
  status: 'idle',
);

const _serverC = ServerInfo(
  id: 'c',
  name: 'Server C',
  country: 'NL',
  protocol: 'Trojan',
  transport: 'TCP',
  security: 'TLS',
  port: 443,
  selected: false,
  status: 'idle',
);

class _FakeAppController extends AppController {
  _FakeAppController({
    this.language = 'en',
    this.logCount = 0,
    this.themeMode = 'system',
    this.performanceMode = false,
    this.connection = const ConnectionInfo(),
    this.initialServers = const [_serverA, _serverB],
  });

  final String language;
  final int logCount;
  final String themeMode;
  final bool performanceMode;
  final ConnectionInfo connection;
  final List<ServerInfo> initialServers;
  int pingRequests = 0;
  int settingsUpdates = 0;
  int logRefreshes = 0;
  int restartRequests = 0;
  int ipRefreshRequests = 0;

  @override
  Future<void> refreshPublicIp() async => ipRefreshRequests++;

  @override
  Future<void> deleteServer(String id) async {
    final current = state.asData!.value;
    state = AsyncData(
      current.copyWith(
        servers: current.servers.where((s) => s.id != id).toList(),
      ),
    );
  }

  final List<(int, int)> reorderRequests = [];

  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    servers: initialServers,
    connection: connection,
    subscriptionConfigured: true,
    settings: NativeSettings(
      connectionMode: 'vpn',
      language: language,
      routingMode: 'global',
      enableIpv6: false,
      themeMode: themeMode,
      performanceMode: performanceMode,
      performanceModePrompted: true,
    ),
    logs: List.generate(
      logCount,
      (index) => LogEntry(
        DateTime.fromMillisecondsSinceEpoch(1700000000000 + index),
        index.isEven ? 'info' : 'warning',
        'Log entry $index',
      ),
    ),
  );

  @override
  Future<void> selectServer(String id) async {
    final current = state.asData!.value;
    state = AsyncData(
      current.copyWith(
        servers: [
          for (final server in current.servers)
            server.copyWith(selected: server.id == id),
        ],
      ),
    );
  }

  @override
  Future<void> reorderServers(int oldIndex, int newIndex) async {
    reorderRequests.add((oldIndex, newIndex));
    final current = state.asData!.value;
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final servers = List<ServerInfo>.of(current.servers);
    final item = servers.removeAt(oldIndex);
    servers.insert(target, item);
    state = AsyncData(current.copyWith(servers: servers));
  }

  @override
  Future<void> updateSettings(Map<String, Object?> values) async {
    settingsUpdates++;
    final current = state.asData!.value;
    state = AsyncData(
      current.copyWith(settings: current.settings.withUpdates(values)),
    );
  }

  @override
  Future<void> restartService() async {
    restartRequests++;
  }

  @override
  Future<void> refreshLogs() async {
    logRefreshes++;
  }

  @override
  Future<void> clearLogs() async {
    final current = state.asData!.value;
    state = AsyncData(current.copyWith(logs: const []));
  }

  @override
  Future<void> pingServer(String id) async {
    pingRequests++;
    _updatePing(id, status: 'testing');
    await Future<void>.delayed(Duration.zero);
    _updatePing(id, status: 'success', ping: 90 + pingRequests);
  }

  void _updatePing(String id, {required String status, int? ping}) {
    final current = state.asData!.value;
    state = AsyncData(
      current.copyWith(
        servers: [
          for (final server in current.servers)
            server.id == id
                ? server.copyWith(status: status, ping: ping)
                : server,
        ],
      ),
    );
  }

  void emitServerUpdate(int value) {
    final current = state.asData!.value;
    state = AsyncData(
      current.copyWith(
        servers: [
          for (final server in current.servers)
            server.id == 'b'
                ? server.copyWith(status: 'success', ping: value)
                : server,
        ],
      ),
    );
  }
}

class _FreshStateController extends AppController {
  _FreshStateController({this.startupGate});

  final Future<void>? startupGate;

  @override
  Future<AppSnapshot> build() async {
    await startupGate;
    return const AppSnapshot(
      subscriptionConfigured: true,
      settings: NativeSettings(performanceModePrompted: true),
    );
  }
}

class _PerformancePromptController extends AppController {
  @override
  Future<AppSnapshot> build() async =>
      const AppSnapshot(settings: NativeSettings());

  @override
  Future<void> updateSettings(Map<String, Object?> values) async {
    final current = state.asData!.value;
    state = AsyncData(
      current.copyWith(settings: current.settings.withUpdates(values)),
    );
  }
}

void main() {
  setUpAll(warmGlassRouteTests);

  testWidgets('desktop and compact pages keep layout and sidebar preference', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final mode in ['light', 'dark']) {
      for (final width in [540.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 900);
        late _FakeAppController controller;
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey('$mode:$width'),
            overrides: [
              appControllerProvider.overrideWith(
                () => controller = _FakeAppController(themeMode: mode),
              ),
            ],
            child: const NirangApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('home-desktop-grid')), findsOneWidget);
        for (final destination in ['Servers', 'Settings', 'Logs', 'Home']) {
          await tester.tap(find.text(destination).last);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$mode/$width/$destination',
          );
        }
        if (width >= 1200) {
          final before = tester.getRect(find.byType(NavigationRail));
          await controller.updateSettings({'sidebarRight': true});
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byType(NavigationRail)).left,
            greaterThan(before.left),
          );
        }
      }
    }
  });

  testWidgets('public IP tap refreshes only while connected', (tester) async {
    late _FakeAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _FakeAppController(
              connection: const ConnectionInfo(state: 'connected'),
            ),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Public IP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Public IP'));
    await tester.pumpAndSettle();
    expect(controller.ipRefreshRequests, 1);
    expect(controller.restartRequests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed deletion collapses the row before removing its data', (
    tester,
  ) async {
    late _FakeAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _FakeAppController(),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servers').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await pumpGlassRoute(tester, find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await pumpGlassRoute(tester, find.widgetWithText(FilledButton, 'Delete'));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(controller.state.requireValue.servers.map((s) => s.id), ['b']);
    expect(find.text('Server A'), findsNothing);
    expect(find.text('Server B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('IP and ping cards align even when IP has a city subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(
              connection: const ConnectionInfo(
                state: 'connected',
                publicIp: '2001:db8::1',
                publicCity: 'Paris',
              ),
            ),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    final ip = find
        .ancestor(of: find.text('Public IP'), matching: find.byType(InkWell))
        .first;
    final ping = find
        .ancestor(of: find.text('Ping'), matching: find.byType(InkWell))
        .first;
    expect(tester.getRect(ip).height, tester.getRect(ping).height);
    expect(tester.getRect(ip).top, tester.getRect(ping).top);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all country flags survive a name with prefix middle and suffix flags',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(
              () => _FakeAppController(
                initialServers: const [
                  ServerInfo(
                    id: 'multi',
                    name: '🇩🇪 Frankfurt 🇫🇷 route 🇳🇱',
                    country: 'DE',
                    protocol: 'VLESS',
                    transport: 'TCP',
                    security: 'TLS',
                    port: 443,
                    selected: true,
                    status: 'idle',
                  ),
                ],
              ),
            ),
          ],
          child: const NirangApp(),
        ),
      );
      await tester.pumpAndSettle();
      final codes = tester
          .widgetList<CountryFlagBadge>(find.byType(CountryFlagBadge))
          .map((b) => b.countryCode)
          .toSet();
      expect(codes, containsAll(['DE', 'FR', 'NL']));
      expect(find.byType(CountryRemarkText), findsOneWidget);
      final remark = tester.widget<CountryRemarkText>(
        find.byType(CountryRemarkText),
      );
      expect(remark.remark, '🇩🇪 Frankfurt 🇫🇷 route 🇳🇱');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Windows no longer prompts for performance mode', (tester) async {
    late _PerformancePromptController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _PerformancePromptController(),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Performance Mode'), findsNothing);
    expect(find.text('Keep full effects'), findsNothing);

    expect(
      controller.state.asData!.value.settings.performanceModePrompted,
      isFalse,
    );
    expect(controller.state.asData!.value.settings.performanceMode, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fresh state renders before any subscription result exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_FreshStateController.new),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('niraN'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Local traffic usage'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup loading state stays responsive and completes cleanly', (
    tester,
  ) async {
    final gate = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FreshStateController(startupGate: gate.future),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exactly one server selection indicator follows selected state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(_FakeAppController.new)],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('—'), findsNothing);
    expect(
      tester.getCenter(find.byIcon(Icons.check_rounded)).dx,
      lessThan(400),
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Server A'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Server B'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Server B'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('servers header uses localized blur only with full effects', (
    tester,
  ) async {
    late _FakeAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _FakeAppController(themeMode: 'light'),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Servers (2)'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsWidgets);

    await controller.updateSettings({'performanceMode': true});
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsWidgets);
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await pumpGlassRoute(tester, find.text('Server information'));
    expect(find.text('Server information'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server reorder uses a held row without visible drag handles', (
    tester,
  ) async {
    late _FakeAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _FakeAppController(
              initialServers: const [_serverA, _serverB, _serverC],
            ),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(ReorderableDragStartListener), findsNothing);
    expect(find.byType(ReorderableDelayedDragStartListener), findsNWidgets(3));
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);
    for (final id in const ['a', 'b', 'c']) {
      final handle = find.byKey(ValueKey('server-drag-$id'));
      expect(handle, findsOneWidget);
      expect(tester.widget(handle), isA<ReorderableDelayedDragStartListener>());
    }
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Server A')),
    );
    await tester.pump(const Duration(milliseconds: 550));
    await gesture.moveBy(const Offset(0, 150));
    await tester.pump(const Duration(milliseconds: 220));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.reorderRequests, isNotEmpty);
    expect(controller.state.requireValue.servers.first.id, isNot('a'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('server rows share glass renderer and one-stage hover lift', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(initialServers: const [_serverA]),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();

    final depth = tester.widget<InteractiveDepth>(
      find.byKey(const ValueKey('server-depth-a')),
    );
    expect(depth.tiltEnabled, isFalse);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('server-row-a')),
        matching: find.byType(GlassSurface),
      ),
      findsOneWidget,
    );
    final rowGlass = tester.widget<GlassSurface>(
      find.ancestor(
        of: find.byKey(const ValueKey('server-row-a')),
        matching: find.byType(GlassSurface),
      ),
    );
    expect(rowGlass.style, GlassSurfaceStyle.flat);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server toolbar actions stay pinned to the far right', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final width in [480.0, 800.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 720);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(_FakeAppController.new),
          ],
          child: const NirangApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Servers').last);
      await tester.pumpAndSettle();

      final toolbar = tester.getRect(find.byKey(const Key('servers-toolbar')));
      final actions = tester.getRect(
        find.byKey(const Key('servers-toolbar-actions')),
      );
      expect(
        toolbar.right - actions.right,
        inInclusiveRange(8, 16),
        reason: '$width',
      );
      expect(tester.takeException(), isNull, reason: '$width');
    }
  });

  testWidgets('country flags render from bundled assets, not system emoji', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CountryFlagBadge(countryCode: 'NL', width: 29, height: 21),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('NL'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile TLS editor validates FinalMask JSON before saving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(_FakeAppController.new)],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert_rounded).at(1));
    await pumpGlassRoute(tester, find.text('Server information'));
    expect(find.text('Profile TLS/CDN settings'), findsNothing);
    await tester.tap(find.text('Server information'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Profile TLS/CDN settings'));
    await tester.pumpAndSettle();

    expect(find.text('Fingerprint'), findsOneWidget);
    expect(find.text('Cipher suites'), findsOneWidget);
    expect(find.text('FinalMask JSON'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(2), '{bad json');
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Invalid JSON'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public IP and existing geo metadata render without ellipsis', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(
              connection: const ConnectionInfo(
                state: 'connected',
                publicIp: '213.165.41.160',
                publicCountry: 'NL',
                publicCity: 'Amsterdam',
              ),
            ),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('(NL) 213.165.41.160'), findsOneWidget);
    expect(find.text('Amsterdam'), findsOneWidget);
    final ipText = tester.widget<Text>(find.text('(NL) 213.165.41.160'));
    expect(ipText.overflow, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restart service is offered only for a connected VPN', (
    tester,
  ) async {
    late _FakeAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _FakeAppController(
              connection: const ConnectionInfo(
                state: 'connected',
                serverId: 'a',
                serverName: 'Server A',
              ),
            ),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Restart Service'), findsOneWidget);
    await tester.tap(find.text('Restart Service'));
    await tester.pump();
    expect(controller.restartRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restart card stays visible and disabled during a restart transition',
    (tester) async {
      late _FakeAppController controller;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(
              () => controller = _FakeAppController(
                connection: const ConnectionInfo(
                  state: 'restarting',
                  serverId: 'a',
                  serverName: 'Server A',
                ),
              ),
            ),
          ],
          child: const NirangApp(),
        ),
      );
      await tester.pump();

      final restart = find.text('Restart Service');
      expect(restart, findsOneWidget);
      final action = find
          .ancestor(of: restart, matching: find.byType(InkWell))
          .first;
      expect(tester.widget<InkWell>(action).onTap, isNull);
      await tester.tap(restart);
      await tester.pump();
      expect(controller.restartRequests, 0);
      expect(find.text('Restarting…'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings picker cancel discards changes and apply commits once',
    (tester) async {
      late _FakeAppController controller;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(
              () => controller = _FakeAppController(),
            ),
          ],
          child: const NirangApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await _expandSettingsSection(tester, 'Appearance');
      await tester.scrollUntilVisible(
        find.text('Theme'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Theme')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme'));
      await pumpGlassRoute(tester, find.byType(NirangAlertDialog));
      await tester.tap(find.text('Dark'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.settingsUpdates, 0);
      expect(controller.state.asData!.value.settings.themeMode, 'system');
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('Theme'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Theme')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme'));
      await pumpGlassRoute(tester, find.byType(NirangAlertDialog));
      await tester.tap(find.text('Dark'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(controller.settingsUpdates, 1);
      expect(controller.state.asData!.value.settings.themeMode, 'dark');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('DNS fields validate, cancel safely, and update independently', (
    tester,
  ) async {
    late _FakeAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _FakeAppController(),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await _expandSettingsSection(tester, 'DNS');
    await tester.scrollUntilVisible(
      find.text('Remote DNS'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Remote DNS')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remote DNS'));
    await pumpGlassRoute(tester, find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'not a dns value');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      find.text('Enter a valid IP address or DNS hostname.'),
      findsOneWidget,
    );
    expect(controller.settingsUpdates, 0);

    await tester.enterText(find.byType(TextFormField), '9.9.9.9');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.settingsUpdates, 0);

    await tester.scrollUntilVisible(
      find.text('Remote DNS'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Remote DNS')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remote DNS'));
    await pumpGlassRoute(tester, find.byType(TextFormField));
    await tester.enterText(
      find.byType(TextFormField),
      '9.9.9.9,https://dns.google/dns-query',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(controller.settingsUpdates, 1);
    expect(
      controller.state.asData!.value.settings.remoteDns,
      '9.9.9.9,https://dns.google/dns-query',
    );
    expect(controller.state.asData!.value.settings.enableLocalDns, isTrue);
    expect(controller.state.asData!.value.settings.enableFakeDns, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'advanced resolution strategy menus expose ordered IPv4 and IPv6 fallback',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(() => _FakeAppController()),
          ],
          child: const NirangApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await _expandSettingsSection(
        tester,
        'Advanced settings',
        visibleChild: 'Proxy target resolution',
      );
      await tester.scrollUntilVisible(
        find.text('Proxy target resolution'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Proxy target resolution')),
        alignment: .4,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proxy target resolution'));
      await pumpGlassRoute(tester, find.text('IPv4, then IPv6'));

      expect(find.text('IPv4, then IPv6'), findsOneWidget);
      expect(find.text('IPv6, then IPv4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'MTU validates, cancels, applies, and reopens with synced state',
    (tester) async {
      late _FakeAppController controller;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(
              () => controller = _FakeAppController(),
            ),
          ],
          child: const NirangApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await _expandSettingsSection(
        tester,
        'Advanced settings',
        visibleChild: 'VPN MTU',
      );
      await tester.scrollUntilVisible(
        find.text('VPN MTU'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('VPN MTU')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('VPN MTU'), warnIfMissed: true);
      await pumpGlassRoute(tester, find.byType(TextFormField));

      await tester.enterText(find.byType(TextFormField), '100');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Valid range: 1280–9000'), findsWidgets);
      expect(controller.settingsUpdates, 0);

      await tester.enterText(find.byType(TextFormField), '1400');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.state.asData!.value.settings.vpnMtu, 1500);

      await Scrollable.ensureVisible(
        tester.element(find.text('VPN MTU')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('VPN MTU'), warnIfMissed: true);
      await pumpGlassRoute(tester, find.byType(TextFormField));
      await tester.enterText(find.byType(TextFormField), '1400');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.state.asData!.value.settings.vpnMtu, 1400);
      expect(find.textContaining('1400'), findsOneWidget);

      await Scrollable.ensureVisible(
        tester.element(find.text('VPN MTU')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('VPN MTU'), warnIfMissed: true);
      await pumpGlassRoute(tester, find.byType(TextFormField));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '1400',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('independent routing switches and domain strategy sync apply', (
    tester,
  ) async {
    late _FakeAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _FakeAppController(),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await _expandSettingsSection(tester, 'Routing');
    await tester.scrollUntilVisible(
      find.text('Bypass Iran'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    // Settings now scrolls behind the AppBar: place the tap below the chrome.
    await Scrollable.ensureVisible(
      tester.element(find.text('Bypass Iran')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bypass Iran'), warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(controller.state.asData!.value.settings.bypassIran, isFalse);
    expect(controller.state.asData!.value.settings.customRulesEnabled, isFalse);
    await tester.tap(find.text('Bypass Iran'));
    await tester.pumpAndSettle();
    expect(controller.state.asData!.value.settings.bypassIran, isTrue);

    await Scrollable.ensureVisible(
      tester.element(find.text('ROUTING')),
      alignment: .35,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ROUTING'));
    await tester.pumpAndSettle();
    await _expandSettingsSection(
      tester,
      'DNS',
      visibleChild: 'Domain strategy',
    );
    await tester.scrollUntilVisible(
      find.text('Domain strategy'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Domain strategy')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Domain strategy'));
    await pumpGlassRoute(tester, find.text('IPOnDemand'));
    await tester.tap(find.text('IPOnDemand').last);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
      controller.state.asData!.value.settings.domainStrategy,
      'IPOnDemand',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('log viewer repeatedly opens and scrolls with capped entries', (
    tester,
  ) async {
    late _FakeAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _FakeAppController(logCount: 250),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();

    for (var iteration = 0; iteration < 4; iteration++) {
      await tester.tap(find.byIcon(Icons.article_outlined));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.home_outlined));
      await tester.pumpAndSettle();
    }

    expect(controller.logRefreshes, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection indicator stays at the directional start in RTL', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(language: 'fa'),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.check_rounded)).dx,
      greaterThan(400),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('home ping is interactive and repeated taps remain responsive', (
    tester,
  ) async {
    late _FakeAppController controller;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => controller = _FakeAppController(),
          ),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('120 ms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('120 ms'));
    await tester.tap(find.text('120 ms'));
    await tester.pumpAndSettle();

    expect(controller.pingRequests, 2);
    expect(find.text('92 ms'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'server events do not rebuild MaterialApp while a settings dialog is open',
    (tester) async {
      late _FakeAppController controller;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(
              () => controller = _FakeAppController(),
            ),
          ],
          child: const NirangApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await _expandSettingsSection(tester, 'Appearance');
      await tester.scrollUntilVisible(
        find.text('Theme'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Theme')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme'));
      await pumpGlassRoute(tester, find.byType(NirangAlertDialog));

      expect(find.byType(NirangAlertDialog), findsOneWidget);
      for (var i = 1; i <= 20; i++) {
        controller.emitServerUpdate(i + 100);
        await tester.pump();
      }
      expect(find.byType(NirangAlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Dark'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _expandSettingsSection(
  WidgetTester tester,
  String title, {
  String? visibleChild,
}) async {
  final section = find.text(title.toUpperCase());
  await tester.scrollUntilVisible(
    section,
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(section), alignment: .4);
  await tester.pumpAndSettle();
  await tester.tap(section);
  await tester.pumpAndSettle();
  if (visibleChild != null && find.text(visibleChild).evaluate().isEmpty) {
    await tester.tap(section);
    await tester.pumpAndSettle();
  }
}

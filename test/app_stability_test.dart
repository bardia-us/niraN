import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/core/widgets/glass_dialog.dart';
import 'package:niran/core/widgets/country_flag_badge.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/main.dart';

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
  testWidgets('performance mode prompt is recorded after one explicit choice', (
    tester,
  ) async {
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

    expect(find.text('Performance Mode'), findsOneWidget);
    await tester.tap(find.text('Keep full effects'));
    await tester.pumpAndSettle();

    expect(
      controller.state.asData!.value.settings.performanceModePrompted,
      isTrue,
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
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Server information'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server reorder starts immediately only from keyed handles', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(
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

    expect(find.byType(ReorderableDragStartListener), findsNWidgets(3));
    expect(find.byType(ReorderableDelayedDragStartListener), findsNothing);
    for (final id in const ['a', 'b', 'c']) {
      final handle = find.byKey(ValueKey('server-drag-$id'));
      expect(handle, findsOneWidget);
      expect(tester.widget(handle), isA<ReorderableDragStartListener>());
    }
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
        lessThanOrEqualTo(6),
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(_FakeAppController.new)],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile TLS/CDN settings'));
    await tester.pumpAndSettle();

    expect(find.text('Fingerprint'), findsOneWidget);
    expect(find.text('Cipher suites'), findsOneWidget);
    expect(find.text('FinalMask JSON'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(2), '{bad json');
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

  testWidgets('restart service is hidden during a restart transition', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => _FakeAppController(
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

    expect(find.text('Restart Service'), findsNothing);
    expect(find.text('Restarting…'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

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
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
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
      await tester.scrollUntilVisible(
        find.text('VPN MTU'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('VPN MTU'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '100');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Valid range: 1280–9000'), findsWidgets);
      expect(controller.settingsUpdates, 0);

      await tester.enterText(find.byType(TextFormField), '1400');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.state.asData!.value.settings.vpnMtu, 1500);

      await tester.tap(find.text('VPN MTU'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '1400');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.state.asData!.value.settings.vpnMtu, 1400);
      expect(find.textContaining('1400'), findsOneWidget);

      await tester.tap(find.text('VPN MTU'));
      await tester.pumpAndSettle();
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

  testWidgets('routing and domain strategy preserve cancel and sync apply', (
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
      find.text('Routing'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Routing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bypass Iran'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.state.asData!.value.settings.routingMode, 'global');

    await tester.tap(find.widgetWithText(ListTile, 'Routing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bypass Iran'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(controller.state.asData!.value.settings.routingMode, 'bypassIran');

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
    await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();

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

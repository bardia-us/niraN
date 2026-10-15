import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/core/widgets/clay_surface.dart';
import 'package:niran/core/widgets/glass_surface.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/main.dart';
import 'home_refinement_test.dart' show HomeController;

class _Controller extends HomeController {
  _Controller({bool connected = true})
    : super(
        connection: ConnectionInfo(
          state: connected ? 'connected' : 'disconnected',
        ),
      );
  int selections = 0;
  int sets = 0;
  @override
  Future<void> setSystemProxy() async {
    sets++;
  }

  @override
  Future<void> selectServer(String id) async {
    selections++;
  }

  @override
  Future<AppSnapshot> build() async => (await super.build()).copyWith(
    servers: List.generate(
      30,
      (i) => ServerInfo(
        id: 'server-$i',
        name: 'Server $i',
        country: 'DE',
        port: 443,
        protocol: 'VLESS',
        transport: 'WS',
        security: 'TLS',
        selected: i == 0,
        ping: 50,
        status: 'success',
      ),
    ),
  );
}

Future<void> _mount(WidgetTester tester, _Controller controller) async {
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
}

void main() {
  testWidgets('ordinary glass surfaces use the shared reference renderer too', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: const SizedBox(
              width: 220,
              height: 80,
              child: GlassSurface(radius: 22, child: Text('Reference surface')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(glass.AdaptiveGlass),
      findsOneWidget,
      reason:
          'Non-live opt-in surfaces must not stay on the unrelated flat rim pipeline',
    );
    expect(find.text('Reference surface'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('both proxy actions use bounded clay and remain sharp on hover', (
    tester,
  ) async {
    final controller = _Controller();
    await _mount(tester, controller);
    for (final label in ['Set System Proxy', 'Clear System Proxy']) {
      final text = find.text(label);
      final clay = find.ancestor(of: text, matching: find.byType(ClaySurface));
      expect(
        clay,
        findsOneWidget,
        reason: 'Both controls need the same Clay material',
      );
      final before = tester.getRect(text);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(before.center);
      await tester.pumpAndSettle();
      final hovered = tester.getRect(text);
      expect(
        hovered.size,
        before.size,
        reason: 'Hover must not scale or blur glyphs',
      );
      expect(
        hovered.top,
        closeTo(before.top - 3, .1),
        reason: 'Approved Clay lifts on hover',
      );
      await mouse.removePointer();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Set System Proxy'));
    await tester.pumpAndSettle();
    expect(controller.sets, 1);
    await tester.tap(find.text('Clear System Proxy'));
    await tester.pumpAndSettle();
    expect(controller.operationCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolled rows cannot be selected through the Servers header', (
    tester,
  ) async {
    final controller = _Controller(connected: false);
    await _mount(tester, controller);
    await tester.tap(find.text('Servers').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ReorderableListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    final header = tester.getRect(find.byKey(const Key('servers-toolbar')));
    final points = [
      Offset(header.left + 4, header.top + 3),
      Offset(header.left + 4, header.bottom - 3),
      ...[
        .15,
        .45,
        .75,
      ].map((x) => Offset(header.left + header.width * x, header.bottom - 2)),
    ];
    for (final point in points) {
      await tester.tapAt(point);
      await tester.pump();
    }
    expect(controller.selections, 0);
    await tester.tap(find.byKey(const Key('servers-menu-button')));
    await tester.pumpAndSettle();
    expect(find.text('Update now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

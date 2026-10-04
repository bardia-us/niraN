import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/localization/app_strings.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/features/servers/servers_screen.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/core/theme/app_theme.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    servers: [
      for (var i = 0; i < 80; i++)
        ServerInfo(
          id: 's$i',
          name: 'Server $i',
          country: 'DE',
          protocol: 'VLESS',
          transport: 'TCP',
          security: 'TLS',
          port: 443,
          selected: i == 0,
          status: 'idle',
        ),
    ],
  );
  void updatePing() {
    final snapshot = state.asData!.value;
    state = AsyncData(
      snapshot.copyWith(
        servers: [
          for (final server in snapshot.servers)
            server.id == 's0'
                ? server.copyWith(ping: 82, status: 'success')
                : server,
        ],
      ),
    );
  }
}

void main() {
  testWidgets(
    'server wheel scrolling keeps its position during ping updates and exposes a thumb',
    (tester) async {
      final controller = _Controller();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(() => controller)],
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: const [AppStrings.delegate],
            home: const Scaffold(body: ServersScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollbar = find.descendant(
        of: find.byType(ServersScreen),
        matching: find.byType(Scrollbar),
      );
      expect(scrollbar, findsOneWidget);
      expect(tester.widget<Scrollbar>(scrollbar).thumbVisibility, isTrue);
      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(scrollable),
          scrollDelta: const Offset(0, 320),
        ),
      );
      await tester.pumpAndSettle();
      final offset = position.pixels;
      expect(offset, greaterThan(0));
      controller.updatePing();
      await tester.pumpAndSettle();
      expect(position.pixels, offset);
      expect(
        find.byKey(const ValueKey('server-row-s79')),
        findsNothing,
        reason: 'The long list stays lazily built.',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

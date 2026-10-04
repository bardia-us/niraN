import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/features/vpn/home_layout.dart';
import 'package:niran/main.dart';
import 'home_canvas_test.dart' show CanvasController;

void main() {
  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1180, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => CanvasController()),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Restart occupies the connection heading row', (tester) async {
    await mount(tester);
    final emblem = tester.getRect(
      find.byKey(const Key('home-connection-emblem')),
    );
    final restart = tester.getRect(find.byKey(const Key('home-tile-restart')));
    expect((restart.center.dy - emblem.center.dy).abs(), lessThan(15));
    expect(restart.left, greaterThan(emblem.right));
    final logs = tester.getRect(find.byKey(const Key('home-tile-logs')));
    final status = tester.getRect(find.byKey(const Key('home-tile-status')));
    final traffic = tester.getRect(find.byKey(const Key('home-tile-traffic')));
    expect(logs.top, greaterThanOrEqualTo(status.bottom));
    expect(logs.width, closeTo(status.width, 1));
    expect(traffic.left, greaterThan(status.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('TUN toggle uses its natural readable width', (tester) async {
    await mount(tester);
    final box = tester.renderObject<RenderBox>(find.byType(Switch));
    final paintedWidth =
        box.localToGlobal(Offset(box.size.width, 0)).dx -
        box.localToGlobal(Offset.zero).dx;
    expect(paintedWidth, greaterThanOrEqualTo(52));
    expect(tester.takeException(), isNull);
  });

  test('restart can occupy top right but controls cannot cover heading', () {
    final layout = HomeLayout.defaults();
    expect(layout.move('restart', 80, 0), isNotNull);
    expect(layout.move('systemProxy', 0, 0), isNull);
    expect(HomeLayout.tryDecode(layout.encode()), isNotNull);
  });

  testWidgets('Reset restores native window only on Save, never Cancel', (
    tester,
  ) async {
    var resets = 0;
    const channel = MethodChannel('dev.niran.windows/host');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'resetWindowBounds') resets++;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await mount(tester);
    await tester.tap(find.byKey(const Key('customize-home')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const Key('reset-home-layout')));
    await tester.pump();
    expect(resets, 0);
    await tester.tap(find.byKey(const Key('cancel-home-edit')));
    await tester.pumpAndSettle();
    expect(resets, 0);
    await tester.tap(find.byKey(const Key('customize-home')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const Key('reset-home-layout')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-home-layout')));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(tester.takeException(), isNull);
  });
}

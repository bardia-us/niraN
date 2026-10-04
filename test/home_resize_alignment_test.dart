import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/localization/app_strings.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/features/vpn/home_canvas.dart';
import 'package:niran/features/vpn/home_layout.dart';
import 'package:niran/features/vpn/traffic_panel.dart';
import 'package:niran/main.dart';
import 'home_canvas_test.dart' show CanvasController;

void main() {
  Future<void> traffic(WidgetTester tester, Size size) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => CanvasController()),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: const TrafficPanel(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shortening traffic never shrinks its text or icons', (
    tester,
  ) async {
    await traffic(tester, const Size(360, 270));
    final titleHeight = tester.getRect(find.text('niraN traffic')).height;
    final iconSize = tester
        .getRect(find.byIcon(Icons.stacked_line_chart_rounded))
        .size;
    await traffic(tester, const Size(360, 150));
    expect(
      tester.getRect(find.text('niraN traffic')).height,
      closeTo(titleHeight, .01),
    );
    expect(
      tester.getRect(find.byIcon(Icons.stacked_line_chart_rounded)).size,
      iconSize,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrowing traffic reflows without scaling the entire body', (
    tester,
  ) async {
    await traffic(tester, const Size(360, 270));
    final height = tester.getRect(find.text('niraN traffic')).height;
    await traffic(tester, const Size(220, 270));
    expect(
      tester.getRect(find.text('niraN traffic')).height,
      closeTo(height, .01),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('default controls sit above selected-server details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
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
    final controls = tester.getRect(
      find.byKey(const Key('home-control-canvas')),
    );
    final details = tester.getRect(find.text('SELECTED SERVER'));
    expect(controls.bottom, lessThan(details.top));
    final logs = tester.getRect(find.byKey(const Key('home-tile-logs')));
    final status = tester.getRect(find.byKey(const Key('home-tile-status')));
    expect(logs.left, closeTo(status.left, .01));
    expect(logs.right, closeTo(status.right, .01));
    expect(tester.takeException(), isNull);
  });
  Future<void> board(
    WidgetTester tester,
    ValueChanged<HomeLayout> changed,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 600,
            child: HomeCanvas(
              layout: HomeLayout.defaults(),
              editing: true,
              logsVisible: true,
              labels: {for (final id in HomeLayout.itemIds) id: id},
              children: {
                for (final id in HomeLayout.surfaceIds)
                  id: ColoredBox(color: Colors.blue, child: Text(id)),
              },
              onChanged: changed,
              onRemoveLogs: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('minimum status and TUN widths remain usable together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CanvasController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(() => controller)],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    final layout = HomeLayout.defaults()
        .resize('status', 52, 66)!
        .resize('tun', 28, 10)!;
    await controller.updateSettings({'homeLayout': layout.encode()});
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('home-tile-tun'))).width,
      lessThan(83),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('free drag preview follows the pointer without grid jumps', (
    tester,
  ) async {
    await board(tester, (_) {});
    final key = find.byKey(const Key('home-tile-logs'));
    final drag = await tester.startGesture(
      tester.getCenter(key),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(27.4, 0));
    await tester.pump();
    expect(tester.getRect(key).left, closeTo(4 + 27.4, .01));
    await drag.up();
    await tester.pump();
  });

  testWidgets('nearby card edges snap and show a guide during mouse drag', (
    tester,
  ) async {
    HomeLayout? result;
    await board(tester, (layout) => result = layout);
    final before = tester.getRect(find.byKey(const Key('home-tile-logs')));
    final drag = await tester.startGesture(
      before.center,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(5, 0));
    await tester.pump();
    expect(find.byKey(const Key('home-align-vertical')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('home-tile-logs'))).left,
      closeTo(before.left, .01),
    );
    await drag.up();
    await tester.pump();
    expect(result!['logs'].x, 0);
    expect(find.byKey(const Key('home-align-vertical')), findsNothing);
  });
  testWidgets('side resize changes only width and bottom resize only height', (
    tester,
  ) async {
    HomeLayout? result;
    await board(tester, (layout) => result = layout);
    final horizontal = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('resize-width-home-logs'))),
      kind: PointerDeviceKind.mouse,
    );
    await horizontal.moveBy(const Offset(-30, 18));
    await horizontal.up();
    await tester.pump();
    expect(result!['logs'].width, 70);
    expect(result!['logs'].height, 32);
    final vertical = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('resize-height-home-logs'))),
      kind: PointerDeviceKind.mouse,
    );
    await vertical.moveBy(const Offset(30, -20));
    await vertical.up();
    await tester.pump();
    expect(result!['logs'].width, 76);
    expect(result!['logs'].height, 28);
  });

  testWidgets('moving beyond the guide distance remains free', (tester) async {
    HomeLayout? result;
    await board(tester, (layout) => result = layout);
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('home-tile-logs'))),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(find.byKey(const Key('home-align-vertical')), findsNothing);
    await drag.up();
    await tester.pump();
    expect(result!['logs'].x, 6);
  });

  testWidgets('small control resize preview preserves the locked axis', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 112,
              child: HomeCanvas(
                controlsOnly: true,
                layout: HomeLayout.defaults().resize('tun', 28, 10)!,
                editing: true,
                logsVisible: false,
                labels: {for (final id in HomeLayout.itemIds) id: id},
                children: {
                  for (final id in HomeLayout.controlIds)
                    id: const ColoredBox(color: Colors.blue),
                },
                onChanged: (_) {},
                onRemoveLogs: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final tile = find.byKey(const Key('home-tile-tun'));
    final size = tester.getSize(tile);
    expect(size.width, lessThan(80));
    expect(size.height, lessThan(36));
    final heightDrag = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('resize-height-home-tun'))),
      kind: PointerDeviceKind.mouse,
    );
    await heightDrag.moveBy(const Offset(0, 5));
    await tester.pump();
    expect(tester.getSize(tile).width, closeTo(size.width, .01));
    await heightDrag.up();
    await tester.pump();
    final widthDrag = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('resize-width-home-tun'))),
      kind: PointerDeviceKind.mouse,
    );
    await widthDrag.moveBy(const Offset(5, 0));
    await tester.pump();
    expect(tester.getSize(tile).height, closeTo(size.height, .01));
    await widthDrag.up();
    await tester.pump();
  });

  testWidgets('Alt keeps near-edge dragging free without snapping', (
    tester,
  ) async {
    HomeLayout? result;
    await board(tester, (layout) => result = layout);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('home-tile-logs'))),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(5, 0));
    await tester.pump();
    expect(find.byKey(const Key('home-align-vertical')), findsNothing);
    await drag.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(result!['logs'].x, 1);
  });
}

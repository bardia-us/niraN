import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/localization/app_strings.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/features/vpn/home_log_panel.dart';

void main() {
  final logs = List.generate(
    105,
    (i) =>
        LogEntry(DateTime(2026, 10, 2, 12, 0, i), 'info', 'Recorded event $i'),
  );

  Future<void> mount(
    WidgetTester tester,
    List<LogEntry> entries, {
    Size size = const Size(400, 220),
    bool editing = false,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: locale,
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
                child: HomeLogPanel(logs: entries, editing: editing),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('home-log-scroll')),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  testWidgets('keeps the latest hundred logs in chronological order', (
    tester,
  ) async {
    await mount(tester, logs);
    final text = tester
        .widget<Text>(find.byKey(const Key('home-log-text')))
        .textSpan!
        .toPlainText();
    expect(text, startsWith('12:00:05  Recorded event 5'));
    expect(text, endsWith('12:01:44  Recorded event 104'));
    expect(text, isNot(contains('Recorded event 4\n')));
    expect(
      text.indexOf('Recorded event 5\n'),
      lessThan(text.indexOf('Recorded event 6\n')),
    );
    expect(position(tester).pixels, position(tester).maxScrollExtent);
  });

  testWidgets(
    'toggle pauses following, resumes immediately and survives manual scroll',
    (tester) async {
      await mount(tester, logs);
      await tester.tap(find.byKey(const Key('home-log-autoscroll')));
      await tester.pumpAndSettle();
      position(tester).jumpTo(40);
      await mount(tester, [
        ...logs,
        LogEntry(DateTime(2026, 10, 2, 12, 2), 'error', 'New event'),
      ]);
      expect(position(tester).pixels, closeTo(40, 0.01));
      await tester.tap(find.byKey(const Key('home-log-autoscroll')));
      await tester.pumpAndSettle();
      expect(position(tester).pixels, position(tester).maxScrollExtent);
      position(tester).jumpTo(20);
      await mount(tester, [
        ...logs,
        LogEntry(DateTime(2026, 10, 2, 12, 3), 'info', 'Later event'),
      ]);
      expect(position(tester).pixels, position(tester).maxScrollExtent);
    },
  );

  testWidgets(
    'fills resized cards and keeps auto-scroll left of the edit remove control',
    (tester) async {
      await mount(tester, logs, size: const Size(190, 110), editing: true);
      expect(tester.takeException(), isNull);
      final panel = tester.getRect(find.byType(HomeLogPanel));
      final toggle = tester.getRect(
        find.byKey(const Key('home-log-autoscroll')),
      );
      expect(panel.size, const Size(190, 110));
      expect(toggle.right, lessThanOrEqualTo(panel.right - 36));
      await mount(tester, [], size: const Size(140, 70));
      expect(tester.takeException(), isNull);
      expect(find.text('No logs yet'), findsOneWidget);
    },
  );

  testWidgets('keeps auto-scroll at the physical right in Persian edit mode', (
    tester,
  ) async {
    await mount(tester, logs, editing: true, locale: const Locale('fa'));
    final panel = tester.getRect(find.byType(HomeLogPanel));
    final toggle = tester.getRect(find.byKey(const Key('home-log-autoscroll')));
    expect(toggle.right, closeTo(panel.right - 36, 0.01));
  });

  testWidgets('new logs do not move the viewport during a mouse selection', (
    tester,
  ) async {
    final entries = logs.take(20).toList();
    await mount(tester, entries);
    position(tester).jumpTo(0);
    await tester.pump();
    final textRect = tester.getRect(find.byKey(const Key('home-log-text')));
    final mouse = await tester.startGesture(
      textRect.topLeft + const Offset(8, 10),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(80, 0));
    await tester.pump();
    await mount(tester, [
      ...entries,
      LogEntry(DateTime(2026, 10, 2, 12, 2), 'info', 'Arrived while selecting'),
    ]);
    expect(position(tester).pixels, 0);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(position(tester).pixels, 0);
  });

  testWidgets(
    'a selected log remains stable when the hundred-entry window advances',
    (tester) async {
      await mount(tester, logs);
      position(tester).jumpTo(0);
      await tester.pump();
      final textRect = tester.getRect(find.byKey(const Key('home-log-text')));
      final mouse = await tester.startGesture(
        textRect.topLeft + const Offset(8, 10),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(80, 0));
      await tester.pump();
      await mount(tester, [
        ...logs,
        LogEntry(DateTime(2026, 10, 2, 12, 2), 'info', 'Next event'),
      ]);
      final selectedWindow = tester
          .widget<Text>(find.byKey(const Key('home-log-text')))
          .textSpan!
          .toPlainText();
      expect(selectedWindow, startsWith('12:00:05  Recorded event 5'));
      await mouse.up();
      await tester.pumpAndSettle();
      final region = tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion;
      region.clearSelection();
      await tester.pumpAndSettle();
      final currentWindow = tester
          .widget<Text>(find.byKey(const Key('home-log-text')))
          .textSpan!
          .toPlainText();
      expect(currentWindow, startsWith('12:00:06  Recorded event 6'));
      expect(currentWindow, endsWith('12:02:00  Next event'));
      expect(position(tester).pixels, position(tester).maxScrollExtent);
    },
  );

  testWidgets(
    'mouse selection copies only the highlighted text from the right-click menu',
    (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester, [
        LogEntry(DateTime(2026, 10, 2, 12), 'info', 'alpha beta gamma'),
      ]);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(const Key('home-log-text')),
          matching: find.byType(RichText),
        ),
      );
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 16, extentOffset: 20),
      );
      final box = boxes.single.toRect();
      final start = paragraph.localToGlobal(
        Offset(box.left + .2, box.center.dy),
      );
      final end = paragraph.localToGlobal(
        Offset(box.right - .2, box.center.dy),
      );
      final mouse = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveTo(end);
      await mouse.up();
      await tester.pumpAndSettle();
      final secondary = await tester.startGesture(
        (start + end) / 2,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await secondary.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy').last);
      await tester.pumpAndSettle();
      expect(clipboard, 'beta');
    },
  );
}

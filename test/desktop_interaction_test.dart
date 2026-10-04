import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/country_flag_badge.dart';
import 'package:niran/core/widgets/interactive_depth.dart';

void main() {
  testWidgets('OS reduced motion removes elastic transforms', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: InteractiveDepth(
              child: TextButton(onPressed: () {}, child: const Text('Action')),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(AnimatedContainer), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('inline flags stay before and after the original Persian text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: CountryRemarkText(remark: '🇮🇷 آلمان نیم بها 🇩🇪'),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text));
    final spans = (text.textSpan! as TextSpan).children!;
    expect(
      spans
          .map(
            (span) => span is WidgetSpan
                ? (span.child as CountryFlagBadge).countryCode
                : (span as TextSpan).text,
          )
          .toList(),
      ['IR', ' آلمان نیم بها ', 'DE'],
    );
    final flags = find.byType(CountryFlagBadge);
    expect(
      tester.getRect(flags.first).left,
      lessThan(tester.getRect(flags.last).left),
    );
    expect(tester.getSize(flags.first), tester.getSize(flags.last));
    expect(tester.takeException(), isNull);
  });
  testWidgets('all country badges retain equal visual weight', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CountryFlagGroup(
            remark: '🇮🇷 آلمان نیم بها 🇩🇪',
            fallbackCountry: 'IR',
          ),
        ),
      ),
    );
    final flags = find.byType(CountryFlagBadge);
    expect(tester.getSize(flags.at(0)), tester.getSize(flags.at(1)));
  });

  testWidgets('stretching a control cancels its click and returns to rest', (
    tester,
  ) async {
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: InteractiveDepth(
              child: TextButton(
                onPressed: () => clicks++,
                child: const Text('Action'),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Action')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(35, 12));
    await tester.pump(const Duration(milliseconds: 100));
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    expect(container.transform!.getTranslation().x, closeTo(4.2, .001));
    expect(container.transform!.getTranslation().y, closeTo(1.44, .001));
    expect(
      container.transform!.entry(0, 0),
      isNot(closeTo(container.transform!.entry(1, 1), .0001)),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(clicks, 0);
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    expect(clicks, 1);
    expect(tester.takeException(), isNull);
  });
}

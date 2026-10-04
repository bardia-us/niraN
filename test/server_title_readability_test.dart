import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/country_flag_badge.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/main.dart';
import 'home_canvas_test.dart' show CanvasController;

void main() {
  testWidgets(
    'server name is slightly larger without scaling its protocol or overflowing',
    (tester) async {
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
      await tester.tap(find.text('Servers').last);
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('server-row-a'));
      final title = find.descendant(
        of: row,
        matching: find.byType(CountryRemarkText),
      );
      final titleParagraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: title, matching: find.byType(RichText)).first,
      );
      expect((titleParagraph.text as TextSpan).style!.fontSize, 14);
      final subtitleParagraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: row, matching: find.text('VLESS  XHTTP')).first,
      );
      expect((subtitleParagraph.text as TextSpan).style!.fontSize, 12);
      expect(tester.takeException(), isNull);
    },
  );
}

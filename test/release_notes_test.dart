import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/update_checker.dart';
import 'package:niran/core/widgets/glass_dialog.dart';
import 'package:niran/core/widgets/release_notes_markdown.dart';

void main() {
  test('bilingual release notes select exactly one locale section', () {
    final notes = parseBilingualReleaseNotes('''
## English
### Changes
- **Fixed** updater recovery.

## فارسی
### تغییرات
- بازیابی **به‌روزرسانی** اصلاح شد.
''');

    expect(notes.forLanguage('en'), contains('Fixed'));
    expect(notes.forLanguage('en'), isNot(contains('بازیابی')));
    expect(notes.forLanguage('fa'), contains('بازیابی'));
    expect(notes.forLanguage('fa'), isNot(contains('Fixed')));
  });

  testWidgets('What’s New content has one scroll owner', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: NirangAlertDialog(
              title: const Text("What's New"),
              content: ReleaseNotesMarkdown(
                data: List.generate(
                  30,
                  (index) => '- **Change ${index + 1}** description',
                ).join('\n'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(
      tester
          .widgetList<RichText>(find.byType(RichText))
          .any((widget) => widget.text.toPlainText().contains('Change 1')),
      isTrue,
    );
  });
}

import 'package:flutter/material.dart';

/// Small non-scrolling Markdown renderer for trusted GitHub release notes.
/// The parent dialog owns the only ScrollView.
class ReleaseNotesMarkdown extends StatelessWidget {
  const ReleaseNotesMarkdown({required this.data, super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];
    for (final raw in data.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        continue;
      }
      if (line.startsWith('### ')) {
        children.add(
          _text(
            context,
            line.substring(4),
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            top: 8,
          ),
        );
      } else if (line.startsWith('## ')) {
        children.add(
          _text(
            context,
            line.substring(3),
            theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            top: 10,
          ),
        );
      } else if (line.startsWith('# ')) {
        children.add(
          _text(
            context,
            line.substring(2),
            theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            top: 10,
          ),
        );
      } else if (RegExp(r'^[-*+]\s+').hasMatch(line)) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 7, left: 3, right: 9),
                  child: Icon(Icons.circle, size: 5),
                ),
                Expanded(
                  child: _InlineMarkdown(
                    line.replaceFirst(RegExp(r'^[-*+]\s+'), ''),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: _InlineMarkdown(line, style: theme.textTheme.bodyMedium),
          ),
        );
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _text(
    BuildContext context,
    String value,
    TextStyle? style, {
    double top = 0,
  }) => Padding(
    padding: EdgeInsets.only(top: top),
    child: _InlineMarkdown(value, style: style),
  );
}

class _InlineMarkdown extends StatelessWidget {
  const _InlineMarkdown(this.data, {this.style});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*.+?\*\*|`.+?`)');
    var offset = 0;
    for (final match in pattern.allMatches(data)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: data.substring(offset, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: TextStyle(
              fontFamily: 'monospace',
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
        );
      }
      offset = match.end;
    }
    if (offset < data.length) spans.add(TextSpan(text: data.substring(offset)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

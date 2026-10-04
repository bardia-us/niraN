import 'package:flutter/material.dart';

import '../formatters.dart';

class CountryFlagGroup extends StatelessWidget {
  const CountryFlagGroup({
    required this.remark,
    required this.fallbackCountry,
    super.key,
    this.width = 29,
    this.height = 21,
  });

  final String remark, fallbackCountry;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final parsed = countryCodesFromRemark(remark);
    final codes = parsed.isEmpty ? [fallbackCountry] : parsed;
    return Tooltip(
      message: codes.where((code) => code.isNotEmpty).join(' · '),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < codes.length && index < 3; index++) ...[
            if (index > 0) const SizedBox(width: 4),
            CountryFlagBadge(
              countryCode: codes[index],
              width: width,
              height: height,
            ),
          ],
          if (codes.length > 3)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: Text(
                '+${codes.length - 3}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Inline flags keep their original position, including repeated flags.
/// The stored/server name is never rewritten to group flags at the front.
class CountryRemarkText extends StatelessWidget {
  const CountryRemarkText({
    required this.remark,
    this.fallbackCountry = '',
    this.style,
    this.maxLines = 1,
    super.key,
  });
  final String remark, fallbackCountry;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final matches = RegExp(
      r'[\u{1F1E6}-\u{1F1FF}]{2}',
      unicode: true,
    ).allMatches(remark).toList();
    if (matches.isEmpty) {
      return Row(
        children: [
          if (RegExp(r'^[A-Za-z]{2}$').hasMatch(fallbackCountry)) ...[
            CountryFlagBadge(
              countryCode: fallbackCountry,
              width: 25,
              height: 18,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              remark,
              style: style,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: remark.substring(cursor, match.start)));
      }
      final code = String.fromCharCodes(
        match.group(0)!.runes.map((r) => r - 127397),
      );
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: CountryFlagBadge(countryCode: code, width: 25, height: 18),
        ),
      );
      cursor = match.end;
    }
    if (cursor < remark.length) {
      spans.add(TextSpan(text: remark.substring(cursor)));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      textDirection: TextDirection.ltr,
      semanticsLabel: remark,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class CountryFlagBadge extends StatelessWidget {
  const CountryFlagBadge({
    required this.countryCode,
    super.key,
    this.width = 29,
    this.height = 21,
  });

  final String countryCode;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final normalized = countryCode.trim().toUpperCase();
    final valid = RegExp(r'^[A-Z]{2}$').hasMatch(normalized);
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .55),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: valid
          ? Image.asset(
              _twemojiAsset(normalized),
              width: width,
              height: height,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              errorBuilder: (_, _, _) => _fallback(context, height),
            )
          : Icon(
              Icons.public_rounded,
              size: height * .7,
              color: Theme.of(context).colorScheme.primary,
            ),
    );
  }

  static String _twemojiAsset(String countryCode) {
    final codepoints = countryCode.codeUnits
        .map((unit) => (unit + 127397).toRadixString(16))
        .join('-');
    return 'assets/flags/twemoji/$codepoints.png';
  }

  static Widget _fallback(BuildContext context, double height) => Icon(
    Icons.public_rounded,
    size: height * .7,
    color: Theme.of(context).colorScheme.primary,
  );
}

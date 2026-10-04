String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final digits = value >= 100 || index == 0
      ? 0
      : value >= 10
      ? 1
      : 2;
  return '${value.toStringAsFixed(digits)} ${units[index]}';
}

String formatDateTime(int epochMillis, {bool dateOnly = false}) {
  if (epochMillis <= 0) return '—';
  final value = DateTime.fromMillisecondsSinceEpoch(epochMillis).toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  final date = '${value.year}-${two(value.month)}-${two(value.day)}';
  return dateOnly ? date : '$date ${two(value.hour)}:${two(value.minute)}';
}

String countryFlag(String code) {
  final normalized = code.trim().toUpperCase();
  if (normalized.length != 2) return '🌐';
  return String.fromCharCodes(
    normalized.codeUnits.map((unit) => unit + 127397),
  );
}

final RegExp _unicodeCountryFlag = RegExp(
  r'[\u{1F1E6}-\u{1F1FF}]{2}',
  unicode: true,
);

String? countryCodeFromRemark(String remark) {
  final codes = countryCodesFromRemark(remark);
  return codes.isEmpty ? null : codes.first;
}

/// Country badges follow their order in the remark, not a prefix-only rule.
/// Repeated flags are one identity; no country metadata is inferred or changed.
List<String> countryCodesFromRemark(String remark) => [
  ..._unicodeCountryFlag
      .allMatches(remark)
      .map(
        (match) => String.fromCharCodes(
          match.group(0)!.runes.map((value) => value - 127397),
        ),
      )
      .toSet(),
];

String remarkWithoutCountryFlag(String remark) => remark
    .replaceAll(_unicodeCountryFlag, '')
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .replaceAll(RegExp(r'^\s*[-–—|·:]\s*|\s*[-–—|·:]\s*$'), '')
    .trim();

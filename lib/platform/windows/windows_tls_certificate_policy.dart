import 'windows_server_record.dart';

/// Certificate constraints carried by Xray-style TLS share links.
abstract final class WindowsTlsCertificatePolicy {
  static const pinKeys = ['pcs', 'pinSHA256'];

  static Map<String, String> xrayFields(WindowsServerRecord server) {
    final fields = <String, String>{};
    String? pins;
    for (final key in pinKeys) {
      final raw = server.parameters[key];
      if (raw == null) continue;
      final normalized = _normalizePins(raw);
      // The parser retains repeated query entries. Do not let last-value-wins
      // parsing or share export conceal an invalid/conflicting earlier pin.
      final entries = server.queryEntries.where((entry) => entry.key == key);
      if (entries.length > 1 &&
          entries.any((entry) => _normalizePins(entry.value) != normalized)) {
        throw const FormatException(
          'Conflicting repeated TLS certificate pins',
        );
      }
      if (pins != null && pins != normalized) {
        throw const FormatException('Conflicting TLS certificate pin aliases');
      }
      pins = normalized;
    }
    if (pins != null) fields['pinnedPeerCertSha256'] = pins;
    final rawNames = server.parameters['vcn'];
    if (rawNames != null) {
      final names = _normalizeNames(rawNames);
      final entries = server.queryEntries.where((entry) => entry.key == 'vcn');
      if (entries.length > 1 &&
          entries.any((entry) => _normalizeNames(entry.value) != names)) {
        throw const FormatException('Conflicting TLS verification names');
      }
      fields['verifyPeerCertByName'] = names;
    }
    if (fields.isNotEmpty && server.security.toLowerCase() != 'tls') {
      throw const FormatException(
        'Certificate constraints require TLS security',
      );
    }
    return fields;
  }

  static String _normalizeNames(String raw) {
    final names = raw.split(',').map((value) => value.trim()).toList();
    if (names.any((value) => value.isEmpty)) {
      throw const FormatException('TLS verification names must not be empty');
    }
    // Xray also accepts special names such as FromMitM. Validate the list,
    // leaving interpretation of individual verification names to the core.
    return names.join(',');
  }

  static String _normalizePins(String raw) {
    final pins = <String>{};
    for (final part in raw.split(',')) {
      final value = part.trim();
      // Only whole-certificate SHA256 hexadecimal representations are accepted.
      // A pinSHA256 SPKI/base64 convention is not equivalent to Xray cert pins.
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value) &&
          !RegExp(r'^(?:[0-9a-fA-F]{2}:){31}[0-9a-fA-F]{2}$').hasMatch(value)) {
        throw const FormatException(
          'TLS certificate pin must be a SHA256 certificate hash in hex',
        );
      }
      pins.add(value.replaceAll(':', '').toLowerCase());
    }
    return (pins.toList()..sort()).join(',');
  }
}

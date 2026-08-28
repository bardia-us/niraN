import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'windows_server_record.dart';

final class WindowsSubscriptionParser {
  const WindowsSubscriptionParser();

  List<WindowsServerRecord> parse(String body) {
    final normalized = body.trim().replaceFirst('\uFEFF', '');
    final content = normalized.contains('://')
        ? normalized
        : _decodeBase64(normalized) ?? normalized;
    final records = <String, WindowsServerRecord>{};
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      try {
        final record = switch (line.toLowerCase()) {
          final value when value.startsWith('vless://') => _parseStandardUri(
            line,
            'vless',
          ),
          final value when value.startsWith('trojan://') => _parseStandardUri(
            line,
            'trojan',
          ),
          final value when value.startsWith('vmess://') => _parseVmess(line),
          _ => null,
        };
        if (record != null) records.putIfAbsent(record.id, () => record);
      } on Object {
        // One malformed entry must not hide valid subscription servers.
      }
    }
    return records.values.toList(growable: false);
  }

  WindowsServerRecord _parseStandardUri(String raw, String protocol) {
    final uri = Uri.parse(raw);
    if (uri.userInfo.isEmpty || uri.host.isEmpty) {
      throw const FormatException('Missing credential or host');
    }
    final queryEntries = _parseQueryEntries(uri.query);
    final query = <String, String>{
      for (final entry in queryEntries) entry.key: entry.value,
    };
    final security = (query['security'] ?? 'none').trim();
    final name = uri.fragment.isEmpty
        ? 'Server'
        : Uri.decodeComponent(uri.fragment);
    return WindowsServerRecord(
      id: _stableId(raw),
      name: name.trim().isEmpty ? 'Server' : name,
      country: _inferCountry(name),
      protocol: protocol,
      address: uri.host,
      port: uri.hasPort
          ? uri.port
          : (const {'tls', 'reality'}.contains(security.toLowerCase())
                ? 443
                : 80),
      credential: Uri.decodeComponent(uri.userInfo),
      transport: (query['type'] ?? 'tcp').trim().isEmpty
          ? 'tcp'
          : query['type']!,
      security: security.isEmpty ? 'none' : security,
      parameters: query,
      queryEntries: queryEntries,
    );
  }

  String exportShareLink(WindowsServerRecord record) {
    if (!const {'vless', 'trojan'}.contains(record.protocol.toLowerCase())) {
      throw const FormatException('Share export is supported for VLESS/Trojan');
    }
    final supported = <String>{
      'security',
      'type',
      'host',
      'sni',
      'path',
      'alpn',
      'allowInsecure',
      'insecure',
      'allow_insecure',
      'fp',
      'cs',
      'fm',
      'encryption',
      'flow',
      'pbk',
      'sid',
      'spx',
      'serviceName',
      'authority',
      'mode',
      'headerType',
      'extra',
      'ed',
      'pqv',
      'ech',
      'vcn',
      'pcs',
    };
    final emittedSupported = <String>{};
    final pairs = <WindowsQueryParameter>[];
    for (final entry in record.queryEntries) {
      if (supported.contains(entry.key)) {
        if (!emittedSupported.add(entry.key)) continue;
        final value = record.parameters[entry.key];
        if (value != null) pairs.add(WindowsQueryParameter(entry.key, value));
      } else {
        pairs.add(entry);
      }
    }
    for (final entry in record.parameters.entries) {
      if (emittedSupported.contains(entry.key) ||
          pairs.any((pair) => pair.key == entry.key)) {
        continue;
      }
      pairs.add(WindowsQueryParameter(entry.key, entry.value));
    }
    final query = pairs
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    final host = record.address.contains(':')
        ? '[${record.address}]'
        : record.address;
    final fragment = Uri.encodeComponent(record.name);
    return '${record.protocol.toLowerCase()}://'
        '${Uri.encodeComponent(record.credential)}@$host:${record.port}'
        '${query.isEmpty ? '' : '?$query'}${fragment.isEmpty ? '' : '#$fragment'}';
  }

  List<WindowsQueryParameter> _parseQueryEntries(String rawQuery) {
    if (rawQuery.isEmpty) return const [];
    return rawQuery
        .split('&')
        .where((part) => part.isNotEmpty)
        .map((part) {
          final separator = part.indexOf('=');
          final rawKey = separator < 0 ? part : part.substring(0, separator);
          final rawValue = separator < 0 ? '' : part.substring(separator + 1);
          return WindowsQueryParameter(
            Uri.decodeQueryComponent(rawKey),
            Uri.decodeQueryComponent(rawValue),
          );
        })
        .where((entry) => entry.key.isNotEmpty)
        .toList(growable: false);
  }

  WindowsServerRecord _parseVmess(String raw) {
    final decoded = _decodeBase64(raw.substring('vmess://'.length));
    if (decoded == null) throw const FormatException('Invalid VMess payload');
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final name = '${json['ps'] ?? 'Server'}';
    final parameters = <String, String>{};
    const mapping = {
      'alterId': 'aid',
      'encryption': 'scy',
      'host': 'host',
      'path': 'path',
      'sni': 'sni',
      'alpn': 'alpn',
      'fp': 'fp',
      'flow': 'flow',
      'headerType': 'type',
    };
    for (final entry in mapping.entries) {
      final value = '${json[entry.value] ?? ''}'.trim();
      if (value.isNotEmpty) parameters[entry.key] = value;
    }
    return WindowsServerRecord(
      id: _stableId(raw),
      name: name,
      country: _inferCountry(name),
      protocol: 'vmess',
      address: '${json['add'] ?? ''}',
      port: int.tryParse('${json['port'] ?? ''}') ?? 443,
      credential: '${json['id'] ?? ''}',
      transport: '${json['net'] ?? 'tcp'}',
      security: '${json['tls'] ?? 'none'}'.trim().isEmpty
          ? 'none'
          : '${json['tls']}',
      parameters: parameters,
    );
  }

  String? _decodeBase64(String input) {
    final compact = input.replaceAll(RegExp(r'\s'), '');
    final padded =
        compact + List.filled((4 - compact.length % 4) % 4, '=').join();
    for (final normalized in [
      padded,
      padded.replaceAll('-', '+').replaceAll('_', '/'),
    ]) {
      try {
        return utf8.decode(base64Decode(normalized));
      } on Object {
        // Try the other base64 alphabet.
      }
    }
    return null;
  }

  String _stableId(String raw) =>
      sha256.convert(utf8.encode(raw)).bytes.take(12).map((byte) {
        return byte.toRadixString(16).padLeft(2, '0');
      }).join();

  String _inferCountry(String name) {
    final flag = RegExp(
      r'[\u{1F1E6}-\u{1F1FF}]{2}',
      unicode: true,
    ).firstMatch(name);
    if (flag != null) {
      final runes = flag.group(0)!.runes.toList(growable: false);
      if (runes.length == 2) {
        return String.fromCharCodes(runes.map((value) => value - 127397));
      }
    }
    final lower = name.toLowerCase();
    const countries = {
      'germany': 'DE',
      'deutschland': 'DE',
      'netherlands': 'NL',
      'holland': 'NL',
      'finland': 'FI',
      'turkey': 'TR',
      'türkiye': 'TR',
      'france': 'FR',
      'united states': 'US',
      'usa': 'US',
      'canada': 'CA',
      'united kingdom': 'GB',
      'singapore': 'SG',
      'japan': 'JP',
      'iran': 'IR',
      'sweden': 'SE',
    };
    for (final entry in countries.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return '';
  }
}

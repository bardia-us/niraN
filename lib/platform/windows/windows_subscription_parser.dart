import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'windows_server_record.dart';

final class WindowsSubscriptionParseResult {
  const WindowsSubscriptionParseResult({
    required this.records,
    required this.totalEntries,
    required this.failedEntries,
    required this.unsupportedEntries,
  });
  final List<WindowsServerRecord> records;
  final int totalEntries;
  final int failedEntries;
  final int unsupportedEntries;
}

final class WindowsSubscriptionParser {
  const WindowsSubscriptionParser();

  List<WindowsServerRecord> parse(String body) => parseDetailed(body).records;

  WindowsSubscriptionParseResult parseDetailed(String body) {
    final normalized = body.trim().replaceFirst('\uFEFF', '');
    final content = normalized.contains('://')
        ? normalized
        : _decodeBase64(normalized) ?? normalized;
    final records = <String, WindowsServerRecord>{};
    var total = 0, failed = 0, unsupported = 0;
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      total++;
      try {
        final lower = line.toLowerCase();
        final record = switch (lower) {
          final v when v.startsWith('vless://') => _parseStandardUri(
            line,
            'vless',
          ),
          final v when v.startsWith('trojan://') => _parseStandardUri(
            line,
            'trojan',
          ),
          final v when v.startsWith('vmess://') => _parseVmess(line),
          final v when v.startsWith('ss://') => _parseShadowsocks(line),
          final v when v.startsWith('socks://') => _parseUserPasswordUri(
            line,
            'socks',
          ),
          final v when v.startsWith('socks5://') => _parseUserPasswordUri(
            line,
            'socks',
          ),
          final v when v.startsWith('http://') => _parseUserPasswordUri(
            line,
            'http',
          ),
          final v when v.startsWith('https://') => _parseUserPasswordUri(
            line,
            'http',
          ),
          final v when v.startsWith('hy2://') => _parseHysteria2(line),
          final v when v.startsWith('hysteria2://') => _parseHysteria2(line),
          _ => null,
        };
        if (record == null) {
          unsupported++;
        } else {
          records.putIfAbsent(record.id, () => record);
        }
      } on Object {
        failed++;
      }
    }
    return WindowsSubscriptionParseResult(
      records: records.values.toList(growable: false),
      totalEntries: total,
      failedEntries: failed,
      unsupportedEntries: unsupported,
    );
  }

  String exportShareLink(WindowsServerRecord record) {
    if (!const {'vless', 'trojan'}.contains(record.protocol.toLowerCase())) {
      throw const FormatException('Share export is supported for VLESS/Trojan');
    }
    const supported = {
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
    final entries = <WindowsQueryParameter>[];
    for (final entry in record.queryEntries) {
      if (supported.contains(entry.key)) {
        if (!emittedSupported.add(entry.key)) continue;
        final value = record.parameters[entry.key];
        if (value != null) entries.add(WindowsQueryParameter(entry.key, value));
      } else {
        entries.add(entry);
      }
    }
    for (final entry in record.parameters.entries) {
      if (emittedSupported.contains(entry.key) ||
          entries.any((item) => item.key == entry.key)) {
        continue;
      }
      entries.add(WindowsQueryParameter(entry.key, entry.value));
    }
    final pairs = entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    final host = record.address.contains(':')
        ? '[${record.address}]'
        : record.address;
    return '${record.protocol.toLowerCase()}://${Uri.encodeComponent(record.credential)}@$host:${record.port}'
        '${pairs.isEmpty ? '' : '?$pairs'}#${Uri.encodeComponent(record.name)}';
  }

  WindowsServerRecord _parseStandardUri(String raw, String protocol) {
    final uri = Uri.parse(raw);
    if (uri.userInfo.isEmpty || uri.host.isEmpty) {
      throw const FormatException('Missing credential or host');
    }
    final entries = _queryEntries(uri.query);
    final query = {for (final entry in entries) entry.key: entry.value};
    final security = (query['security'] ?? 'none').trim();
    return _record(
      name: _remark(uri),
      protocol: protocol,
      address: uri.host,
      port: uri.hasPort
          ? uri.port
          : const {'tls', 'reality'}.contains(security.toLowerCase())
          ? 443
          : 80,
      credential: _decodeComponent(uri.userInfo),
      transport: (query['type'] ?? 'tcp').trim(),
      security: security.isEmpty ? 'none' : security,
      parameters: query,
      queryEntries: entries,
    );
  }

  WindowsServerRecord _parseUserPasswordUri(String raw, String protocol) {
    final uri = Uri.parse(raw);
    if (uri.host.isEmpty) throw const FormatException('Missing proxy host');
    final colon = uri.userInfo.indexOf(':');
    final username = _decodeComponent(
      colon < 0 ? uri.userInfo : uri.userInfo.substring(0, colon),
    );
    final password = colon < 0
        ? ''
        : _decodeComponent(uri.userInfo.substring(colon + 1));
    final entries = _queryEntries(uri.query);
    final params = <String, String>{
      for (final e in entries) e.key: e.value,
      if (username.isNotEmpty) 'username': username,
      if (password.isNotEmpty) 'password': password,
    };
    return _record(
      name: _remark(uri),
      protocol: protocol,
      address: uri.host,
      port: uri.hasPort ? uri.port : (protocol == 'http' ? 8080 : 1080),
      credential: password,
      transport: 'tcp',
      security: raw.toLowerCase().startsWith('https://') ? 'tls' : 'none',
      parameters: params,
      queryEntries: entries,
    );
  }

  WindowsServerRecord _parseHysteria2(String raw) {
    final uri = Uri.parse(raw);
    if (uri.host.isEmpty || uri.userInfo.isEmpty) {
      throw const FormatException('Missing Hysteria2 credential or host');
    }
    final entries = _queryEntries(uri.query);
    final params = <String, String>{
      for (final e in entries) e.key: e.value,
      'version': '2',
    };
    if ((params['mport'] ?? '').trim().isNotEmpty) {
      throw const FormatException('Hysteria2 multi-port is unsupported');
    }
    final obfs = (params['obfs'] ?? '').trim().toLowerCase();
    if (obfs.isNotEmpty && obfs != 'salamander') {
      throw const FormatException('Unsupported Hysteria2 obfuscation');
    }
    if (obfs == 'salamander' &&
        (params['obfs-password'] ?? params['obfsPassword'] ?? '')
            .trim()
            .isEmpty) {
      throw const FormatException('Hysteria2 obfuscation password is missing');
    }
    return _record(
      name: _remark(uri),
      protocol: 'hysteria2',
      address: uri.host,
      port: uri.hasPort ? uri.port : 443,
      credential: _decodeComponent(uri.userInfo),
      transport: 'hysteria',
      security: 'tls',
      parameters: params,
      queryEntries: entries,
    );
  }

  WindowsServerRecord _parseShadowsocks(String raw) {
    final body = raw.substring(5);
    final hash = body.indexOf('#');
    final fragment = hash < 0 ? '' : body.substring(hash + 1);
    final base = hash < 0 ? body : body.substring(0, hash);
    final q = base.indexOf('?');
    final authority = q < 0 ? base : base.substring(0, q);
    final entries = _queryEntries(q < 0 ? '' : base.substring(q + 1));
    String userInfo, endpoint;
    final at = authority.lastIndexOf('@');
    if (at >= 0) {
      userInfo = authority.substring(0, at);
      endpoint = authority.substring(at + 1);
      if (!userInfo.contains(':')) {
        userInfo = _decodeBase64(userInfo) ?? userInfo;
      }
    } else {
      final decoded = _decodeBase64(authority);
      if (decoded == null || !decoded.contains('@')) {
        throw const FormatException('Invalid Shadowsocks URI');
      }
      final i = decoded.lastIndexOf('@');
      userInfo = decoded.substring(0, i);
      endpoint = decoded.substring(i + 1);
    }
    final colon = userInfo.indexOf(':');
    if (colon <= 0) throw const FormatException('Missing Shadowsocks method');
    final method = _decodeComponent(userInfo.substring(0, colon)).toLowerCase();
    final password = _decodeComponent(userInfo.substring(colon + 1));
    if (!_ssMethods.contains(method) || password.isEmpty) {
      throw const FormatException('Unsupported Shadowsocks credentials');
    }
    final target = Uri.parse('ss://x@$endpoint');
    if (target.host.isEmpty || !target.hasPort) {
      throw const FormatException('Invalid Shadowsocks endpoint');
    }
    final params = <String, String>{
      for (final e in entries) e.key: e.value,
      'method': method,
    };
    return _record(
      name: fragment.isEmpty ? 'Server' : _decodeComponent(fragment),
      protocol: 'shadowsocks',
      address: target.host,
      port: target.port,
      credential: password,
      transport: 'tcp',
      security: 'none',
      parameters: params,
      queryEntries: entries,
    );
  }

  WindowsServerRecord _parseVmess(String raw) {
    final decoded = _decodeBase64(raw.substring(8));
    if (decoded == null) throw const FormatException('Invalid VMess payload');
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    final name = '${json['ps'] ?? 'Server'}';
    final params = <String, String>{};
    const map = {
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
    for (final e in map.entries) {
      final v = '${json[e.value] ?? ''}'.trim();
      if (v.isNotEmpty) params[e.key] = v;
    }
    return _record(
      name: name,
      protocol: 'vmess',
      address: '${json['add'] ?? ''}',
      port: int.tryParse('${json['port'] ?? ''}') ?? 443,
      credential: '${json['id'] ?? ''}',
      transport: '${json['net'] ?? 'tcp'}',
      security: '${json['tls'] ?? 'none'}'.trim().isEmpty
          ? 'none'
          : '${json['tls']}',
      parameters: params,
    );
  }

  WindowsServerRecord _record({
    required String name,
    required String protocol,
    required String address,
    required int port,
    required String credential,
    required String transport,
    required String security,
    required Map<String, String> parameters,
    List<WindowsQueryParameter> queryEntries = const [],
  }) {
    final actualTransport = transport.trim().isEmpty ? 'tcp' : transport;
    final record = WindowsServerRecord(
      id: _semanticId(
        protocol,
        address,
        port,
        credential,
        actualTransport,
        security,
        parameters,
      ),
      name: name.trim().isEmpty ? 'Server' : name.trim(),
      country: _inferCountry(name),
      protocol: protocol,
      address: address,
      port: port,
      credential: credential,
      transport: actualTransport,
      security: security,
      parameters: Map.unmodifiable(parameters),
      queryEntries: queryEntries,
    );
    // Informational entries remain visible, as they do in the source
    // subscription. The connection boundary rejects them using
    // [WindowsServerRecord.rejectionReason], so they can never reach Xray.
    return record;
  }

  String _semanticId(
    String protocol,
    String address,
    int port,
    String credential,
    String transport,
    String security,
    Map<String, String> parameters,
  ) {
    const ignored = {'remarks', 'remark', 'name', 'ps'};
    final keys =
        parameters.keys
            .where((k) => !ignored.contains(k.toLowerCase()))
            .toList()
          ..sort();
    final identity = jsonEncode({
      'protocol': protocol.toLowerCase(),
      'address': address.trim().toLowerCase(),
      'port': port,
      'credential': credential,
      'transport': transport.toLowerCase(),
      'security': security.toLowerCase(),
      'parameters': {for (final k in keys) k: parameters[k]},
    });
    return sha256
        .convert(utf8.encode(identity))
        .bytes
        .take(12)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  List<WindowsQueryParameter> _queryEntries(String query) => query.isEmpty
      ? const []
      : query
            .split('&')
            .where((p) => p.isNotEmpty)
            .map((p) {
              final i = p.indexOf('=');
              return WindowsQueryParameter(
                _decodeQuery(i < 0 ? p : p.substring(0, i)),
                _decodeQuery(i < 0 ? '' : p.substring(i + 1)),
              );
            })
            .where((e) => e.key.isNotEmpty)
            .toList(growable: false);
  String _remark(Uri uri) =>
      uri.fragment.isEmpty ? 'Server' : _decodeComponent(uri.fragment);
  String _decodeComponent(String value) => value.replaceAllMapped(
    RegExp(r'(?:%[0-9a-fA-F]{2})+'),
    (match) => Uri.decodeComponent(match.group(0)!),
  );
  String _decodeQuery(String value) =>
      _decodeComponent(value.replaceAll('+', ' '));
  String? _decodeBase64(String input) {
    final compact = input.replaceAll(RegExp(r'\s'), '');
    final padded =
        compact + List.filled((4 - compact.length % 4) % 4, '=').join();
    for (final v in [
      padded,
      padded.replaceAll('-', '+').replaceAll('_', '/'),
    ]) {
      try {
        return utf8.decode(base64Decode(v));
      } on Object {
        // Try the alternate Base64 alphabet.
      }
    }
    return null;
  }

  String _inferCountry(String name) {
    final flag = RegExp(
      r'[\u{1F1E6}-\u{1F1FF}]{2}',
      unicode: true,
    ).firstMatch(name);
    if (flag != null) {
      final r = flag.group(0)!.runes.toList();
      if (r.length == 2) return String.fromCharCodes(r.map((v) => v - 127397));
    }
    final lower = name.toLowerCase();
    const c = {
      'germany': 'DE',
      'netherlands': 'NL',
      'holland': 'NL',
      'finland': 'FI',
      'turkey': 'TR',
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
    for (final e in c.entries) {
      if (lower.contains(e.key)) return e.value;
    }
    return '';
  }

  static const _ssMethods = {
    'aes-128-gcm',
    'aead_aes_128_gcm',
    'aes-256-gcm',
    'aead_aes_256_gcm',
    'chacha20-poly1305',
    'aead_chacha20_poly1305',
    'chacha20-ietf-poly1305',
    'xchacha20-poly1305',
    'aead_xchacha20_poly1305',
    'xchacha20-ietf-poly1305',
    '2022-blake3-aes-128-gcm',
    '2022-blake3-aes-256-gcm',
    '2022-blake3-chacha20-poly1305',
  };
}

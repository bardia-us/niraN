final class WindowsServerRecord {
  WindowsServerRecord({
    required this.id,
    required this.name,
    required this.country,
    required this.protocol,
    required this.address,
    required this.port,
    required this.credential,
    required this.transport,
    required this.security,
    required this.parameters,
    this.queryEntries = const [],
    this.pingMs,
    this.pingStatus = 'idle',
  });

  factory WindowsServerRecord.fromJson(Map<String, dynamic> json) =>
      WindowsServerRecord(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Server'}',
        country: '${json['country'] ?? ''}',
        protocol: '${json['protocol'] ?? ''}',
        address: '${json['address'] ?? ''}',
        port: (json['port'] as num?)?.toInt() ?? 0,
        credential: '${json['credential'] ?? ''}',
        transport: '${json['transport'] ?? 'tcp'}',
        security: '${json['security'] ?? 'none'}',
        parameters:
            (json['parameters'] as Map?)?.map(
              (key, value) => MapEntry('$key', '$value'),
            ) ??
            const {},
        queryEntries:
            (json['queryEntries'] as List?)
                ?.whereType<Map>()
                .map(
                  (entry) => WindowsQueryParameter(
                    '${entry['key'] ?? ''}',
                    '${entry['value'] ?? ''}',
                  ),
                )
                .where((entry) => entry.key.isNotEmpty)
                .toList(growable: false) ??
            const [],
        pingMs: (json['pingMs'] as num?)?.toInt(),
        pingStatus: '${json['pingStatus'] ?? 'idle'}',
      );

  final String id;
  final String name;
  final String country;
  final String protocol;
  final String address;
  final int port;
  final String credential;
  final String transport;
  final String security;
  final Map<String, String> parameters;
  final List<WindowsQueryParameter> queryEntries;
  int? pingMs;
  String pingStatus;

  String? get rejectionReason {
    final normalizedName = name.toLowerCase();
    const noticeMarkers = [
      'هر دفعه آپدیت',
      'هر بار آپدیت',
      'آپدیت کنید',
      'به‌روزرسانی کنید',
      'بروزرسانی کنید',
      'update subscription',
      'update config',
    ];
    if (noticeMarkers.any(normalizedName.contains)) {
      return 'This entry is subscription information, not a connectable server';
    }
    if (const {
      '',
      '0.0.0.0',
      '::',
      'localhost',
    }.contains(address.trim().toLowerCase())) {
      return 'This server address is not connectable';
    }
    if (port < 1 || port > 65535) return 'This server port is invalid';
    return null;
  }

  Map<String, dynamic> toPrivateJson() => {
    'id': id,
    'name': name,
    'country': country,
    'protocol': protocol,
    'address': address,
    'port': port,
    'credential': credential,
    'transport': transport,
    'security': security,
    'parameters': parameters,
    'queryEntries': [for (final entry in queryEntries) entry.toJson()],
    'pingMs': pingMs,
    'pingStatus': pingStatus,
  };

  Map<String, Object?> safeMetadata(String? selectedId) => {
    'id': id,
    'name': name,
    'country': country,
    'protocol': protocol.toUpperCase(),
    'transport': switch (transport.toLowerCase()) {
      'ws' => 'WebSocket',
      'grpc' => 'gRPC',
      'xhttp' || 'splithttp' => 'XHTTP',
      _ => transport.toUpperCase(),
    },
    'security': switch (security.toLowerCase()) {
      'reality' => 'Reality',
      'tls' => 'TLS',
      'none' || '' => 'None',
      _ => security.toUpperCase(),
    },
    'port': port,
    'sni': parameters['sni'] ?? '',
    'fingerprint': parameters['fp'] ?? '',
    'cipherSuites': parameters['cs'] ?? '',
    'finalMask': parameters['fm'] ?? '',
    'allowInsecure':
        _queryBool(parameters['allowInsecure']) ||
        _queryBool(parameters['insecure']) ||
        _queryBool(parameters['allow_insecure']),
    'credentialLabel':
        const {
          'trojan',
          'shadowsocks',
          'hysteria2',
        }.contains(protocol.toLowerCase())
        ? 'Password'
        : const {'socks', 'http'}.contains(protocol.toLowerCase())
        ? 'Credentials'
        : 'UUID',
    'credentialMasked':
        const {
          'trojan',
          'shadowsocks',
          'hysteria2',
          'socks',
          'http',
        }.contains(protocol.toLowerCase())
        ? '••••••••••••'
        : '********-****-****-****-************',
    'realityPublicKeyMasked': (parameters['pbk'] ?? '').isEmpty
        ? ''
        : '••••••••••••••••',
    'shortIdMasked': (parameters['sid'] ?? '').isEmpty ? '' : '••••••',
    'ping': pingMs,
    'selected': id == selectedId,
    'status': pingStatus,
  };

  WindowsServerRecord copyWithParameters(Map<String, String> updated) =>
      WindowsServerRecord(
        id: id,
        name: name,
        country: country,
        protocol: protocol,
        address: address,
        port: port,
        credential: credential,
        transport: updated['type'] ?? transport,
        security: updated['security'] ?? security,
        parameters: Map.unmodifiable(updated),
        queryEntries: queryEntries,
        pingMs: pingMs,
        pingStatus: pingStatus,
      );
}

final class WindowsQueryParameter {
  const WindowsQueryParameter(this.key, this.value);

  final String key;
  final String value;

  Map<String, String> toJson() => {'key': key, 'value': value};
}

bool _queryBool(String? value) =>
    const {'1', 'true', 'yes', 'on'}.contains(value?.trim().toLowerCase());

final class WindowsSubscriptionUsage {
  const WindowsSubscriptionUsage({
    this.upload,
    this.download,
    this.total,
    this.expire,
  });

  factory WindowsSubscriptionUsage.fromHeader(String? header) {
    if (header == null || header.trim().isEmpty) {
      return const WindowsSubscriptionUsage();
    }
    final values = <String, int>{};
    for (final field in header.split(';')) {
      final parts = field.trim().split('=');
      if (parts.length != 2) continue;
      final value = int.tryParse(parts[1].trim());
      if (value != null) values[parts[0].trim().toLowerCase()] = value;
    }
    return WindowsSubscriptionUsage(
      upload: values['upload'],
      download: values['download'],
      total: values['total'],
      expire: values['expire'],
    );
  }

  factory WindowsSubscriptionUsage.fromJson(Map<String, dynamic> json) =>
      WindowsSubscriptionUsage(
        upload: (json['upload'] as num?)?.toInt(),
        download: (json['download'] as num?)?.toInt(),
        total: (json['total'] as num?)?.toInt(),
        expire: (json['expire'] as num?)?.toInt(),
      );

  final int? upload;
  final int? download;
  final int? total;
  final int? expire;

  int? get used => upload == null && download == null
      ? null
      : (upload ?? 0) + (download ?? 0);
  int? get remaining => total != null && total! > 0 && used != null
      ? (total! - used!).clamp(0, total!).toInt()
      : null;
  bool get unlimited => total == 0;
  bool get expired =>
      expire != null &&
      expire! > 0 &&
      expire! * 1000 < DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> toMap() => {
    'upload': upload,
    'download': download,
    'used': used,
    'total': total,
    'remaining': remaining,
    'expire': expire,
    'unlimited': unlimited,
    'expired': expired,
  };

  Map<String, Object?> toJson() => {
    'upload': upload,
    'download': download,
    'total': total,
    'expire': expire,
  };
}

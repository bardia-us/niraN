import 'windows_server_record.dart';

enum WindowsProxyCore { xray, singBox }

abstract final class WindowsCoreSelection {
  static const protocols = [
    'vless',
    'vmess',
    'trojan',
    'shadowsocks',
    'socks',
    'http',
    'hysteria2',
  ];
  static WindowsProxyCore forProtocol(
    Map<String, Object?> settings,
    String protocol,
  ) {
    final mapping = settings['coreByProtocol'];
    return mapping is Map && mapping[protocol.toLowerCase()] == 'sing-box'
        ? WindowsProxyCore.singBox
        : WindowsProxyCore.xray;
  }

  static Map<String, String> validateMapping(Object? value) {
    if (value is! Map) throw const FormatException('Invalid core selection');
    final result = <String, String>{};
    for (final entry in value.entries) {
      if (!protocols.contains(entry.key) ||
          !const ['xray', 'sing-box'].contains(entry.value)) {
        throw const FormatException('Invalid core selection');
      }
      result['${entry.key}'] = '${entry.value}';
    }
    return Map.unmodifiable(result);
  }

  /// Fail explicitly instead of silently discarding Xray-only profile features.
  static String? singBoxUnsupportedReason(
    WindowsServerRecord server,
    Map<String, Object?> settings,
  ) {
    final p = server.parameters;
    if (!protocols.contains(server.protocol.toLowerCase())) return 'protocol';
    final protocol = server.protocol.toLowerCase();
    final transport = server.transport.toLowerCase();
    if (!const ['vless', 'vmess', 'trojan'].contains(protocol) &&
        transport != 'tcp' &&
        !(protocol == 'hysteria2' && transport == 'hysteria')) {
      return 'protocol transport';
    }
    if ((p['flow'] ?? '').isNotEmpty && protocol != 'vless') {
      return 'flow';
    }
    if (transport == 'ws' &&
        ((p['ed'] ?? '').isNotEmpty ||
            (p['eh'] ?? '').isNotEmpty ||
            RegExp(r'[?&]ed=').hasMatch(p['path'] ?? ''))) {
      return 'WebSocket early data';
    }
    if (!const [
      'tcp',
      'ws',
      'grpc',
      'httpupgrade',
      'http',
      'h2',
      'hysteria',
    ].contains(server.transport.toLowerCase())) {
      return 'transport';
    }
    if (!const [
      '',
      'none',
      'tls',
      'reality',
    ].contains(server.security.toLowerCase())) {
      return 'security';
    }
    for (final key in ['fm', 'extra', 'pqv', 'mldsa65Verify', 'plugin']) {
      if ((p[key] ?? '').trim().isNotEmpty) return key;
    }
    if (settings['fragmentEnabled'] == true) return 'fragmentation';
    if (settings['muxEnabled'] == true &&
        const ['vless', 'vmess'].contains(server.protocol)) {
      return 'Xray Mux/XUDP';
    }
    if ((p['headerType'] ?? 'none') != 'none' &&
        (p['headerType'] ?? '').isNotEmpty) {
      return 'TCP header';
    }
    if (p['mode'] == 'multi' && server.transport == 'grpc') {
      return 'gRPC multiMode';
    }
    if (!const ['', 'xtls-rprx-vision'].contains(p['flow'] ?? '')) {
      return 'flow';
    }
    if ((p['encryption'] ?? 'none') != 'none' && server.protocol == 'vless') {
      return 'VLESS encryption';
    }
    final fingerprint = p['fp']?.isNotEmpty == true
        ? p['fp']!
        : '${settings['defaultFingerprint'] ?? 'chrome'}';
    if (const ['tls', 'reality'].contains(server.security) &&
        !const [
          'chrome',
          'firefox',
          'safari',
          'ios',
          'android',
          'edge',
          '360',
          'qq',
          'random',
          'randomized',
        ].contains(fingerprint)) {
      return 'TLS fingerprint';
    }
    return null;
  }
}

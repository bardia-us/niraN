import 'dart:convert';
import 'windows_core_selection.dart';
import 'windows_server_record.dart';
import 'windows_sing_box_tun_config_builder.dart';
import 'windows_routing_policy.dart';

final class WindowsSingBoxProxyConfigBuilder {
  const WindowsSingBoxProxyConfigBuilder();
  String build({
    required WindowsServerRecord server,
    required Map<String, Object?> settings,
    List<String> iranCidrs = const [],
  }) {
    const routing = WindowsSingBoxTunConfigBuilder();
    if (WindowsRoutingPolicy.bypassIran(settings) && iranCidrs.isEmpty) {
      throw const FormatException('Iran CIDR assets are unavailable');
    }
    final socks = _port(settings['localSocksPort'], 10808);
    final http = _port(settings['localHttpPort'], 10809);
    if (socks == http) {
      throw const FormatException('Proxy ports must be different');
    }
    final listen = settings['allowLanConnections'] == true
        ? '${settings['localListenAddress'] ?? '0.0.0.0'}'
        : '127.0.0.1';
    final mode = '${settings['routingMode'] ?? 'global'}';
    return jsonEncode({
      'log': {
        'level': settings['xrayLogLevel'] == 'warning'
            ? 'warn'
            : settings['xrayLogLevel'] == 'none'
            ? 'error'
            : '${settings['xrayLogLevel'] ?? 'warn'}',
      },
      'dns': routing.buildDns(settings, mode, server.address),
      'inbounds': [
        {
          'type': 'socks',
          'tag': 'socks-in',
          'listen': listen,
          'listen_port': socks,
        },
        {
          'type': 'http',
          'tag': 'http-in',
          'listen': listen,
          'listen_port': http,
        },
      ],
      'outbounds': [
        outbound(server, settings),
        {'type': 'direct', 'tag': 'direct', 'domain_resolver': 'local-dns'},
      ],
      'route': {
        'default_domain_resolver': {'server': 'bootstrap-dns'},
        'rules': routing.buildRouteRules(
          settings,
          mode,
          iranCidrs,
          const [],
          const [],
          tun: false,
        ),
        'final': 'proxy',
      },
    });
  }

  String buildSpeedtest({
    required List<WindowsServerRecord> servers,
    required Map<String, Object?> settings,
    required List<int> socksPorts,
    required List<int> httpPorts,
  }) {
    if (servers.isEmpty ||
        servers.length != socksPorts.length ||
        servers.length != httpPorts.length) {
      throw const FormatException('Speed-test batch is invalid');
    }
    return jsonEncode({
      'log': {'level': 'warn'},
      'dns': {
        'servers': [
          {'type': 'local', 'tag': 'local-dns'},
        ],
        'final': 'local-dns',
      },
      'inbounds': [
        for (var i = 0; i < servers.length; i++) ...[
          {
            'type': 'socks',
            'tag': 'test-in-$i',
            'listen': '127.0.0.1',
            'listen_port': _port(socksPorts[i], 0),
          },
          {
            'type': 'http',
            'tag': 'test-in-$i-http',
            'listen': '127.0.0.1',
            'listen_port': _port(httpPorts[i], 0),
          },
        ],
      ],
      'outbounds': [
        for (var i = 0; i < servers.length; i++)
          {...outbound(servers[i], settings), 'tag': 'test-out-$i'},
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'default_domain_resolver': {'server': 'local-dns'},
        'rules': [
          {
            'ip_cidr': WindowsRoutingPolicy.localCidrs,
            'action': 'route',
            'outbound': 'direct',
          },
          {
            'domain': ['localhost'],
            'domain_suffix': ['.localhost', '.local'],
            'action': 'route',
            'outbound': 'direct',
          },
          for (var i = 0; i < servers.length; i++)
            {
              'inbound': ['test-in-$i', 'test-in-$i-http'],
              'action': 'route',
              'outbound': 'test-out-$i',
            },
        ],
        'final': 'direct',
      },
    });
  }

  Map<String, Object?> outbound(
    WindowsServerRecord server,
    Map<String, Object?> settings,
  ) {
    final reason = WindowsCoreSelection.singBoxUnsupportedReason(
      server,
      settings,
    );
    if (reason != null) {
      throw FormatException(
        'sing-box does not support $reason for this profile',
      );
    }
    if (server.rejectionReason != null) {
      throw const FormatException('Invalid proxy server');
    }
    final p = server.parameters;
    final protocol = server.protocol.toLowerCase();
    final result = <String, Object?>{
      'type': protocol,
      'tag': 'proxy',
      'server': server.address,
      'server_port': server.port,
    };
    switch (protocol) {
      case 'vless':
        result.addAll({
          'uuid': server.credential,
          if ((p['flow'] ?? '').isNotEmpty) 'flow': p['flow'],
        });
      case 'vmess':
        result.addAll({
          'uuid': server.credential,
          'security': p['encryption'] ?? 'auto',
          'alter_id': int.tryParse(p['alterId'] ?? '') ?? 0,
        });
      case 'trojan' || 'hysteria2':
        result['password'] = server.credential;
      case 'shadowsocks':
        result.addAll({'method': p['method'], 'password': server.credential});
      case 'socks' || 'http':
        if (protocol == 'socks') result['version'] = '5';
        if ((p['username'] ?? '').isNotEmpty) {
          result.addAll({
            'username': p['username'],
            'password': p['password'] ?? server.credential,
          });
        }
    }
    if (const ['tls', 'reality'].contains(server.security) ||
        protocol == 'hysteria2') {
      final fp = p['fp']?.isNotEmpty == true
          ? p['fp']
          : settings['defaultFingerprint'] ?? 'chrome';
      result['tls'] = {
        'enabled': true,
        'server_name': (p['sni'] ?? '').isNotEmpty
            ? p['sni']
            : (p['host'] ?? '').isNotEmpty
            ? p['host']!.split(',').first
            : server.address,
        'insecure': ['allowInsecure', 'insecure', 'allow_insecure'].any(
          (k) => const ['1', 'true', 'yes', 'on'].contains(p[k]?.toLowerCase()),
        ),
        if ((p['alpn'] ?? '').isNotEmpty) 'alpn': p['alpn']!.split(','),
        if ((p['cs'] ?? '').isNotEmpty)
          'cipher_suites': p['cs']!.split(RegExp('[:,]')),
        if (protocol != 'hysteria2')
          'utls': {'enabled': true, 'fingerprint': fp},
        if (server.security == 'reality')
          'reality': {
            'enabled': true,
            'public_key': p['pbk'] ?? '',
            'short_id': p['sid'] ?? '',
          },
      };
    }
    if (protocol == 'hysteria2' && (p['obfs'] ?? '').isNotEmpty) {
      if (p['obfs'] != 'salamander') {
        throw const FormatException('Unsupported Hysteria2 obfuscation');
      }
      result['obfs'] = {
        'type': 'salamander',
        'password': p['obfs-password'] ?? p['obfsPassword'] ?? '',
      };
    }
    if (const ['vless', 'vmess', 'trojan'].contains(protocol) &&
        server.transport != 'tcp') {
      final type = server.transport == 'h2' ? 'http' : server.transport;
      result['transport'] = switch (type) {
        'ws' => {
          'type': 'ws',
          'path': p['path'] ?? '/',
          'headers': {
            if ((p['host'] ?? '').isNotEmpty) 'Host': p['host'],
            if ('${settings['defaultUserAgent'] ?? ''}'.isNotEmpty)
              'User-Agent': settings['defaultUserAgent'],
          },
        },
        'grpc' => {
          'type': 'grpc',
          'service_name': p['serviceName'] ?? p['path'] ?? '',
        },
        'httpupgrade' => {
          'type': 'httpupgrade',
          'host': p['host'] ?? '',
          'path': p['path'] ?? '/',
        },
        'http' => {
          'type': 'http',
          if ((p['host'] ?? '').isNotEmpty) 'host': p['host']!.split(','),
          'path': p['path'] ?? '/',
        },
        _ => throw const FormatException('Unsupported sing-box transport'),
      };
    }
    return result;
  }

  int _port(Object? value, int fallback) {
    final port = value is num ? value.toInt() : fallback;
    if (port < 1024 || port > 65535) {
      throw const FormatException('Invalid proxy port');
    }
    return port;
  }
}

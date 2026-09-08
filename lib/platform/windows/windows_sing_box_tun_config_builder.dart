import 'dart:convert';
import 'dart:io';

final class WindowsSingBoxTunConfigBuilder {
  const WindowsSingBoxTunConfigBuilder();

  String build({
    required Map<String, Object?> settings,
    required int xraySocksPort,
    required List<String> iranCidrs,
    required List<String> protectedProcessPaths,
    String? proxyServerHost,
  }) {
    if (xraySocksPort < 1024 || xraySocksPort > 65535) {
      throw const FormatException('Xray SOCKS port is invalid');
    }
    final ipv6 = _bool(settings, 'enableIpv6', true);
    final addresses = <String>[
      '${settings['vpnInterfaceAddress'] ?? '10.10.14.1/30'}',
      if (ipv6)
        '${settings['vpnInterfaceIpv6Address'] ?? 'fdfe:dcba:9876::1/126'}',
    ];
    final routingMode = '${settings['routingMode'] ?? 'bypassIran'}';
    if (!const {'global', 'bypassIran', 'custom'}.contains(routingMode)) {
      throw const FormatException('Unsupported TUN routing mode');
    }
    if (routingMode == 'bypassIran' && iranCidrs.isEmpty) {
      throw const FormatException('Iran CIDR assets are unavailable');
    }

    final config = <String, Object?>{
      'log': _log(settings),
      'dns': _dns(settings, routingMode, proxyServerHost),
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'niraN',
          'address': addresses,
          'mtu': _integer(settings, 'vpnMtu', 1500),
          'auto_route': true,
          'strict_route': true,
          'stack': 'system',
          'dns_mode': 'hijack',
        },
      ],
      'outbounds': [
        {
          'type': 'socks',
          'tag': 'proxy',
          'server': '127.0.0.1',
          'server_port': xraySocksPort,
          'version': '5',
        },
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'auto_detect_interface': true,
        'find_process': true,
        'default_domain_resolver': {
          'server': 'bootstrap-dns',
          'strategy': _dnsStrategy(settings),
        },
        'rules': _routeRules(
          settings,
          routingMode,
          iranCidrs,
          addresses,
          protectedProcessPaths,
        ),
        'final': 'proxy',
      },
    };
    validate(jsonEncode(config));
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  Map<String, Object?> _log(Map<String, Object?> settings) {
    final level = '${settings['xrayLogLevel'] ?? 'warning'}'.toLowerCase();
    if (level == 'none') return {'disabled': true};
    return {'level': level == 'warning' ? 'warn' : level, 'timestamp': false};
  }

  void validate(String value) {
    final root = jsonDecode(value);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('Generated sing-box JSON is invalid');
    }
    final inbounds = root['inbounds'];
    final tun = inbounds is List
        ? inbounds.whereType<Map>().where((item) => item['type'] == 'tun')
        : const Iterable<Map>.empty();
    if (tun.length != 1 ||
        tun.single['auto_route'] != true ||
        tun.single['dns_mode'] != 'hijack') {
      throw const FormatException('sing-box TUN inbound is incomplete');
    }
    final outbounds = root['outbounds'];
    final tags = outbounds is List
        ? {for (final item in outbounds.whereType<Map>()) item['tag']}
        : const <Object?>{};
    if (!tags.contains('proxy') || !tags.contains('direct')) {
      throw const FormatException('sing-box TUN outbounds are incomplete');
    }
    final route = root['route'];
    if (route is! Map || route['final'] != 'proxy') {
      throw const FormatException('sing-box TUN route is incomplete');
    }
  }

  Map<String, Object?> _dns(
    Map<String, Object?> settings,
    String routingMode,
    String? proxyServerHost,
  ) {
    final bootstrap = _dnsServer(
      _firstResolver('${settings['vpnDns'] ?? '1.1.1.1'}'),
      tag: 'bootstrap-dns',
      detour: null,
      domainResolver: null,
    );
    final remote = _dnsServer(
      _firstResolver(
        '${settings['remoteDns'] ?? 'https://dns.google/dns-query'}',
      ),
      tag: 'remote-dns',
      detour: 'proxy',
      domainResolver: 'bootstrap-dns',
    );
    final servers = <Map<String, Object?>>[bootstrap, remote];
    if (routingMode != 'global') {
      servers.add(
        _dnsServer(
          _firstResolver('${settings['domesticDns'] ?? '223.5.5.5'}'),
          tag: 'direct-dns',
          detour: null,
          domainResolver: 'bootstrap-dns',
        ),
      );
    }
    final customDnsDomains = routingMode == 'custom'
        ? _customDomainFields('${settings['customDomains'] ?? ''}')
        : const <String, Object?>{};
    return {
      'servers': servers,
      'rules': [
        if (proxyServerHost != null &&
            proxyServerHost.trim().isNotEmpty &&
            InternetAddress.tryParse(proxyServerHost.trim()) == null)
          {
            'domain': [proxyServerHost.trim()],
            'action': 'route',
            'server': 'bootstrap-dns',
          },
        if (routingMode == 'bypassIran')
          {
            'domain': ['localhost'],
            'domain_suffix': ['.ir', '.local'],
            'action': 'route',
            'server': 'direct-dns',
          },
        if (customDnsDomains.isNotEmpty)
          {...customDnsDomains, 'action': 'route', 'server': 'direct-dns'},
      ],
      'final': 'remote-dns',
      'strategy': _dnsStrategy(settings),
      'timeout': '5s',
    };
  }

  Map<String, Object?> _dnsServer(
    String value, {
    required String tag,
    required String? detour,
    required String? domainResolver,
  }) {
    final raw = value.trim();
    if (raw.isEmpty) throw const FormatException('DNS resolver is empty');
    final parsed = raw.contains('://') ? Uri.tryParse(raw) : null;
    final scheme = parsed?.scheme.toLowerCase() ?? 'udp';
    final host = parsed?.host.isNotEmpty == true ? parsed!.host : raw;
    final connectHost = _knownEncryptedDnsAddress(scheme, host) ?? host;
    final isIp = InternetAddress.tryParse(connectHost) != null;
    final server = <String, Object?>{
      'type': switch (scheme) {
        'https' => 'https',
        'tls' => 'tls',
        'tcp' => 'tcp',
        'udp' => 'udp',
        _ => throw const FormatException('Unsupported DNS resolver scheme'),
      },
      'tag': tag,
      'server': connectHost,
      if (parsed?.hasPort == true) 'server_port': parsed!.port,
      if (scheme == 'https')
        'path': parsed?.path.isNotEmpty == true ? parsed!.path : '/dns-query',
      if (scheme == 'https' || scheme == 'tls')
        'tls': {'enabled': true, 'server_name': host},
      if (!isIp && domainResolver != null) 'domain_resolver': domainResolver,
    };
    if (detour != null) server['detour'] = detour;
    return server;
  }

  String? _knownEncryptedDnsAddress(String scheme, String host) {
    if (scheme != 'https' && scheme != 'tls') return null;
    return switch (host.toLowerCase()) {
      'dns.google' => '8.8.8.8',
      'cloudflare-dns.com' => '1.1.1.1',
      _ => null,
    };
  }

  List<Map<String, Object?>> _routeRules(
    Map<String, Object?> settings,
    String routingMode,
    List<String> iranCidrs,
    List<String> tunAddresses,
    List<String> protectedProcessPaths,
  ) {
    final rules = <Map<String, Object?>>[
      if (protectedProcessPaths.isNotEmpty)
        {
          'process_path': protectedProcessPaths,
          'action': 'route',
          'outbound': 'direct',
        },
      {
        'ip_cidr': tunAddresses.map(_singleAddressPrefix).toList(),
        'action': 'reject',
        'method': 'drop',
      },
      {
        'inbound': ['tun-in'],
        'action': 'sniff',
        'timeout': '300ms',
      },
      {
        'inbound': ['tun-in'],
        'port': [53],
        'action': 'hijack-dns',
      },
    ];
    if (routingMode == 'bypassIran') {
      rules.addAll([
        {
          'domain': ['localhost'],
          'domain_suffix': ['.ir', '.local'],
          'action': 'route',
          'outbound': 'direct',
        },
        {'ip_is_private': true, 'action': 'route', 'outbound': 'direct'},
        {'ip_cidr': iranCidrs, 'action': 'route', 'outbound': 'direct'},
      ]);
    } else if (routingMode == 'custom') {
      rules.add({
        'ip_is_private': true,
        'action': 'route',
        'outbound': 'direct',
      });
      final domains = _customDomainFields('${settings['customDomains'] ?? ''}');
      if (domains.isNotEmpty) {
        rules.add({...domains, 'action': 'route', 'outbound': 'direct'});
      }
      final ips = _items('${settings['customIps'] ?? ''}');
      if (ips.isNotEmpty) {
        rules.add({'ip_cidr': ips, 'action': 'route', 'outbound': 'direct'});
      }
    }
    return rules;
  }

  Map<String, Object?> _customDomainFields(String raw) {
    final full = <String>[];
    final suffix = <String>[];
    final regex = <String>[];
    for (final item in _items(raw)) {
      if (item.startsWith('full:')) {
        full.add(item.substring(5));
      } else if (item.startsWith('regexp:')) {
        regex.add(item.substring(7));
      } else if (item.startsWith('domain:')) {
        suffix.add(_asSuffix(item.substring(7)));
      } else {
        suffix.add(_asSuffix(item));
      }
    }
    return {
      if (full.isNotEmpty) 'domain': full,
      if (suffix.isNotEmpty) 'domain_suffix': suffix,
      if (regex.isNotEmpty) 'domain_regex': regex,
    };
  }

  String _asSuffix(String value) => value.startsWith('.') ? value : '.$value';

  String _singleAddressPrefix(String value) {
    final address = value.split('/').first;
    final parsed = InternetAddress.tryParse(address);
    if (parsed == null) return value;
    return '$address/${parsed.type == InternetAddressType.IPv6 ? 128 : 32}';
  }

  String _firstResolver(String value) {
    final values = _items(value);
    return values.isEmpty ? '' : values.first;
  }

  String _dnsStrategy(Map<String, Object?> settings) {
    if (!_bool(settings, 'enableIpv6', true)) return 'ipv4_only';
    final configured = '${settings['dnsQueryStrategy'] ?? 'Auto'}';
    return switch (configured) {
      'UseIPv4' => 'ipv4_only',
      'UseIPv6' => 'ipv6_only',
      'UseIP' =>
        _bool(settings, 'preferIpv6', false) ? 'prefer_ipv6' : 'prefer_ipv4',
      // With Happy Eyeballs intentionally disabled, returning AAAA records in
      // Auto mode lets Windows select an unreachable IPv6 path and wait for a
      // full TCP timeout. Auto therefore uses the user's existing preference:
      // the default is reliable IPv4, while an explicit IPv6 preference keeps
      // dual-stack resolution.
      _ => _bool(settings, 'preferIpv6', false) ? 'prefer_ipv6' : 'ipv4_only',
    };
  }

  List<String> _items(String value) => value
      .split(RegExp(r'[,\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  bool _bool(Map<String, Object?> values, String key, bool fallback) =>
      values[key] is bool ? values[key]! as bool : fallback;

  int _integer(Map<String, Object?> values, String key, int fallback) =>
      values[key] is num ? (values[key]! as num).toInt() : fallback;
}

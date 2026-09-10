import 'dart:convert';

import 'windows_server_record.dart';

final class WindowsXrayConfigBuilder {
  const WindowsXrayConfigBuilder();

  static const defaultSocksPort = 10808;
  static const defaultHttpPort = 10809;

  String buildSpeedtest({
    required List<WindowsServerRecord> servers,
    required Map<String, Object?> settings,
    required List<int> socksPorts,
    required List<int> httpPorts,
  }) {
    if (servers.isEmpty ||
        servers.length != socksPorts.length ||
        servers.length != httpPorts.length) {
      throw const FormatException('Speed-test server/port batch is invalid');
    }
    for (final server in servers) {
      _validateServer(server);
    }
    final inbounds = <Map<String, Object?>>[];
    final outbounds = <Map<String, Object?>>[];
    final rules = <Map<String, Object?>>[];
    for (var index = 0; index < servers.length; index++) {
      final inboundTag = 'test-in-$index';
      final outboundTag = 'test-out-$index';
      inbounds.add({
        'tag': inboundTag,
        'listen': '127.0.0.1',
        'port': socksPorts[index],
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': false},
      });
      inbounds.add({
        'tag': '$inboundTag-http',
        'listen': '127.0.0.1',
        'port': httpPorts[index],
        'protocol': 'http',
        'settings': {'allowTransparent': false},
      });
      outbounds.add({
        ..._proxyOutbound(servers[index], {
          ...settings,
          'fragmentEnabled': false,
        }),
        'tag': outboundTag,
      });
      rules.add({
        'type': 'field',
        'inboundTag': [inboundTag, '$inboundTag-http'],
        'outboundTag': outboundTag,
      });
    }
    return const JsonEncoder.withIndent('  ').convert({
      'log': {'loglevel': '${settings['xrayLogLevel'] ?? 'warning'}'},
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {'domainStrategy': 'AsIs', 'rules': rules},
    });
  }

  String build({
    required WindowsServerRecord server,
    required Map<String, Object?> settings,
    List<String> iranCidrs = const [],
  }) {
    _validateServer(server);
    final config = <String, Object?>{
      'log': {'loglevel': '${settings['xrayLogLevel'] ?? 'warning'}'},
      'dns': _dns(settings),
      'inbounds': _inbounds(settings),
      'outbounds': [
        _proxyOutbound(server, settings),
        {
          'tag': 'dns-out',
          'protocol': 'dns',
          'settings': {'nonIPQuery': 'skip'},
        },
        {
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': <String, Object?>{
            'targetStrategy': '${settings['directTargetStrategy'] ?? 'AsIs'}',
          },
        },
        {
          'tag': 'blocked',
          'protocol': 'blackhole',
          'settings': <String, Object?>{},
        },
        if (_bool(settings, 'fragmentEnabled', false) &&
            (server.parameters['fm'] ?? '').trim().isEmpty)
          {
            'tag': 'fragment',
            'protocol': 'freedom',
            'settings': {
              'fragment': {
                'packets': '${settings['fragmentPackets'] ?? 'tlshello'}',
                'length': '${settings['fragmentLength'] ?? '100-200'}',
                'interval': '${settings['fragmentInterval'] ?? '10-20'}',
                'maxSplit': '${settings['fragmentMaxSplit'] ?? '0'}',
              },
            },
          },
      ],
      'routing': _routing(
        settings,
        iranCidrs,
        blockQuic: _shouldBlockQuic(settings),
      ),
    };
    if (_bool(settings, 'enableLocalDns', true) &&
        _bool(settings, 'enableFakeDns', false)) {
      config['fakedns'] = [
        {'ipPool': '198.18.0.0/15', 'poolSize': 65535},
      ];
    }
    validate(jsonEncode(config), tunEnabled: _tunEnabled(settings));
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  void validate(String value, {bool tunEnabled = false}) {
    final root = jsonDecode(value);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('Generated Xray JSON is invalid');
    }
    final inbounds = root['inbounds'];
    if (inbounds is! List) {
      throw const FormatException('Generated Xray inbounds are invalid');
    }
    final maps = inbounds.whereType<Map>().toList(growable: false);
    if (tunEnabled) {
      final tun = maps.where((item) => item['protocol'] == 'tun').firstOrNull;
      final settings = tun?['settings'];
      if (tun == null ||
          settings is! Map ||
          settings['autoOutboundsInterface'] != 'auto' ||
          settings['autoSystemRoutingTable'] is! List) {
        throw const FormatException('Windows TUN inbound is incomplete');
      }
    }
    final socks = maps.where((item) => item['protocol'] == 'socks').firstOrNull;
    final http = maps.where((item) => item['protocol'] == 'http').firstOrNull;
    final socksPort = socks?['port'];
    final httpPort = http?['port'];
    if (socksPort is! int ||
        socksPort < 1024 ||
        socksPort > 65535 ||
        httpPort is! int ||
        httpPort < 1024 ||
        httpPort > 65535 ||
        socksPort == httpPort) {
      throw const FormatException('Local proxy inbounds are incomplete');
    }
    final outbounds = root['outbounds'];
    final tags = outbounds is List
        ? {for (final item in outbounds.whereType<Map>()) item['tag']}
        : const <Object?>{};
    if (!tags.contains('proxy') || !tags.contains('direct')) {
      throw const FormatException('Generated Xray outbounds are incomplete');
    }
    final rules = (root['routing'] as Map?)?['rules'];
    if (rules is! List) {
      throw const FormatException('Generated Xray routing rules are missing');
    }
    for (final rule in rules.whereType<Map>()) {
      if (!tags.contains(rule['outboundTag'])) {
        throw const FormatException('Routing references an unknown outbound');
      }
    }
  }

  List<Map<String, Object?>> _inbounds(Map<String, Object?> settings) {
    final fakeDns =
        _bool(settings, 'enableLocalDns', true) &&
        _bool(settings, 'enableFakeDns', false);
    final sniffing = _sniffing(settings, fakeDns: fakeDns);
    final listen = _listenAddress(settings);
    final result = <Map<String, Object?>>[
      {
        'tag': 'local-socks',
        'listen': listen,
        'port': _integer(settings, 'localSocksPort', defaultSocksPort),
        'protocol': 'socks',
        'settings': {
          'auth': 'noauth',
          'udp': _bool(settings, 'enableUdp', true),
        },
        'sniffing': sniffing,
      },
      {
        'tag': 'local-http',
        'listen': listen,
        'port': _integer(settings, 'localHttpPort', defaultHttpPort),
        'protocol': 'http',
        'settings': {'allowTransparent': false},
        'sniffing': sniffing,
      },
    ];
    if (_tunEnabled(settings)) {
      final ipv6 = _bool(settings, 'enableIpv6', true);
      result.add({
        'tag': 'tun-in',
        'protocol': 'tun',
        'settings': {
          'name': 'niraN',
          'desc': 'niraN',
          'mtu': _integer(settings, 'vpnMtu', 1500),
          'gateway': [
            '${settings['vpnInterfaceAddress'] ?? '10.10.14.1/30'}',
            if (ipv6)
              '${settings['vpnInterfaceIpv6Address'] ?? 'fdfe:dcba:9876::1/126'}',
          ],
          'dns': _tunDns(settings),
          'autoSystemRoutingTable': ['0.0.0.0/0', if (ipv6) '::/0'],
          'autoOutboundsInterface': 'auto',
        },
        'sniffing': sniffing,
      });
    }
    return result;
  }

  Map<String, Object?> _sniffing(
    Map<String, Object?> settings, {
    required bool fakeDns,
  }) {
    final sniffingEnabled = _bool(settings, 'sniffingEnabled', true);
    final sniffTypes = _rules(
      '${settings['sniffingType'] ?? 'http,tls,quic'}',
    ).where(const {'http', 'tls', 'quic'}.contains).toList(growable: false);
    final overrides = <String>[
      if (sniffingEnabled) ...sniffTypes,
      if (fakeDns) 'fakedns',
    ];
    return <String, Object?>{
      'enabled': sniffingEnabled || fakeDns,
      'destOverride': overrides,
      'routeOnly': sniffingEnabled && _bool(settings, 'routeOnly', false),
    };
  }

  List<String> _tunDns(Map<String, Object?> settings) {
    final values = _rules('${settings['vpnDns'] ?? '1.1.1.1'}');
    return values.isEmpty ? const ['1.1.1.1'] : values;
  }

  Map<String, Object?> _proxyOutbound(
    WindowsServerRecord server,
    Map<String, Object?> settings,
  ) => {
    'tag': 'proxy',
    'targetStrategy': '${settings['proxyTargetStrategy'] ?? 'AsIs'}',
    'protocol': server.protocol.toLowerCase() == 'hysteria2'
        ? 'hysteria'
        : server.protocol.toLowerCase(),
    'settings': switch (server.protocol.toLowerCase()) {
      'trojan' => {
        'servers': [
          {
            'address': server.address,
            'port': server.port,
            'password': server.credential,
          },
        ],
      },
      'vmess' => {
        'vnext': [
          {
            'address': server.address,
            'port': server.port,
            'users': [
              {
                'id': server.credential,
                'alterId':
                    int.tryParse(server.parameters['alterId'] ?? '') ?? 0,
                'security': server.parameters['encryption'] ?? 'auto',
              },
            ],
          },
        ],
      },
      'shadowsocks' => {
        'servers': [
          {
            'address': server.address,
            'port': server.port,
            'method': server.parameters['method'],
            'password': server.credential,
          },
        ],
      },
      'socks' || 'http' => {
        'servers': [
          {
            'address': server.address,
            'port': server.port,
            if ((server.parameters['username'] ?? '').isNotEmpty)
              'users': [
                {
                  'user': server.parameters['username'],
                  'pass': server.parameters['password'] ?? server.credential,
                },
              ],
          },
        ],
      },
      'hysteria2' => {
        'version': 2,
        'address': server.address,
        'port': server.port,
      },
      _ => {
        'vnext': [
          {
            'address': server.address,
            'port': server.port,
            'users': [
              {
                'id': server.credential,
                'encryption': server.parameters['encryption'] ?? 'none',
                if ((server.parameters['flow'] ?? '').isNotEmpty)
                  'flow': server.parameters['flow'],
              },
            ],
          },
        ],
      },
    },
    'streamSettings': _streamSettings(server, settings),
    'mux': _mux(server, settings),
  };

  Map<String, Object?> _mux(
    WindowsServerRecord server,
    Map<String, Object?> settings,
  ) {
    final enabled =
        _bool(settings, 'muxEnabled', false) && _supportsMux(server);
    return {
      'enabled': enabled,
      if (enabled) 'concurrency': _integer(settings, 'muxConcurrency', 8),
    };
  }

  bool _supportsMux(WindowsServerRecord server) {
    final protocol = server.protocol.toLowerCase();
    if (protocol != 'vless' && protocol != 'vmess') return false;
    final transport = server.transport.toLowerCase();
    if (transport == 'xhttp' || transport == 'splithttp') return false;
    return (server.parameters['flow'] ?? '').trim().isEmpty;
  }

  Map<String, Object?> _streamSettings(
    WindowsServerRecord server,
    Map<String, Object?> settings,
  ) {
    final network = server.transport.toLowerCase() == 'splithttp'
        ? 'xhttp'
        : server.transport.toLowerCase();
    final result = <String, Object?>{
      'network': network,
      'security': server.security.trim().isEmpty
          ? 'none'
          : server.security.toLowerCase(),
    };
    switch (network) {
      case 'ws':
        final userAgent = '${settings['defaultUserAgent'] ?? ''}'.trim();
        result['wsSettings'] = {
          'path': server.parameters['path'] ?? '/',
          if ((server.parameters['host'] ?? '').isNotEmpty)
            'host': server.parameters['host'],
          if (userAgent.isNotEmpty) 'headers': {'User-Agent': userAgent},
        };
      case 'grpc':
        result['grpcSettings'] = {
          'serviceName':
              server.parameters['serviceName'] ??
              server.parameters['path'] ??
              '',
          'multiMode': server.parameters['mode']?.toLowerCase() == 'multi',
        };
      case 'xhttp':
        final extra = _jsonObjectParameter(
          server.parameters['extra'],
          label: 'XHTTP extra',
        );
        result['xhttpSettings'] = {
          'path': server.parameters['path'] ?? '/',
          if ((server.parameters['host'] ?? '').isNotEmpty)
            'host': server.parameters['host'],
          if ((server.parameters['mode'] ?? '').isNotEmpty)
            'mode': server.parameters['mode'],
          'extra': ?extra,
        };
      case 'tcp':
        final headerType = server.parameters['headerType'];
        if (headerType != null &&
            headerType.isNotEmpty &&
            headerType != 'none') {
          result['tcpSettings'] = {
            'header': {'type': headerType},
          };
        }
      case 'hysteria':
        result['hysteriaSettings'] = {'version': 2, 'auth': server.credential};
    }
    switch (server.security.toLowerCase()) {
      case 'tls':
        final fingerprint = _fingerprint(server, settings, tls: true);
        result['tlsSettings'] = {
          'serverName': _tlsServerName(server),
          if (_csv(server.parameters['alpn']).isNotEmpty)
            'alpn': _csv(server.parameters['alpn']),
          'fingerprint': fingerprint,
          if ((server.parameters['cs'] ?? '').trim().isNotEmpty)
            'cipherSuites': server.parameters['cs']!.trim(),
        };
      case 'reality':
        final fingerprint = _fingerprint(server, settings, tls: false);
        final mldsa65Verify =
            (server.parameters['mldsa65Verify'] ??
                    server.parameters['pqv'] ??
                    '')
                .trim();
        result['realitySettings'] = {
          'serverName': server.parameters['sni'] ?? server.address,
          'fingerprint': fingerprint,
          'publicKey': server.parameters['pbk'] ?? '',
          'shortId': server.parameters['sid'] ?? '',
          'spiderX': server.parameters['spx'] ?? '/',
          if (mldsa65Verify.isNotEmpty) 'mldsa65Verify': mldsa65Verify,
        };
    }
    final finalMask = (server.parameters['fm'] ?? '').trim();
    if (finalMask.isNotEmpty) {
      final decoded = jsonDecode(finalMask);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('FinalMask must be a JSON object');
      }
      result['finalmask'] = decoded;
    } else if (server.protocol.toLowerCase() == 'hysteria2' &&
        (server.parameters['obfs'] ?? '').toLowerCase() == 'salamander') {
      result['finalmask'] = {
        'udp': [
          {
            'type': 'salamander',
            'settings': {
              'password':
                  server.parameters['obfs-password'] ??
                  server.parameters['obfsPassword'],
            },
          },
        ],
      };
    }
    final sockopt = <String, Object?>{};
    var dialStrategy = '${settings['proxyDialStrategy'] ?? 'Auto'}';
    if (dialStrategy == 'Auto') {
      dialStrategy =
          _bool(settings, 'enableIpv6', true) &&
              _bool(settings, 'preferIpv6', false)
          ? 'UseIPv6v4'
          : 'AsIs';
    }
    if (_bool(settings, 'happyEyeballs', false) && dialStrategy == 'AsIs') {
      dialStrategy = 'UseIP';
    }
    if (dialStrategy != 'AsIs') {
      sockopt['domainStrategy'] = dialStrategy;
    }
    if (_bool(settings, 'happyEyeballs', false)) {
      sockopt['happyEyeballs'] = {
        'tryDelayMs': 250,
        'prioritizeIPv6': _bool(settings, 'preferIpv6', false),
        'interleave': 1,
        'maxConcurrentTry': 4,
      };
    }
    if (_bool(settings, 'fragmentEnabled', false) && finalMask.isEmpty) {
      sockopt['dialerProxy'] = 'fragment';
    }
    if (sockopt.isNotEmpty) result['sockopt'] = sockopt;
    return result;
  }

  String _tlsServerName(WindowsServerRecord server) {
    final explicit = (server.parameters['sni'] ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    final host = (server.parameters['host'] ?? '').split(',').first.trim();
    return host.isEmpty ? server.address : host;
  }

  String _fingerprint(
    WindowsServerRecord server,
    Map<String, Object?> settings, {
    required bool tls,
  }) {
    final value = (server.parameters['fp'] ?? '').trim().toLowerCase();
    final fingerprint = value.isEmpty
        ? '${settings['defaultFingerprint'] ?? 'chrome'}'.trim().toLowerCase()
        : value;
    if (fingerprint == 'unsafe' && !tls) {
      throw const FormatException(
        'Fingerprint unsafe is supported only by Xray TLS transports',
      );
    }
    const supported = {
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
      'unsafe',
    };
    if (!supported.contains(fingerprint)) {
      throw const FormatException('Unsupported TLS fingerprint');
    }
    return fingerprint;
  }

  Map<String, Object?>? _jsonObjectParameter(
    String? raw, {
    required String label,
  }) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) throw const FormatException();
      return decoded.map((key, item) => MapEntry('$key', item));
    } on Object {
      throw FormatException('$label must be a JSON object');
    }
  }

  Map<String, Object?> _dns(Map<String, Object?> settings) {
    final servers = <Object?>[
      ..._rules('${settings['remoteDns'] ?? ''}').toSet(),
    ];
    if (servers.isEmpty) servers.add('localhost');
    final domestic = _rules('${settings['domesticDns'] ?? ''}');
    final directDns = '${settings['directDnsAddress'] ?? ''}'.trim();
    if (_bool(settings, 'directDnsEnabled', false) && directDns.isNotEmpty) {
      servers.insert(0, {
        'address': directDns,
        'domains': ['domain:ir', 'domain:local'],
        'skipFallback': true,
      });
    }
    if (settings['routingMode'] == 'bypassIran' && domestic.isNotEmpty) {
      servers.insert(0, {
        'address': domestic.first,
        'domains': ['domain:ir', 'domain:local'],
      });
    }
    if (_bool(settings, 'enableLocalDns', true) &&
        _bool(settings, 'enableFakeDns', false)) {
      servers.insert(0, 'fakedns');
    }
    final configuredStrategy = '${settings['dnsQueryStrategy'] ?? 'Auto'}';
    final queryStrategy = configuredStrategy == 'Auto'
        ? (_bool(settings, 'enableIpv6', true) ? 'UseIP' : 'UseIPv4')
        : configuredStrategy;
    return {
      'servers': servers,
      'queryStrategy': queryStrategy,
      'enableParallelQuery': _bool(settings, 'dnsParallelQuery', false),
      'serveStale': _bool(settings, 'dnsServeStale', false),
    };
  }

  Map<String, Object?> _routing(
    Map<String, Object?> settings,
    List<String> iranCidrs, {
    bool blockQuic = false,
  }) {
    final mode = '${settings['routingMode'] ?? 'global'}';
    if (!const {'global', 'bypassIran', 'custom'}.contains(mode)) {
      throw const FormatException('Unsupported routing mode');
    }
    final domainStrategy = '${settings['domainStrategy'] ?? 'AsIs'}';
    if (!const {
      'AsIs',
      'IPIfNonMatch',
      'IPOnDemand',
    }.contains(domainStrategy)) {
      throw const FormatException('Unsupported domain strategy');
    }
    final rules = <Map<String, Object?>>[];
    if (_bool(settings, 'enableLocalDns', true)) {
      rules.add({
        'type': 'field',
        'inboundTag': [
          'local-socks',
          'local-http',
          if (_tunEnabled(settings)) 'tun-in',
        ],
        'network': 'tcp,udp',
        'port': '53',
        'outboundTag': 'dns-out',
      });
    }
    const privateIps = [
      '10.0.0.0/8',
      '100.64.0.0/10',
      '127.0.0.0/8',
      '169.254.0.0/16',
      '172.16.0.0/12',
      '192.168.0.0/16',
      '::1/128',
      'fc00::/7',
      'fe80::/10',
    ];
    const privateDomains = [
      'full:localhost',
      'domain:localhost',
      'domain:local',
    ];
    if (mode == 'bypassIran') {
      if (iranCidrs.isEmpty) {
        throw const FormatException('Iran CIDR assets are unavailable');
      }
      rules.addAll([
        {
          'type': 'field',
          'domain': ['domain:ir', ...privateDomains],
          'outboundTag': 'direct',
        },
        {
          'type': 'field',
          'ip': [...privateIps, ...iranCidrs],
          'outboundTag': 'direct',
        },
      ]);
    } else if (mode == 'custom') {
      rules.addAll([
        {'type': 'field', 'domain': privateDomains, 'outboundTag': 'direct'},
        {'type': 'field', 'ip': privateIps, 'outboundTag': 'direct'},
      ]);
      final ips = _rules('${settings['customIps'] ?? ''}');
      final domains = _domainRules('${settings['customDomains'] ?? ''}');
      if (domains.isNotEmpty) {
        rules.add({
          'type': 'field',
          'domain': domains,
          'outboundTag': 'direct',
        });
      }
      if (ips.isNotEmpty) {
        rules.add({'type': 'field', 'ip': ips, 'outboundTag': 'direct'});
      }
    }
    if (blockQuic) {
      rules.insert(0, {
        'type': 'field',
        'network': 'udp',
        'port': '443',
        'outboundTag': 'blocked',
      });
    }
    return {'domainStrategy': domainStrategy, 'rules': rules};
  }

  void _validateServer(WindowsServerRecord server) {
    if (!const {
      'vless',
      'vmess',
      'trojan',
      'shadowsocks',
      'socks',
      'http',
      'hysteria2',
    }.contains(server.protocol.toLowerCase())) {
      throw const FormatException('Unsupported proxy protocol');
    }
    if (server.address.isEmpty ||
        server.address.length > 253 ||
        server.port < 1 ||
        server.port > 65535 ||
        (server.credential.isEmpty &&
            !const {'socks', 'http'}.contains(server.protocol.toLowerCase()))) {
      throw const FormatException('Server endpoint is invalid');
    }
    if (server.protocol.toLowerCase() == 'shadowsocks' &&
        (server.parameters['method'] ?? '').isEmpty) {
      throw const FormatException('Shadowsocks method is missing');
    }
    if (server.protocol.toLowerCase() == 'hysteria2' &&
        server.parameters['version'] != '2') {
      throw const FormatException('Hysteria2 version is invalid');
    }
    if (!const {
      '',
      'none',
      'tls',
      'reality',
    }.contains(server.security.toLowerCase())) {
      throw const FormatException('Unsupported transport security');
    }
    if (server.security.toLowerCase() == 'reality' &&
        (server.parameters['pbk'] ?? '').isEmpty) {
      throw const FormatException('Reality public key is missing');
    }
  }

  bool _bool(Map<String, Object?> values, String key, bool fallback) =>
      values[key] is bool ? values[key]! as bool : fallback;
  int _integer(Map<String, Object?> values, String key, int fallback) =>
      values[key] is num ? (values[key]! as num).toInt() : fallback;
  bool _tunEnabled(Map<String, Object?> values) => values['tunEnabled'] == true;
  bool _shouldBlockQuic(Map<String, Object?> values) =>
      _bool(values, 'blockQuic', false);
  String _listenAddress(Map<String, Object?> values) {
    if (!_bool(values, 'allowLanConnections', false)) return '127.0.0.1';
    final address = '${values['localListenAddress'] ?? '0.0.0.0'}'.trim();
    return address.isEmpty ? '0.0.0.0' : address;
  }

  List<String> _csv(String? value) =>
      value
          ?.split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false) ??
      const [];
  List<String> _rules(String value) => value
      .split(RegExp(r'[,\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  List<String> _domainRules(String value) => value
      .split(RegExp(r'[,\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

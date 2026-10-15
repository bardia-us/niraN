/// Local routing takes precedence over geographic/custom rules.
abstract final class WindowsRoutingPolicy {
  static bool bypassLocal(Map<String, Object?> settings) =>
      settings['localBypassMode'] != 'proxy';
  static const localCidrs = <String>[
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
  static const localDomains = [
    'full:localhost',
    'domain:localhost',
    'domain:local',
  ];
  static bool bypassIran(Map<String, Object?> settings) =>
      settings['bypassIran'] as bool? ??
      settings['routingMode'] == 'bypassIran';
  static bool customEnabled(Map<String, Object?> settings) =>
      settings['customRulesEnabled'] as bool? ??
      settings['routingMode'] == 'custom';
}

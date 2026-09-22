import 'dart:convert';
import 'dart:io';

const nirangRepositoryUrl = 'https://github.com/bardia-us/niraN';
const nirangLatestReleaseApi =
    'https://api.github.com/repos/bardia-us/niraN/releases/latest';
const nirangReleaseByTagApi =
    'https://api.github.com/repos/bardia-us/niraN/releases/tags/';

class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch, [this.build = 0]);

  factory SemanticVersion.parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:-[^+]*)?(?:\+(\d+))?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) throw const FormatException('Invalid release version');
    return SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.tryParse(match.group(4) ?? '') ?? 0,
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    final majorResult = major.compareTo(other.major);
    if (majorResult != 0) return majorResult;
    final minorResult = minor.compareTo(other.minor);
    if (minorResult != 0) return minorResult;
    final patchResult = patch.compareTo(other.patch);
    if (patchResult != 0) return patchResult;
    return build.compareTo(other.build);
  }

  final int major;
  final int minor;
  final int patch;
  final int build;

  String get releaseVersion => '$major.$minor.$patch';

  @override
  String toString() => build == 0 ? releaseVersion : '$releaseVersion+$build';
}

class ReleaseCheckResult {
  const ReleaseCheckResult({
    required this.latestVersion,
    required this.releaseUrl,
    required this.updateAvailable,
    this.portableAsset,
    this.setupAsset,
  });

  final SemanticVersion latestVersion;
  final Uri releaseUrl;
  final bool updateAvailable;
  final ReleaseAsset? portableAsset;
  final ReleaseAsset? setupAsset;

  ReleaseAsset? assetFor(WindowsUpdatePackage package) => switch (package) {
    WindowsUpdatePackage.portableZip => portableAsset,
    WindowsUpdatePackage.setupExe => setupAsset,
  };
}

enum WindowsUpdatePackage { portableZip, setupExe }

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });
  final String name;
  final Uri url;
  final int size;
  final String? sha256;

  WindowsUpdatePackage? get package => packageFromName(name);

  SemanticVersion? get version {
    final match = RegExp(
      r'^niraN-(?:v)?(\d+\.\d+\.\d+)-windows-x64(?:-setup)?\.(?:zip|exe)$',
      caseSensitive: false,
    ).firstMatch(name);
    if (match == null) return null;
    return SemanticVersion.parse(match.group(1)!);
  }

  static WindowsUpdatePackage? packageFromName(String name) {
    if (RegExp(
      r'^niraN-(?:v)?\d+\.\d+\.\d+-windows-x64\.zip$',
      caseSensitive: false,
    ).hasMatch(name)) {
      return WindowsUpdatePackage.portableZip;
    }
    if (RegExp(
      r'^niraN-(?:v)?\d+\.\d+\.\d+-windows-x64(?:-setup)?\.exe$',
      caseSensitive: false,
    ).hasMatch(name)) {
      return WindowsUpdatePackage.setupExe;
    }
    return null;
  }
}

class GitHubUpdateChecker {
  const GitHubUpdateChecker();

  Future<ReleaseCheckResult> check(String currentVersion) async {
    final payload = await _fetch(
      Uri.parse(nirangLatestReleaseApi),
      currentVersion,
    );
    return parseGitHubRelease(payload, currentVersion);
  }

  Future<BilingualReleaseNotes> releaseNotes(String version) async {
    final releaseVersion = SemanticVersion.parse(version).releaseVersion;
    final tag = 'v$releaseVersion';
    final payload = await _fetch(
      Uri.parse('$nirangReleaseByTagApi${Uri.encodeComponent(tag)}'),
      version,
    );
    return parseBilingualReleaseNotes('${payload['body'] ?? ''}');
  }

  Future<Map<String, dynamic>> _fetch(Uri uri, String currentVersion) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(
          HttpHeaders.userAgentHeader,
          'niraN-update-checker/$currentVersion',
        );
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('GitHub release check failed');
      }
      final payload = jsonDecode(
        await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 10)),
      );
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid GitHub response');
      }
      return payload;
    } finally {
      client.close(force: true);
    }
  }
}

class BilingualReleaseNotes {
  const BilingualReleaseNotes({required this.english, required this.persian});

  final String english;
  final String persian;

  String forLanguage(String language) => language == 'fa'
      ? (persian.isNotEmpty ? persian : english)
      : (english.isNotEmpty ? english : persian);
}

BilingualReleaseNotes parseBilingualReleaseNotes(String body) {
  final sections = <String, StringBuffer>{
    'en': StringBuffer(),
    'fa': StringBuffer(),
  };
  String? current;
  for (final line in body.replaceAll('\r\n', '\n').split('\n')) {
    final heading = line.trim().toLowerCase().replaceAll(
      RegExp(r'[#:*_\s]'),
      '',
    );
    if ({'english', 'en', 'انگلیسی'}.contains(heading)) {
      current = 'en';
      continue;
    }
    if ({'فارسی', 'persian', 'fa', 'farsi'}.contains(heading)) {
      current = 'fa';
      continue;
    }
    if (current != null) sections[current]!.writeln(line);
  }
  final english = sections['en']!.toString().trim();
  final persian = sections['fa']!.toString().trim();
  if (english.isEmpty && persian.isEmpty) {
    return BilingualReleaseNotes(english: body.trim(), persian: '');
  }
  return BilingualReleaseNotes(english: english, persian: persian);
}

ReleaseCheckResult parseGitHubRelease(
  Map<String, dynamic> payload,
  String currentVersion,
) {
  final latest = SemanticVersion.parse('${payload['tag_name'] ?? ''}');
  final releaseUrl = Uri.tryParse('${payload['html_url'] ?? ''}');
  if (releaseUrl == null ||
      releaseUrl.scheme != 'https' ||
      releaseUrl.host != 'github.com' ||
      !releaseUrl.path.startsWith('/bardia-us/niraN/releases/')) {
    throw const FormatException('Invalid release URL');
  }
  ReleaseAsset? portableAsset;
  ReleaseAsset? setupAsset;
  final assets = payload['assets'];
  if (assets is List) {
    for (final value in assets.whereType<Map>()) {
      final name = '${value['name'] ?? ''}';
      final package = ReleaseAsset.packageFromName(name);
      if (package == null) continue;
      final url = Uri.tryParse('${value['browser_download_url'] ?? ''}');
      if (url == null ||
          url.scheme != 'https' ||
          !const {
            'github.com',
            'objects.githubusercontent.com',
          }.contains(url.host)) {
        continue;
      }
      final rawDigest = '${value['digest'] ?? ''}';
      final digest = RegExp(
        r'^sha256:([0-9a-fA-F]{64})$',
      ).firstMatch(rawDigest)?.group(1)?.toLowerCase();
      final asset = ReleaseAsset(
        name: name,
        url: url,
        size: (value['size'] as num?)?.toInt() ?? 0,
        sha256: digest,
      );
      if (asset.version?.compareTo(latest) != 0) continue;
      switch (package) {
        case WindowsUpdatePackage.portableZip:
          portableAsset ??= asset;
        case WindowsUpdatePackage.setupExe:
          setupAsset ??= asset;
      }
    }
  }
  return ReleaseCheckResult(
    latestVersion: latest,
    releaseUrl: releaseUrl,
    updateAvailable:
        latest.compareTo(SemanticVersion.parse(currentVersion)) > 0,
    portableAsset: portableAsset,
    setupAsset: setupAsset,
  );
}

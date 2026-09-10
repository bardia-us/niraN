import 'dart:convert';
import 'dart:io';

const nirangRepositoryUrl = 'https://github.com/bardia-us/niraN';
const nirangLatestReleaseApi =
    'https://api.github.com/repos/bardia-us/niraN/releases/latest';

class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);

  factory SemanticVersion.parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) throw const FormatException('Invalid release version');
    return SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    final majorResult = major.compareTo(other.major);
    if (majorResult != 0) return majorResult;
    final minorResult = minor.compareTo(other.minor);
    if (minorResult != 0) return minorResult;
    return patch.compareTo(other.patch);
  }

  final int major;
  final int minor;
  final int patch;

  @override
  String toString() => '$major.$minor.$patch';
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
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(nirangLatestReleaseApi));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'niraN-update-checker/0.3.5');
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
    } finally {
      client.close(force: true);
    }
  }
}

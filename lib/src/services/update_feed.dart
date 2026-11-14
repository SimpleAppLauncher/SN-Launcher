import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One release in the GitHub releases feed.
///
/// The feed is the whole releases list, not `/releases/latest`: everything
/// this project published from 0.2.0 onwards is a pre-release, and
/// `/releases/latest` answers with v0.1.3.
@immutable
class UpdateRelease {
  const UpdateRelease({
    required this.tag,
    required this.version,
    required this.prerelease,
    required this.notes,
    required this.assets,
  });

  /// The tag as GitHub wrote it — `v0.4.0`.
  final String tag;

  /// The tag without its leading `v` — `0.4.0`.
  ///
  /// This is the string compared against the running app's `versionName`.
  /// Version *codes* are never compared: Flutter's per-ABI offsets make a
  /// universal APK (9001) look older than an installed arm64 build (11001)
  /// at the same version.
  final String version;

  /// Whether GitHub marked this release as a pre-release.
  final bool prerelease;

  /// The release body as GitHub wrote it, empty when the release has none.
  final String notes;

  /// The published assets, in the order GitHub listed them.
  final List<UpdateAsset> assets;
}

/// One file attached to a release.
@immutable
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.sha256,
    required this.size,
  });

  /// The file name — `SN-Launcher-0.4.0-arm64-v8a.apk`.
  final String name;

  /// Where the file is downloaded from.
  final String url;

  /// The SHA-256 digest GitHub published for the file, empty when it
  /// published none. A missing digest is not a wrong one: it means there was
  /// no digest to publish.
  final String sha256;

  /// The file size in bytes, zero when GitHub did not say.
  final int size;
}

/// The asset name prefix for each published variant.
///
/// The variant is matched by the exact applicationId and never by a suffix
/// heuristic: `dev.snlauncher.snlauncher.perf` ends with another variant's
/// name and would be handed the wrong build.
const Map<String, String> _assetPrefixes = {
  'dev.snlauncher.snlauncher': 'SN-Launcher-',
  'dev.snlauncher.snlauncher.ef': 'SN-Launcher-ef-',
  'dev.snlauncher.snlauncher.perf': 'SN-Launcher-perf-',
};

/// The leading digits of a version component.
final RegExp _leadingDigits = RegExp(r'^\d+');

/// Reads a GitHub releases payload into releases.
///
/// Anything that is not a release list — a rate-limit message, an HTML error
/// page from a captive portal, a truncated body — reads as no releases. The
/// feed is a corner of the app and never a dependency of the home screen, so
/// a body it cannot read is a failed check rather than a crash.
List<UpdateRelease> parseReleases(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const [];
  }

  final List<dynamic> entries;
  if (decoded is List) {
    entries = decoded;
  } else if (decoded is Map && decoded['releases'] is List) {
    entries = decoded['releases'] as List<dynamic>;
  } else {
    return const [];
  }

  final releases = <UpdateRelease>[];
  for (final entry in entries) {
    if (entry is Map) releases.add(_release(entry));
  }
  return List.unmodifiable(releases);
}

/// Whether [candidate] is a newer version than [installed].
///
/// The comparison is on the numeric components of the version *name*. A
/// version that does not parse is not newer: an unparseable version is not
/// evidence of a newer build.
bool isNewerVersion(String candidate, String installed) {
  final left = _numbers(candidate);
  final right = _numbers(installed);
  if (left == null || right == null) return false;

  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    // A version with fewer components is missing zeroes rather than missing
    // evidence: 0.4 and 0.4.0 are the same version.
    final a = i < left.length ? left[i] : 0;
    final b = i < right.length ? right[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// Whether the version carries a pre-release suffix, such as `0.4.0-rc2`.
///
/// The suffix is what makes it a pre-release; the numeric triple underneath
/// it is what the comparison uses.
bool isPreReleaseVersion(String version) {
  final dash = version.indexOf('-');
  if (dash < 0) return false;
  return _numbers(version.substring(0, dash)) != null;
}

/// The name of the file that carries [version] for [applicationId] on [abi].
///
/// Empty for an applicationId this project does not publish: there is no
/// asset for it, and offering one would offer a file that cannot run.
String expectedAssetName(String applicationId, String version, String abi) {
  final prefix = _assetPrefixes[applicationId];
  if (prefix == null) return '';
  return '$prefix$version-$abi.apk';
}

/// The asset in [release] that this build and this device can install, or
/// null when the release carries none.
///
/// The match is on the exact file name, because the canonical names are the
/// only ones the updater can use. The historical ones — `-arm64`, `-armv7`,
/// `-beta-` — are not among them, and a file named for another ABI does not
/// run here.
UpdateAsset? assetFor(
  UpdateRelease release, {
  required String applicationId,
  required String abi,
}) {
  final expected = expectedAssetName(applicationId, release.version, abi);
  if (expected.isEmpty) return null;
  for (final asset in release.assets) {
    if (asset.name == expected) return asset;
  }
  return null;
}

/// One release from the payload.
UpdateRelease _release(Map<Object?, Object?> entry) {
  // The tag is the version's source of truth. GitHub's `name` is the human
  // title, and is only consulted for a payload that carries no tag at all.
  final tag = _text(entry['tag_name']);
  final title = _text(entry['name']);
  final named = tag.isNotEmpty ? tag : title;

  return UpdateRelease(
    tag: named,
    version: _versionOf(named),
    prerelease: entry['prerelease'] == true,
    notes: _text(entry['body']),
    assets: _assets(entry['assets']),
  );
}

/// The assets of one release.
List<UpdateAsset> _assets(Object? raw) {
  if (raw is! List) return const [];
  final assets = <UpdateAsset>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    assets.add(
      UpdateAsset(
        name: _text(entry['name']),
        url: _text(entry['browser_download_url']),
        sha256: _digest(entry['digest']),
        size: _size(entry['size']),
      ),
    );
  }
  return List.unmodifiable(assets);
}

/// The version a tag names — `v0.4.0` is `0.4.0`, `0.4.0` is `0.4.0`.
String _versionOf(String tag) {
  if (tag.startsWith('v')) return tag.substring(1);
  return tag;
}

/// The numeric components of a version, or null when one does not parse.
///
/// The leading digits of each component are what count, so `0.4.0-rc2` is
/// the triple 0, 4, 0.
List<int>? _numbers(String version) {
  final parts = <int>[];
  for (final component in version.split('.')) {
    final digits = _leadingDigits.firstMatch(component);
    if (digits == null) return null;
    final value = int.tryParse(digits.group(0)!);
    if (value == null) return null;
    parts.add(value);
  }
  return parts;
}

/// The digest GitHub published, as the hex alone.
///
/// GitHub writes `sha256:<hex>`. A digest under another algorithm is not
/// this field's digest, and a digest with no algorithm at all is not one
/// either; both read as no digest.
String _digest(Object? raw) {
  if (raw is! String) return '';
  final colon = raw.indexOf(':');
  if (colon < 0) return '';
  if (raw.substring(0, colon).toLowerCase() != 'sha256') return '';
  return raw.substring(colon + 1);
}

/// The size of an asset in bytes, zero when GitHub did not say.
int _size(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return 0;
}

/// A string field of the payload, empty when it is missing or not a string.
String _text(Object? raw) => raw is String ? raw : '';

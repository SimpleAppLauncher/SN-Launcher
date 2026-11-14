import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/update_feed.dart';

/// A captured GitHub releases payload.
///
/// Taken from `GET https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases`
/// on 14 November 2026 and trimmed to the two releases and three assets the
/// tests below need. Every value left in it is the value GitHub sent: the
/// tags, the names, the bodies, the asset names, the sizes and the SHA-256
/// digests are the published ones.
///
/// The release bodies are cut to their opening lines. The parser reads a
/// body whole; the cut is visible only in the notes.
const String _capturedReleases = r'''
[
  {
    "url": "https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases/418540370",
    "assets_url": "https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases/418540370/assets",
    "upload_url": "https://uploads.github.com/repos/SimpleAppLauncher/SN-Launcher/releases/418540370/assets{?name,label}",
    "html_url": "https://github.com/SimpleAppLauncher/SN-Launcher/releases/tag/v0.3.0-rc2",
    "id": 418540370,
    "tag_name": "v0.3.0-rc2",
    "target_commitish": "master",
    "name": "v0.3.0-rc2 — the Rust library runs, and the weather page gets a photograph of the place",
    "draft": false,
    "prerelease": true,
    "created_at": "2026-10-20T15:10:28Z",
    "published_at": "2026-10-20T15:10:50Z",
    "body": "The Rust library runs on a device for the first time, and the weather page\ngets a photograph of where you are.",
    "assets": [
      {
        "url": "https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases/assets/659658418",
        "id": 659658418,
        "name": "SN-Launcher-0.3.0-rc2-arm64.apk",
        "label": "",
        "content_type": "application/vnd.android.package-archive",
        "state": "uploaded",
        "size": 10375707,
        "digest": "sha256:f153559b8a8afcb1262494156ecf97c2f98eb84f43dfb51474d027dc86b89fde",
        "download_count": 3,
        "created_at": "2026-10-20T15:10:36Z",
        "updated_at": "2026-10-20T15:10:44Z",
        "browser_download_url": "https://github.com/SimpleAppLauncher/SN-Launcher/releases/download/v0.3.0-rc2/SN-Launcher-0.3.0-rc2-arm64.apk"
      },
      {
        "url": "https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases/assets/659658400",
        "id": 659658400,
        "name": "SN-Launcher-0.3.0-rc2-x86_64.apk",
        "label": "",
        "content_type": "application/vnd.android.package-archive",
        "state": "uploaded",
        "size": 10569334,
        "digest": "sha256:625c73494bffffffbcb1ba27ccb052087937d4d01754fde66f639c58b5460e13",
        "download_count": 0,
        "created_at": "2026-10-20T15:10:36Z",
        "updated_at": "2026-10-20T15:10:49Z",
        "browser_download_url": "https://github.com/SimpleAppLauncher/SN-Launcher/releases/download/v0.3.0-rc2/SN-Launcher-0.3.0-rc2-x86_64.apk"
      }
    ],
    "tarball_url": "https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/tarball/v0.3.0-rc2",
    "zipball_url": "https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/zipball/v0.3.0-rc2"
  },
  {
    "url": "https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases/416298476",
    "assets_url": "https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases/416298476/assets",
    "upload_url": "https://uploads.github.com/repos/SimpleAppLauncher/SN-Launcher/releases/416298476/assets{?name,label}",
    "html_url": "https://github.com/SimpleAppLauncher/SN-Launcher/releases/tag/v0.1.3",
    "id": 416298476,
    "tag_name": "v0.1.3",
    "target_commitish": "master",
    "name": "v0.1.3 — the carousel can reach every page",
    "draft": false,
    "prerelease": false,
    "created_at": "2026-10-18T07:16:37Z",
    "published_at": "2026-10-18T07:17:27Z",
    "body": "## The carousel could only reach page 1\n\n`AnimationController` defaults to `upperBound: 1.0`, and `goToPage` animates to\nthe target page's **index**. So `animateTo(2.0)` was silently clamped to 1.0.",
    "assets": [
      {
        "url": "https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases/assets/652779726",
        "id": 652779726,
        "name": "SN-Launcher-0.1.3-arm64.apk",
        "label": "",
        "content_type": "application/vnd.android.package-archive",
        "state": "uploaded",
        "size": 18970621,
        "digest": "sha256:70275419a6f5f271a0ebdfbf6fa345fce360de0440ac581cea8bbae7487c2850",
        "download_count": 8,
        "created_at": "2026-10-18T07:17:12Z",
        "updated_at": "2026-10-18T07:17:22Z",
        "browser_download_url": "https://github.com/SimpleAppLauncher/SN-Launcher/releases/download/v0.1.3/SN-Launcher-0.1.3-arm64.apk"
      }
    ],
    "tarball_url": "https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/tarball/v0.1.3",
    "zipball_url": "https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/zipball/v0.1.3"
  }
]
''';

/// A hand-written payload for the two fields GitHub leaves out sometimes:
/// a release with no body, and an asset with no digest.
const String _sparseRelease = r'''
[
  {
    "tag_name": "v0.4.0",
    "name": "0.4.0",
    "prerelease": false,
    "body": null,
    "assets": [
      {
        "name": "SN-Launcher-0.4.0-arm64-v8a.apk",
        "browser_download_url": "https://github.com/SimpleAppLauncher/SN-Launcher/releases/download/v0.4.0/SN-Launcher-0.4.0-arm64-v8a.apk",
        "size": 10485760
      }
    ]
  }
]
''';

/// A payload whose asset carries a digest under another algorithm.
///
/// GitHub writes `sha256:<hex>`. A digest under a different algorithm is not
/// this field's SHA-256, so it reads as no digest rather than as a hash of
/// the wrong kind.
const String _otherAlgorithmDigest = r'''
[
  {
    "tag_name": "v0.4.0",
    "name": "0.4.0",
    "prerelease": false,
    "body": "A digest under another algorithm.",
    "assets": [
      {
        "name": "SN-Launcher-0.4.0-arm64-v8a.apk",
        "browser_download_url": "https://github.com/SimpleAppLauncher/SN-Launcher/releases/download/v0.4.0/SN-Launcher-0.4.0-arm64-v8a.apk",
        "size": 10485760,
        "digest": "sha512:abc123"
      }
    ]
  }
]
''';

/// A payload whose release carries no tag.
///
/// GitHub always sends `tag_name`. This is the shape a payload has when it
/// does not, and the release title is then the only name the release has.
const String _taglessRelease = r'''
[
  {
    "name": "v0.4.0",
    "prerelease": false,
    "body": "A release with no tag.",
    "assets": []
  }
]
''';

/// A payload whose asset carries a size that is not a number.
///
/// GitHub sends the size as a whole number of bytes. A payload that sends
/// anything else reads as no size at all.
const String _sizeAsText = r'''
[
  {
    "tag_name": "v0.4.0",
    "name": "0.4.0",
    "prerelease": false,
    "body": "A size that is not a number.",
    "assets": [
      {
        "name": "SN-Launcher-0.4.0-arm64-v8a.apk",
        "browser_download_url": "https://github.com/SimpleAppLauncher/SN-Launcher/releases/download/v0.4.0/SN-Launcher-0.4.0-arm64-v8a.apk",
        "size": "10485760"
      }
    ]
  }
]
''';

/// A payload whose asset carries a size with a fraction.
///
/// GitHub sends whole bytes. A payload that sends a fraction has a size the
/// updater cannot use as it stands, and the whole bytes are what it takes.
const String _fractionalSize = r'''
[
  {
    "tag_name": "v0.4.0",
    "name": "0.4.0",
    "prerelease": false,
    "body": "A size with a fraction.",
    "assets": [
      {
        "name": "SN-Launcher-0.4.0-arm64-v8a.apk",
        "browser_download_url": "https://github.com/SimpleAppLauncher/SN-Launcher/releases/download/v0.4.0/SN-Launcher-0.4.0-arm64-v8a.apk",
        "size": 10485760.5
      }
    ]
  }
]
''';

/// A release with the canonical asset names.
///
/// No published release uses these names — everything the project has
/// published so far is `-arm64` or `-armv7` — so this is written by hand
/// from the naming contract rather than captured.
const UpdateRelease _canonicalRelease = UpdateRelease(
  tag: 'v0.4.0',
  version: '0.4.0',
  prerelease: false,
  notes: '',
  assets: [
    UpdateAsset(
      name: 'SN-Launcher-0.4.0-arm64-v8a.apk',
      url: 'https://example.invalid/SN-Launcher-0.4.0-arm64-v8a.apk',
      sha256: '',
      size: 10485760,
    ),
    UpdateAsset(
      name: 'SN-Launcher-ef-0.4.0-arm64-v8a.apk',
      url: 'https://example.invalid/SN-Launcher-ef-0.4.0-arm64-v8a.apk',
      sha256: '',
      size: 10485760,
    ),
    UpdateAsset(
      name: 'SN-Launcher-0.4.0-x86_64.apk',
      url: 'https://example.invalid/SN-Launcher-0.4.0-x86_64.apk',
      sha256: '',
      size: 10485760,
    ),
  ],
);

void main() {
  group('parsing the feed', () {
    test('reads both releases of a captured payload, newest first', () {
      final releases = parseReleases(_capturedReleases);

      expect(releases, hasLength(2));
      expect(releases[0].tag, 'v0.3.0-rc2');
      expect(releases[1].tag, 'v0.1.3');
    });

    test('reads the version out of the tag', () {
      final releases = parseReleases(_capturedReleases);

      expect(releases[0].version, '0.3.0-rc2');
      expect(releases[1].version, '0.1.3');
    });

    test('reads the pre-release flag GitHub set', () {
      final releases = parseReleases(_capturedReleases);

      expect(releases[0].prerelease, isTrue);
      expect(releases[1].prerelease, isFalse);
    });

    test('reads the release body as the notes', () {
      final releases = parseReleases(_capturedReleases);

      expect(
        releases[0].notes,
        startsWith('The Rust library runs on a device for the first time'),
      );
      expect(releases[1].notes, startsWith('## The carousel could only reach'));
    });

    test('reads the assets of a release, in the order GitHub listed them', () {
      final releases = parseReleases(_capturedReleases);

      expect(releases[0].assets, hasLength(2));
      expect(releases[0].assets[0].name, 'SN-Launcher-0.3.0-rc2-arm64.apk');
      expect(releases[0].assets[1].name, 'SN-Launcher-0.3.0-rc2-x86_64.apk');
      expect(releases[1].assets, hasLength(1));
      expect(releases[1].assets[0].name, 'SN-Launcher-0.1.3-arm64.apk');
    });

    test('reads the url, the digest and the size of an asset', () {
      final asset = parseReleases(_capturedReleases)[0].assets[0];

      expect(
        asset.url,
        'https://github.com/SimpleAppLauncher/SN-Launcher/releases/download/'
        'v0.3.0-rc2/SN-Launcher-0.3.0-rc2-arm64.apk',
      );
      expect(
        asset.sha256,
        'f153559b8a8afcb1262494156ecf97c2f98eb84f43dfb51474d027dc86b89fde',
      );
      expect(asset.size, 10375707);
    });

    test('reads a release with no body as no notes', () {
      final releases = parseReleases(_sparseRelease);

      expect(releases, hasLength(1));
      expect(releases[0].notes, isEmpty);
    });

    test('reads an asset with no digest as no digest', () {
      final asset = parseReleases(_sparseRelease)[0].assets[0];

      expect(asset.sha256, isEmpty);
      expect(asset.size, 10485760);
    });

    test('reads a digest under another algorithm as no digest', () {
      // The hex of a SHA-512 is not this field's SHA-256, and carrying it as
      // one would be a hash that checks nothing.
      final asset = parseReleases(_otherAlgorithmDigest)[0].assets[0];

      expect(asset.sha256, isEmpty);
    });

    test('reads a release with no tag as the tag its title names', () {
      // A payload with no tag still has a name, and a release with no
      // version cannot be compared against anything.
      final release = parseReleases(_taglessRelease)[0];

      expect(release.tag, 'v0.4.0');
      expect(release.version, '0.4.0');
    });

    test('reads a size that is not a number as no size', () {
      final asset = parseReleases(_sizeAsText)[0].assets[0];

      expect(asset.size, 0);
    });

    test('reads a size with a fraction as the whole bytes', () {
      // The fraction is dropped rather than rounded, and rather than making
      // the size unknown: the file is not half a byte, and a size of zero
      // would read as "GitHub did not say".
      final asset = parseReleases(_fractionalSize)[0].assets[0];

      expect(asset.size, 10485760);
    });

    test('a body that is not JSON yields no releases', () {
      expect(parseReleases('not json at all'), isEmpty);
    });

    test('a rate-limited answer yields no releases', () {
      // GitHub answers a rate-limited request with a JSON object that is not a
      // release list. Reading it as one would be reading a message as a
      // release.
      expect(
        parseReleases('{"message":"API rate limit exceeded"}'),
        isEmpty,
      );
    });

    test('an object with a releases array is read as a release list', () {
      final releases = parseReleases('{"releases":$_sparseRelease}');

      expect(releases, hasLength(1));
      expect(releases[0].tag, 'v0.4.0');
    });
  });

  group('comparing versions', () {
    test('a higher version is newer than a lower one', () {
      expect(isNewerVersion('0.4.0', '0.3.0'), isTrue);
    });

    test('version components are compared as numbers, not as text', () {
      // "10" sorts before "9" as text, and 0.3.10 is newer than 0.3.9.
      expect(isNewerVersion('0.3.10', '0.3.9'), isTrue);
    });

    test('the same version is not newer than itself', () {
      expect(isNewerVersion('0.3.0', '0.3.0'), isFalse);
    });

    test('a lower version is not newer than a higher one', () {
      expect(isNewerVersion('0.3.0', '0.4.0'), isFalse);
    });

    test('a version that does not parse is not evidence of a newer build', () {
      // Neither side: an unparseable version is not a newer version, and it
      // is not an older one either.
      expect(isNewerVersion('garbage', '0.3.0'), isFalse);
      expect(isNewerVersion('0.4.0', 'garbage'), isFalse);
    });
  });

  group('pre-releases', () {
    test('a version with a pre-release suffix is a pre-release', () {
      expect(isPreReleaseVersion('0.4.0-rc2'), isTrue);
    });

    test('a version without a suffix is not a pre-release', () {
      expect(isPreReleaseVersion('0.4.0'), isFalse);
    });

    test('a pre-release compares on its numeric triple', () {
      expect(isNewerVersion('0.4.0-rc2', '0.3.0'), isTrue);
    });
  });

  group('choosing the asset', () {
    test('the reduced build expects the plain asset name', () {
      expect(
        expectedAssetName('dev.snlauncher.snlauncher', '0.4.0', 'arm64-v8a'),
        'SN-Launcher-0.4.0-arm64-v8a.apk',
      );
    });

    test('the ef build expects the ef asset name', () {
      expect(
        expectedAssetName(
          'dev.snlauncher.snlauncher.ef',
          '0.4.0',
          'arm64-v8a',
        ),
        'SN-Launcher-ef-0.4.0-arm64-v8a.apk',
      );
    });

    test('the perf build expects the perf asset name', () {
      expect(
        expectedAssetName(
          'dev.snlauncher.snlauncher.perf',
          '0.4.0',
          'arm64-v8a',
        ),
        'SN-Launcher-perf-0.4.0-arm64-v8a.apk',
      );
    });

    test('an unknown applicationId has no asset name', () {
      expect(
        expectedAssetName('com.example.other', '0.4.0', 'arm64-v8a'),
        isEmpty,
      );
    });

    test('finds the asset that matches this build and device', () {
      final asset = assetFor(
        _canonicalRelease,
        applicationId: 'dev.snlauncher.snlauncher',
        abi: 'arm64-v8a',
      );

      expect(asset, isNotNull);
      expect(asset!.name, 'SN-Launcher-0.4.0-arm64-v8a.apk');
    });

    test('finds the ef asset for the ef build', () {
      final asset = assetFor(
        _canonicalRelease,
        applicationId: 'dev.snlauncher.snlauncher.ef',
        abi: 'arm64-v8a',
      );

      expect(asset, isNotNull);
      expect(asset!.name, 'SN-Launcher-ef-0.4.0-arm64-v8a.apk');
    });

    test('finds nothing when the release has no asset for this ABI', () {
      final asset = assetFor(
        _canonicalRelease,
        applicationId: 'dev.snlauncher.snlauncher',
        abi: 'armeabi-v7a',
      );

      expect(asset, isNull);
    });

    test('does not match the historical arm64 token on an arm64 device', () {
      // "arm64" is not an Android ABI name and the published files use it
      // anyway. Offering one of those would offer a build this device may
      // not run.
      final release = parseReleases(_capturedReleases)[0];

      expect(
        assetFor(
          release,
          applicationId: 'dev.snlauncher.snlauncher',
          abi: 'arm64-v8a',
        ),
        isNull,
      );
    });

    test('finds nothing for an applicationId the project does not publish', () {
      final asset = assetFor(
        _canonicalRelease,
        applicationId: 'com.example.other',
        abi: 'arm64-v8a',
      );

      expect(asset, isNull);
    });
  });
}

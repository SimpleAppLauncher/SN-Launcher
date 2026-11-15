import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/update_feed.dart';

/// The publish script and the app have to agree on the file names.
///
/// They are two pieces of code in two languages that both decide what a
/// release's assets are called. When they disagree, the release exists and the
/// updater cannot see it — which is exactly what happened the first time the
/// script ran: it built six APKs, named the arm64 one, and then stopped with
/// "unknown ABI in sn-launcher-armeabi-v7a-release.apk", because its table
/// knew the ABI under Gradle's old name (`armel`) and not the one Gradle
/// actually uses.
///
/// These tests are the guard for that. They read the script off disk, the same
/// way the permission drift test reads the build script.
void main() {
  final script = File('tool/publish_release.sh').readAsStringSync();

  /// The `canonical_abi` table: the name Gradle uses → the name Android
  /// reports.
  Map<String, String> abiTable() {
    final pattern = RegExp(
      r'^\s*([a-z0-9_\-]+)\)\s+echo\s+"([a-z0-9_\-]+)"',
      multiLine: true,
    );
    return {
      for (final m in pattern.allMatches(script))
        m.group(1)!: m.group(2)!,
    };
  }

  test('every ABI Android reports is one the script can name', () {
    // These are the values Build.SUPPORTED_ABIS returns, which is what the
    // native appInfo hands to the Dart side.
    final table = abiTable();
    for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      expect(
        table[abi],
        abi,
        reason: 'the publish script does not know the ABI "$abi"',
      );
    }
  });

  test('the script names the assets the way the app looks for them', () {
    // The whole contract: the app asks for one exact name and the script
    // publishes it. The script writes the name with shell variables; the app
    // writes it with Dart ones. They have to be the same name.
    const templates = {
      'dev.snlauncher.snlauncher': r'SN-Launcher-$version-$abi.apk',
      'dev.snlauncher.snlauncher.ef': r'SN-Launcher-ef-$version-$abi.apk',
    };
    templates.forEach((applicationId, template) {
      for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
        final fromApp = expectedAssetName(applicationId, '0.4.1', abi);
        expect(fromApp, isNotEmpty);
        // The app's name, with the version and ABI put back as the script's
        // variables, has to be the script's template.
        final fromScript = fromApp
            .replaceFirst('0.4.1', r'$version')
            .replaceFirst(abi, r'$abi');
        expect(
          fromScript,
          template,
          reason: 'the app looks for "$fromApp" and the script builds "$template"',
        );
        expect(
          script.contains(template),
          isTrue,
          reason: 'the publish script does not build "$template"',
        );
      }
    });
  });

  test('the script publishes a pre-release as a pre-release', () {
    // A version with a dash in it is not finished. GitHub has to be told, or
    // the release shows up as the newest stable one and every user is offered
    // a build that is not.
    expect(script, contains('--prerelease'));
  });

  test('the script refuses to publish over an existing release', () {
    expect(script, contains('gh release view'));
  });

  test('the script checks the permissions of the files it publishes', () {
    expect(script, contains('tool/verify_permissions.sh'));
  });
}

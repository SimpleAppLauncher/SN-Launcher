import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/services/permission_service.dart';
import 'package:sn_launcher/src/services/platform_bridge.dart';
import 'package:sn_launcher/src/services/settings_store.dart';

/// A platform that answers permission questions the way a real phone would:
/// it knows which permissions this build's manifest declares, and which of
/// them the user has granted.
class _FakePlatform extends PlatformBridge {
  _FakePlatform({
    Set<String> declared = const <String>{},
    Set<String> granted = const <String>{},
    this.grants = const <String, bool>{},
    this.noPermissionModel = false,
    this.canShowRationale = true,
  }) : declared = {...declared},
       granted = {...granted};

  /// Whether the app's own settings screen was opened.
  bool settingsOpened = false;

  /// The permissions this build declares in its manifest.
  final Set<String> declared;

  /// The permissions the user has granted.
  final Set<String> granted;

  /// What the system answers when each permission is requested.
  final Map<String, bool> grants;

  /// True on a platform with no permission model at all (desktop).
  final bool noPermissionModel;

  /// Whether the system will still show a dialog if we ask.
  final bool canShowRationale;

  /// Every permission the app asked the platform for, in order.
  final List<String> asked = [];

  @override
  Future<PermissionProbe?> probePermission(String permission) async {
    if (noPermissionModel) return null;
    return PermissionProbe(
      declared: declared.contains(permission),
      granted: granted.contains(permission),
      canShowRationale: canShowRationale,
    );
  }

  @override
  Future<bool?> requestPermission(String permission) async {
    asked.add(permission);
    if (noPermissionModel) return null;
    if (!declared.contains(permission)) return false;
    final answer = grants[permission] ?? false;
    if (answer) granted.add(permission);
    return answer;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened = true;
    return true;
  }
}

SettingsStore _storeIn(File file) => SettingsStore(fallbackPath: file.path);

void main() {
  // The settings store reaches for a platform channel to read and write, and
  // the channel needs a binding even when the native side is not there.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what the platform said', () {
    test('a permission this build does not declare is reported missing',
        () async {
      // This is the state the shipped build was in: the calendar card was on,
      // the feature was there, and the manifest had no READ_CALENDAR in it, so
      // the request came back denied forever and the card said "Permission
      // needed" for the life of the install.
      final service = PermissionService(
        bridge: _FakePlatform(declared: <String>{}),
      );

      await service.refresh();

      expect(
        service.state(AppPermission.calendar),
        PermissionState.notInThisBuild,
      );
    });

    test('a granted permission reads as allowed', () async {
      final service = PermissionService(
        bridge: _FakePlatform(
          declared: <String>{'calendar'},
          granted: <String>{'calendar'},
        ),
      );

      await service.refresh();

      expect(service.state(AppPermission.calendar), PermissionState.allowed);
    });

    test('a declared permission the user refused reads as denied', () async {
      final service = PermissionService(
        bridge: _FakePlatform(declared: <String>{'calendar'}),
      );

      await service.refresh();

      expect(service.state(AppPermission.calendar), PermissionState.denied);
    });

    test('a platform with no permission model is not applicable', () async {
      final service = PermissionService(
        bridge: _FakePlatform(noPermissionModel: true),
      );

      await service.refresh();

      expect(
        service.state(AppPermission.calendar),
        PermissionState.notApplicable,
      );
    });
  });

  group('asking', () {
    test('a permission this build does not declare is never asked for',
        () async {
      final platform = _FakePlatform(declared: <String>{});
      final service = PermissionService(bridge: platform);

      final granted = await service.request(AppPermission.calendar);

      expect(granted, isFalse);
      expect(platform.asked, isEmpty);
      expect(
        service.state(AppPermission.calendar),
        PermissionState.notInThisBuild,
      );
    });

    test('a granted request reports the permission as allowed', () async {
      final platform = _FakePlatform(
        declared: <String>{'microphone'},
        grants: <String, bool>{'microphone': true},
      );
      final service = PermissionService(bridge: platform);

      final granted = await service.request(AppPermission.microphone);

      expect(granted, isTrue);
      expect(platform.asked, <String>['microphone']);
      expect(service.state(AppPermission.microphone), PermissionState.allowed);
    });

    test('a refused request reports the permission as denied', () async {
      final platform = _FakePlatform(declared: <String>{'microphone'});
      final service = PermissionService(bridge: platform);

      final granted = await service.request(AppPermission.microphone);

      expect(granted, isFalse);
      expect(service.state(AppPermission.microphone), PermissionState.denied);
    });

    test('a refused request the system will not ask about again is blocked',
        () async {
      // The user chose "don't ask again". Asking a second time returns denied
      // without a dialog ever appearing, so the only honest offer left is the
      // app's own settings screen.
      final platform = _FakePlatform(
        declared: <String>{'microphone'},
        canShowRationale: false,
      );
      final service = PermissionService(bridge: platform);

      await service.request(AppPermission.microphone);

      expect(service.state(AppPermission.microphone), PermissionState.blocked);
    });

    test('a blocked permission can be sent to the settings screen', () async {
      final platform = _FakePlatform(declared: <String>{'microphone'});
      final service = PermissionService(bridge: platform);

      final opened = await service.openSettings();

      expect(opened, isTrue);
      expect(platform.settingsOpened, isTrue);
    });

    test('the refusal is remembered across a restart', () async {
      // Otherwise a launcher that was blocked last week would offer a button
      // that silently does nothing.
      final file = File(
        '${Directory.systemTemp.path}/sn_perm_asked_${DateTime.now().microsecondsSinceEpoch}.json',
      );
      addTearDown(() async {
        if (file.existsSync()) await file.delete();
      });

      final first = PermissionService(
        bridge: _FakePlatform(declared: <String>{'microphone'}, canShowRationale: false),
        settings: _storeIn(file),
      );
      await first.settings?.load();
      await first.request(AppPermission.microphone);
      await first.settings?.load();

      final second = PermissionService(
        bridge: _FakePlatform(declared: <String>{'microphone'}, canShowRationale: false),
        settings: _storeIn(file),
      );
      await second.settings?.load();
      await second.refresh();

      expect(second.state(AppPermission.microphone), PermissionState.blocked);
    });
  });

  group('which permissions this build needs', () {
    test('a feature that is switched off needs nothing', () {
      final flags = FeatureFlags.parse('{"features":{}}', 'test');

      expect(PermissionService.requiredFor(flags), isEmpty);
    });

    test('the calendar card needs the calendar', () {
      final flags = FeatureFlags.parse(
        '{"features":{"calendar":true}}',
        'test',
      );

      expect(
        PermissionService.requiredFor(flags),
        <AppPermission>[AppPermission.calendar],
      );
    });

    test('the voice command needs the microphone', () {
      final flags = FeatureFlags.parse(
        '{"features":{"voiceCommand":true}}',
        'test',
      );

      expect(
        PermissionService.requiredFor(flags),
        <AppPermission>[AppPermission.microphone],
      );
    });

    test('every requirement names the feature that switches it on', () {
      // A permission with no feature behind it is a permission nobody asked
      // for, which is the thing this whole service exists to prevent.
      for (final r in kPermissionRequirements) {
        expect(r.feature, isNotEmpty);
        expect(r.title, isNotEmpty);
        expect(r.reason, isNotEmpty);
      }
    });
  });

  group('the build script and the app agree', () {
    // The app and the build script both decide which permissions a build
    // needs. They are written in different languages, in different files,
    // for the same decision — so this checks they still say the same thing.
    //
    // The script's table looks like:
    //
    //     calendar)     echo "READ_CALENDAR" ;;
    final script = File('tool/permissions_for.sh').readAsStringSync();
    final pattern = RegExp(r'^\s*(\w+)\)\s+echo "([A-Z_]+)"', multiLine: true);
    final table = <String, String>{
      for (final m in pattern.allMatches(script))
        m.group(1)!: m.group(2)!,
    };

    test('the build script declares what the app expects', () {
      for (final r in kPermissionRequirements) {
        expect(
          table[r.feature],
          r.permission.androidName,
          reason:
              'the build script and the app disagree about what '
              '"${r.feature}" needs',
        );
      }
    });

    test('the build script declares nothing the app does not use', () {
      for (final entry in table.entries) {
        expect(
          kPermissionRequirements.any((r) => r.feature == entry.key),
          isTrue,
          reason:
              'the build script declares a permission for "${entry.key}", which '
              'no feature in the app uses',
        );
      }
    });

    test('the build script asks for exactly what the app needs', () async {
      // The end-to-end check: run the script the build runs, and compare what
      // it says against what this app believes the build needs.
      for (final file in ['assets/features.json', 'assets/features.ef.json']) {
        final flags = FeatureFlags.parse(File(file).readAsStringSync(), file);
        final expected = PermissionService.requiredFor(flags)
            .map((p) => p.androidName)
            .join(',');
        final result = await Process.run(
          'bash',
          ['tool/permissions_for.sh', file],
        );
        expect(
          result.stdout.toString().trim(),
          expected,
          reason: '$file asks for the wrong permissions',
        );
      }
    });
  });
}

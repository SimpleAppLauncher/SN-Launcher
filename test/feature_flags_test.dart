import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/models/nest_action.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';

/// These read the two config files **off disk** rather than through
/// [FeatureFlags.load].
///
/// That distinction is the point. `load` would happily parse a file whose
/// contents are wrong; only reading the shipped bytes can tell us that
/// `assets/features.json` actually says what this project claims it says.
FeatureFlags loadFile(String name) =>
    FeatureFlags.parse(File('assets/$name').readAsStringSync(), 'assets/$name');

void main() {
  group('parsing', () {
    test('reads the features node', () {
      final f = FeatureFlags.parse('{"features":{"assistant":true}}', 't');
      expect(f.isOn('assistant'), isTrue);
      expect(f.isOn('music'), isFalse);
    });

    test('accepts a flat map with no features wrapper', () {
      final f = FeatureFlags.parse('{"assistant":true,"music":false}', 't');
      expect(f.isOn('assistant'), isTrue);
      expect(f.isOn('music'), isFalse);
    });

    test('ignores non-boolean values rather than guessing', () {
      // "yes" is not true. Coercing it would mean a typo silently enables a
      // feature the author meant to disable.
      final f = FeatureFlags.parse('{"features":{"assistant":"yes"}}', 't');
      expect(f.isOn('assistant'), isFalse);
    });

    test('malformed JSON fails closed, not open', () {
      // The whole design rests on this: a broken config must produce a
      // launcher with nothing switched on, never one that invents
      // capabilities it was not built with.
      final f = FeatureFlags.parse('{"features": {', 't');
      expect(f.all, isEmpty);
      expect(f.isOn('assistant'), isFalse);
    });

    test('a JSON array or scalar fails closed', () {
      expect(FeatureFlags.parse('[1,2,3]', 't').all, isEmpty);
      expect(FeatureFlags.parse('42', 't').all, isEmpty);
    });

    test('reports flags this build does not implement', () {
      // Otherwise a typo like "assisstant" is silently ignored and the author
      // spends an afternoon wondering why nothing happens.
      final f = FeatureFlags.parse(
        '{"features":{"assisstant":true,"assistant":true}}',
        't',
      );
      expect(f.unknown, ['assisstant']);
      expect(f.isOn('assistant'), isTrue);
    });

    test('comment keys are documentation, not unknown flags', () {
      final f = loadFile('features.json');
      expect(f.unknown, isEmpty, reason: '_comment must not read as a flag');
    });
  });

  group('the shipped ExtraFeature build', () {
    final f = loadFile('features.ef.json');

    test('enables every feature the build knows how to gate', () {
      // If someone adds a flag to FeatureFlags.known and forgets the ef file,
      // this is the test that says so. Without it the new feature ships
      // switched off in the one build that is supposed to show everything.
      final off = FeatureFlags.known.where((k) => !f.isOn(k)).toList();
      expect(off, isEmpty, reason: 'ef build leaves $off off');
    });

    test('declares no flags the build does not know', () {
      expect(f.unknown, isEmpty);
    });
  });

  group('the shipped reduced build', () {
    final f = loadFile('features.json');

    /// What "reduced" means: a launcher, and nothing else. These two stay on
    /// in both builds because without them it is not a launcher — there is no
    /// way to reach brightness, volume, or configuration.
    const core = {'settings', 'quickSettings'};

    test('keeps the launcher core on', () {
      expect(
        core.where(f.isOn).toSet(),
        core,
        reason: 'reduced build lost a core launcher capability',
      );
    });

    test('has every optional extra switched off', () {
      // The whole point of the reduced build. Guarded explicitly so that
      // flipping a flag on in this file is a deliberate act, not an accident
      // that ships to users.
      final on = FeatureFlags.known
          .where((k) => !core.contains(k))
          .where(f.isOn)
          .toList();
      expect(on, isEmpty, reason: 'reduced build unexpectedly enables $on');
    });

    test('declares no flags the build does not know', () {
      expect(f.unknown, isEmpty);
    });
  });

  group('quick-settings row', () {
    /// The ef build, with both optional buttons available.
    FeatureFlags efLike() => FeatureFlags.parse(
          '{"features":{"settings":true,"quickSettings":true,"digestPage":true}}',
          't',
        );

    test('is the full seven-button row on the ef build', () {
      // Seven, and it is a measurement rather than a preference: this row was
      // measured off a rectified photograph of a real Nest Hub Max. tool/
      // verify.py asserts the app-badge *pitch*, which this does not change.
      final row = quickSettingsFor(efLike());
      expect(row.length, 7);
      expect(
        row.map((q) => q.kind),
        containsAll(<QuickSettingKind>[
          QuickSettingKind.settings,
          QuickSettingKind.zoomIn,
        ]),
      );
    });

    test('drops the digest button when there is no digest page', () {
      // The bug this replaces: the reduced build kept the sparkles button,
      // which navigated to a page that renders nothing. Tapping it gave a blank
      // screen, which is what made the reduced build look broken on hardware.
      // Six buttons, every one of which does something.
      final f = FeatureFlags.parse(
        '{"features":{"settings":true,"quickSettings":true}}',
        't',
      );
      final row = quickSettingsFor(f);
      expect(row.length, 6);
      expect(row.map((q) => q.kind), isNot(contains(QuickSettingKind.zoomIn)));
    });

    test('drops the settings button when settings is off', () {
      final f = FeatureFlags.parse(
        '{"features":{"quickSettings":true,"digestPage":true}}',
        't',
      );
      final row = quickSettingsFor(f);
      expect(row.length, 6);
      expect(row.map((q) => q.kind), isNot(contains(QuickSettingKind.settings)));
    });

    test('drops both when both are off', () {
      final f = FeatureFlags.parse('{"features":{"quickSettings":true}}', 't');
      final row = quickSettingsFor(f);
      expect(row.length, 5);
      expect(
        row.map((q) => q.kind),
        isNot(anyOf(
          QuickSettingKind.settings,
          QuickSettingKind.zoomIn,
        )),
      );
    });

    test('is empty when the row itself is off', () {
      final f = FeatureFlags.parse('{"features":{"settings":true}}', 't');
      expect(quickSettingsFor(f), isEmpty);
    });

    test('the shipped builds produce the rows they should', () {
      // Reads the real files, so an edit to either JSON shows up here.
      expect(quickSettingsFor(loadFile('features.ef.json')).length, 7);
      expect(quickSettingsFor(loadFile('features.json')).length, 6);
    });
  });

  group('themes', () {
    test('the ef build offers all five, including Sun', () {
      final f = loadFile('features.ef.json');
      expect(availableThemes(f).length, NestTheme.values.length);
      expect(availableThemes(f), contains(NestTheme.dynamic));
    });

    test('the reduced build does not offer Sun', () {
      // "Sun" in the picker is NestTheme.dynamic, the time-of-day theme.
      final f = loadFile('features.json');
      expect(availableThemes(f), isNot(contains(NestTheme.dynamic)));
      expect(availableThemes(f).length, NestTheme.values.length - 1);
    });

    test('the reduced build still offers four, not none', () {
      final f = loadFile('features.json');
      expect(
        availableThemes(f),
        containsAll(<NestTheme>[
          NestTheme.white,
          NestTheme.day,
          NestTheme.afternoon,
          NestTheme.night,
        ]),
      );
    });

    test('the fallback is a theme the build actually has', () {
      // Deliberately not the first entry: the first entry is Sun, which is
      // exactly what is missing in the reduced build, so a first-entry
      // fallback would return the thing just excluded.
      final f = loadFile('features.json');
      expect(availableThemes(f), contains(fallbackTheme(f)));
      expect(fallbackTheme(f), NestTheme.day);
    });

    test('the fallback is a no-op on the ef build', () {
      final f = loadFile('features.ef.json');
      expect(fallbackTheme(f), NestTheme.day);
      expect(availableThemes(f), contains(fallbackTheme(f)));
    });
  });
}
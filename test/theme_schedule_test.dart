import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/models/nest_action.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/services/settings_store.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_type.dart';
import 'package:sn_launcher/src/widgets/settings_page.dart';

/// The time-based theme schedule: windows that say when a specific theme should
/// appear while the theme follows the time of day.
///
/// An empty schedule means the plain time-of-day theme, which is the default and
/// the behaviour every pre-existing test pins.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sn_theme_schedule_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('ThemeOverride windows', () {
    test('a window inside one day is half-open on both ends', () {
      final o = ThemeOverride(
        theme: NestTheme.night,
        startHour: 6,
        endHour: 12,
      );
      expect(o.contains(5.9), isFalse);
      expect(o.contains(6), isTrue);
      expect(o.contains(11.5), isTrue);
      expect(o.contains(12), isFalse);
    });

    test('a window that wraps past midnight', () {
      final o = ThemeOverride(
        theme: NestTheme.night,
        startHour: 22,
        endHour: 6,
      );
      expect(o.contains(21.9), isFalse);
      expect(o.contains(22), isTrue);
      expect(o.contains(23.5), isTrue);
      expect(o.contains(3), isTrue);
      expect(o.contains(5.9), isTrue);
      expect(o.contains(6), isFalse);
    });

    test('a zero-length window never applies', () {
      final o = ThemeOverride(theme: NestTheme.night, startHour: 6, endHour: 6);
      expect(o.contains(0), isFalse);
      expect(o.contains(6), isFalse);
      expect(o.contains(12), isFalse);
      expect(o.contains(23.9), isFalse);
      expect(o.contains(24), isFalse);
    });
  });

  group('ThemeOverride parsing', () {
    test('drops unusable entries without throwing', () {
      final parsed = ThemeOverride.listFromJson([
        {'theme': 'night', 'start': 22, 'end': 6},
        {'theme': 'dynamic', 'start': 1, 'end': 2},
        {'theme': 'nope', 'start': 1, 'end': 2},
        {'theme': 'day', 'start': '6', 'end': 12},
        {'theme': 'day', 'start': -1, 'end': 12},
        {'theme': 'day', 'start': 6, 'end': 25},
        {'theme': 'day', 'start': double.nan, 'end': 12},
        'not a map',
      ]);
      expect(parsed, hasLength(1));
      expect(parsed.single.theme, NestTheme.night);
      expect(parsed.single.startHour, 22);
      expect(parsed.single.endHour, 6);
      expect(ThemeOverride.listFromJson('bad'), isEmpty);
    });
  });

  group('AmbientPalette.resolve', () {
    test('no overrides keeps the time-of-day theme', () {
      expect(
        AmbientPalette.resolve(NestTheme.dynamic, const [], 3).name,
        AmbientPalette.at(3).name,
      );
      expect(
        AmbientPalette.resolve(NestTheme.night, const [], 3).name,
        AmbientPalette.of(NestTheme.night).name,
      );
    });

    test(
      'an override wins inside its window and the clock theme outside it',
      () {
        final o = ThemeOverride(
          theme: NestTheme.night,
          startHour: 22,
          endHour: 24,
        );
        expect(
          AmbientPalette.resolve(NestTheme.dynamic, [o], 23).name,
          AmbientPalette.of(NestTheme.night).name,
        );
        expect(
          AmbientPalette.resolve(NestTheme.dynamic, [o], 12).name,
          AmbientPalette.at(12).name,
        );
      },
    );

    test('a pinned theme ignores the schedule', () {
      final o = ThemeOverride(theme: NestTheme.day, startHour: 0, endHour: 24);
      expect(
        AmbientPalette.resolve(NestTheme.day, [o], 14).name,
        AmbientPalette.of(NestTheme.day).name,
      );
    });
  });

  group('ShellController', () {
    test('an override repaints the palette through the clock tick', () {
      final controller = ShellController(
        metrics: NestMetrics.forSize(const Size(1280, 800)),
        vsync: const TestVSync(),
      );
      addTearDown(controller.dispose);
      controller.attachClock(ClockTicker(DateTime(2022, 5, 26, 23, 0, 0)));
      expect(controller.themeOverrides, isEmpty);
      expect(controller.palette.name, AmbientPalette.at(23).name);

      controller.addThemeOverride(
        const ThemeOverride(theme: NestTheme.night, startHour: 22, endHour: 6),
      );
      expect(controller.palette.name, 'Night');
      expect(
        controller.settings.get(SettingKeys.themeSchedule),
        isNotNull,
        reason: 'the schedule has to survive a restart through the store',
      );

      controller.attachClock(ClockTicker(DateTime(2022, 5, 26, 12, 0, 0)));
      expect(controller.palette.name, AmbientPalette.at(12).name);
    });

    test(
      'a schedule restores from the settings file after a restart',
      () async {
        FeatureFlags.forTesting = FeatureFlags.parse(
          '{"features":{"sunTheme":true,"themePicker":true,"settings":true}}',
          'theme-schedule-restore',
        );
        final path = '${tmp.path}/settings.json';
        final first = ShellController(
          metrics: NestMetrics.forSize(const Size(1280, 800)),
          vsync: const TestVSync(),
          settings: SettingsStore(fallbackPath: path),
        );
        addTearDown(first.dispose);
        await first.restore();
        first.addThemeOverride(
          const ThemeOverride(
            theme: NestTheme.night,
            startHour: 22,
            endHour: 6,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final second = ShellController(
          metrics: NestMetrics.forSize(const Size(1280, 800)),
          vsync: const TestVSync(),
          settings: SettingsStore(fallbackPath: path),
        );
        addTearDown(second.dispose);
        await second.restore();
        second.attachClock(ClockTicker(DateTime(2022, 5, 26, 23, 0, 0)));

        expect(second.themeOverrides, hasLength(1));
        expect(second.themeOverrides.single.theme, NestTheme.night);
        expect(second.palette.name, 'Night');
      },
    );
  });

  group('the settings page', () {
    testWidgets('offers the time-based theme editor while dynamic', (
      tester,
    ) async {
      FeatureFlags.forTesting = FeatureFlags.parse(
        '{"features":{"sunTheme":true,"themePicker":true,"settings":true}}',
        'theme-schedule-test',
      );
      final controller = ShellController(
        metrics: NestMetrics.forSize(const Size(800, 1340)),
        vsync: const TestVSync(),
      );
      addTearDown(controller.dispose);
      controller.setPaletteForTest(AmbientPalette.at(12));

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SettingsPage(
              metrics: controller.metrics,
              type: NestType(controller.metrics),
              palette: controller.palette,
              controller: controller,
              assistant: const AssistantSettings(
                enabled: false,
                backend: AssistantBackend.localOnly,
                geminiKey: '',
                homeAssistantUrl: '',
                homeAssistantToken: '',
                voiceEnabled: false,
                voiceCommandEnabled: true,
                busy: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Time-based themes'), findsOneWidget);
      expect(find.text('Add time-based theme'), findsOneWidget);
      const empty =
          'Not set. While the theme follows the time of day, the display '
          'picks its palette from the wall clock alone.';
      expect(find.text(empty), findsOneWidget);
    });

    testWidgets('does not offer the editor while a theme is pinned', (
      tester,
    ) async {
      FeatureFlags.forTesting = FeatureFlags.parse(
        '{"features":{"sunTheme":true,"themePicker":true,"settings":true}}',
        'theme-schedule-test',
      );
      final controller = ShellController(
        metrics: NestMetrics.forSize(const Size(800, 1340)),
        vsync: const TestVSync(),
      );
      addTearDown(controller.dispose);
      controller.setTheme(NestTheme.night);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SettingsPage(
              metrics: controller.metrics,
              type: NestType(controller.metrics),
              palette: controller.palette,
              controller: controller,
              assistant: const AssistantSettings(
                enabled: false,
                backend: AssistantBackend.localOnly,
                geminiKey: '',
                homeAssistantUrl: '',
                homeAssistantToken: '',
                voiceEnabled: false,
                voiceCommandEnabled: true,
                busy: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Time-based themes'), findsNothing);
    });
  });
}

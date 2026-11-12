import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/models/nest_action.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/services/settings_store.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_type.dart';
import 'package:sn_launcher/src/widgets/settings_page.dart';
import 'package:sn_launcher/src/widgets/snow_overlay.dart';

/// Christmas mode: the palette, the window it turns itself on in, and the snow.
///
/// The window matters: it opens at midnight on 1 December and closes at
/// midnight on 7 January, and a season that starts on the 2nd or ends on the
/// 8th is a bug the user sees every year.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sn_christmas_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ShellController controllerFor(DateTime now) {
    final c = ShellController(
      metrics: NestMetrics.forSize(const Size(1280, 800)),
      vsync: const TestVSync(),
      settings: SettingsStore(fallbackPath: '${tmp.path}/settings.json'),
    );
    c.attachClock(ClockTicker(now));
    return c;
  }

  group('the Christmas palette', () {
    test('is legible', () {
      expect(AmbientPalette.christmas.hasReadableInk, isTrue,
          reason: 'the clock is white text on this palette');
    });

    test('is a night palette, so the photograph behind it is dimmed', () {
      expect(AmbientPalette.christmas.isNight, isTrue);
      expect(AmbientPalette.christmas.isDark, isTrue);
    });

    test('has a name of its own', () {
      expect(AmbientPalette.christmas.name, 'Christmas');
    });
  });

  group('the automatic window', () {
    test('is closed the night before', () {
      final c = controllerFor(DateTime(2026, 11, 30, 23, 59));
      addTearDown(c.dispose);
      expect(c.christmasActive, isFalse);
    });

    test('opens at midnight on 1 December', () {
      final c = controllerFor(DateTime(2026, 12, 1, 0, 0));
      addTearDown(c.dispose);
      expect(c.christmasActive, isTrue);
    });

    test('is still open on the sixth of January at midnight to midnight', () {
      final c = controllerFor(DateTime(2027, 1, 6, 23, 59));
      addTearDown(c.dispose);
      expect(c.christmasActive, isTrue);
    });

    test('closes at midnight on 7 January', () {
      final c = controllerFor(DateTime(2027, 1, 7, 0, 0));
      addTearDown(c.dispose);
      expect(c.christmasActive, isFalse);
    });

    test('is closed in the middle of the summer', () {
      final c = controllerFor(DateTime(2026, 7, 4, 12, 0));
      addTearDown(c.dispose);
      expect(c.christmasActive, isFalse);
    });

    test('the automatic switch can be turned off', () {
      final c = controllerFor(DateTime(2026, 12, 1, 12, 0));
      addTearDown(c.dispose);
      expect(c.christmasActive, isTrue);
      c.toggleChristmasAuto();
      expect(c.christmasAuto, isFalse);
      expect(c.christmasActive, isFalse);
    });
  });

  group('the mode switch', () {
    test('turns the season on outside the window', () {
      final c = controllerFor(DateTime(2026, 7, 4, 12, 0));
      addTearDown(c.dispose);
      expect(c.christmasActive, isFalse);
      c.toggleChristmasMode();
      expect(c.christmasMode, isTrue);
      expect(c.christmasActive, isTrue);
      c.toggleChristmasMode();
      expect(c.christmasMode, isFalse);
      expect(c.christmasActive, isFalse);
    });

    test('takes the palette over completely, ignoring a pinned theme', () {
      final c = controllerFor(DateTime(2026, 7, 4, 12, 0));
      addTearDown(c.dispose);
      c.setTheme(NestTheme.white);
      expect(c.palette.name, isNot('Christmas'));
      c.toggleChristmasMode();
      expect(c.palette.name, 'Christmas');
    });

    test('the snow switch is independent of the mode and starts on', () {
      final c = controllerFor(DateTime(2026, 7, 4, 12, 0));
      addTearDown(c.dispose);
      expect(c.snowEnabled, isTrue);
      expect(c.christmasMode, isFalse);
      c.toggleSnow();
      expect(c.snowEnabled, isFalse);
      expect(c.christmasMode, isFalse,
          reason: 'turning the snow off must not turn the season off');
    });

    test('survives a restart through the settings file', () async {
      final path = '${tmp.path}/settings.json';
      final first = ShellController(
        metrics: NestMetrics.forSize(const Size(1280, 800)),
        vsync: const TestVSync(),
        settings: SettingsStore(fallbackPath: path),
      );
      addTearDown(first.dispose);
      await first.restore();
      first.toggleChristmasMode();
      first.toggleSnow();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final second = ShellController(
        metrics: NestMetrics.forSize(const Size(1280, 800)),
        vsync: const TestVSync(),
        settings: SettingsStore(fallbackPath: path),
      );
      addTearDown(second.dispose);
      await second.restore();
      expect(second.christmasMode, isTrue);
      expect(second.snowEnabled, isFalse);
    });
  });

  group('the snow', () {
    const shapes = <(String, Size)>[
      ('Nest Hub 1024x600', Size(1024, 600)),
      ('Hub Max 1280x800', Size(1280, 800)),
      ('T20 1143x686', Size(1143, 686)),
      ('4:3 1365x1024', Size(1365, 1024)),
      ('square 1200x1150', Size(1200, 1150)),
      ('ultrawide 2000x900', Size(2000, 900)),
      ('portrait 800x1280', Size(800, 1280)),
      ('1:1 1000x1000', Size(1000, 1000)),
      ('3:4 1080x1440', Size(1080, 1440)),
      ('9:16 1080x1920', Size(1080, 1920)),
      ('4:3 wide 1600x1200', Size(1600, 1200)),
    ];

    for (final (name, size) in shapes) {
      testWidgets('paints without overflow at $name', (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFF0B1A2A),
              body: Stack(
                children: [
                  Positioned.fill(
                    child: SnowOverlay(animate: false),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(SnowOverlay), findsOneWidget);
      });
    }

    testWidgets('paints the same picture twice when it is not animating',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Color(0xFF0B1A2A),
            body: Stack(
              children: [
                Positioned.fill(child: SnowOverlay(animate: false)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      Future<List<int>> capture() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first,
        );
        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.0);
          final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
          return data!.buffer.asUint8List();
        });
        return bytes!;
      }

      final first = await capture();
      await tester.pump(const Duration(milliseconds: 900));
      final second = await capture();

      expect(first, isNotEmpty);
      expect(second, first,
          reason: 'a frozen overlay must paint the same flakes every frame');
    });
  });

  group('the settings page', () {
    const shapes = <(String, Size)>[
      ('1:1', Size(1000, 1000)),
      ('4:3', Size(1365, 1024)),
      ('3:4', Size(1080, 1440)),
      ('9:16', Size(1080, 1920)),
    ];

    for (final (name, size) in shapes) {
      testWidgets('opens the Background and Christmas sections at $name',
          (tester) async {
        FeatureFlags.forTesting = FeatureFlags.parse(
          '{"features":{"settings":true,"themePicker":true}}',
          'christmas-settings',
        );
        addTearDown(() => FeatureFlags.forTesting = FeatureFlags.empty);

        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        final controller = ShellController(
          metrics: NestMetrics.forSize(size),
          vsync: const TestVSync(),
          settings: SettingsStore(fallbackPath: '${tmp.path}/settings.json'),
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
                  busy: false,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Background'), findsOneWidget);
        expect(find.text('Christmas'), findsOneWidget);
        expect(find.text('Christmas mode'), findsOneWidget);
      });
    }
  });
}

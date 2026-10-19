import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/clock_service.dart';
import 'package:sn_launcher/src/services/weather_service.dart';
import 'package:sn_launcher/src/services/settings_store.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_type.dart';
import 'package:sn_launcher/src/widgets/clock_block.dart';

/// Two settings that did nothing at all.
///
/// "Show seconds" drew the seconds and then froze them, because the flag
/// reached the display but never reached the clock service that owns the
/// timer. "Clock face size" wrote to a field that no drawing code read.
///
/// Both are here as behavioural tests, because the previous state was
/// "compiles, and the slider moves".
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sn_clock_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('show seconds', () {
    test('the clock ticks every second once seconds are shown', () {
      fakeAsync((async) {
        final clock = ClockService();
        var ticks = 0;
        clock.addListener(() => ticks++);

        // `fakeAsync` starts from the real wall clock, so a three-second
        // window is not a fixed distance from a minute boundary — it lands
        // somewhere different on every run. Asserting "exactly 0 ticks here"
        // therefore failed about one run in twenty, because roughly one time
        // in twelve a minute boundary genuinely falls inside the window and
        // the clock correctly ticks. The property under test is the *rate*,
        // so the assertion now permits the one legitimate tick.
        async.elapse(const Duration(seconds: 3));
        expect(
          ticks,
          lessThanOrEqualTo(1),
          reason: 'at minute resolution the clock may only tick if a minute '
              'boundary falls inside the window; waking every second is the '
              'bug this guards',
        );

        clock.setShowSeconds(true);
        final before = ticks;
        // Four seconds, expecting at least three. The boundary offset is the
        // same problem, and rounding the expectation down to 3 removes it
        // without weakening the test: a clock still on minute resolution
        // scores 1, not 3.
        async.elapse(const Duration(seconds: 4));
        expect(
          ticks - before,
          greaterThanOrEqualTo(3),
          reason: 'with seconds shown the clock has to wake every second',
        );
        clock.dispose();
      });
    });

    test('turning seconds off slows the clock back down', () {
      fakeAsync((async) {
        final clock = ClockService()..setShowSeconds(true);
        var ticks = 0;
        clock.addListener(() => ticks++);
        async.elapse(const Duration(seconds: 2));
        expect(ticks, greaterThanOrEqualTo(2));

        clock.setShowSeconds(false);
        final before = ticks;
        async.elapse(const Duration(seconds: 3));
        expect(
          ticks - before,
          0,
          reason: 'seconds off means back to waking on the minute',
        );
        clock.dispose();
      });
    });

    test('the setting reaches the clock service, not just the display', () {
      // The bug. The flag was on the controller, the controller redrew the
      // clock block, and the timer was never told.
      final clock = ClockService(autoTick: false);
      final controller = ShellController(
        metrics: NestMetrics.forSize(const Size(1280, 800)),
        vsync: const TestVSync(),
      );
      addTearDown(controller.dispose);
      addTearDown(clock.dispose);

      controller.onShowSecondsChanged = clock.setShowSeconds;

      expect(controller.showSeconds, isFalse);
      controller.toggleShowSeconds();
      expect(controller.showSeconds, isTrue);
      expect(
        clock.showSeconds,
        isTrue,
        reason: 'the clock service was never told, so the seconds were frozen',
      );

      controller.toggleShowSeconds();
      expect(clock.showSeconds, isFalse);
    });

    test('it is written to the settings store', () {
      // The old behaviour was to keep it in a field and lose it on restart.
      final controller = ShellController(
        metrics: NestMetrics.forSize(const Size(1280, 800)),
        vsync: const TestVSync(),
      );
      addTearDown(controller.dispose);

      controller.setShowSeconds(true);
      expect(controller.settings.get(SettingKeys.showSeconds), 'true');
    });
  });

  group('clock face size', () {
    Future<double> renderedClockSize(
      WidgetTester tester,
      double zoom,
    ) async {
      final m = NestMetrics.forSize(const Size(1280, 800));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'GoogleSans'),
          home: Material(
            color: const Color(0xFF000000),
            child: ClockBlock(
              metrics: m,
              type: NestType(m),
              palette: AmbientPalette.of(NestTheme.day),
              weather: WeatherNow.placeholder,
              now: DateTime(2022, 5, 26, 9, 45),
              zoom: zoom,
            ),
          ),
        ),
      );
      await tester.pump();
      final block = tester.widget<ClockBlock>(find.byType(ClockBlock));
      expect(block.zoom, zoom);
      // The clock is the first big Text in the block.
      final texts = tester.widgetList<Text>(find.byType(Text));
      final clockText = texts.firstWhere(
        (t) => t.data != null && t.data!.contains(':'),
      );
      return clockText.style!.fontSize!;
    }

    testWidgets('a bigger face really is bigger', (tester) async {
      final small = await renderedClockSize(tester, 1.0);
      final big = await renderedClockSize(tester, 1.8);
      expect(
        big,
        greaterThan(small),
        reason: 'the zoom was never read by anything that drew',
      );
      expect(big / small, closeTo(1.8, 0.01));
    });

    testWidgets('the measured size is the default', (tester) async {
      final m = NestMetrics.forSize(const Size(1280, 800));
      final at = await renderedClockSize(tester, 1.0);
      expect(at, closeTo(m.px(NestMetrics.clockFontSize), 0.5));
    });
  });
}

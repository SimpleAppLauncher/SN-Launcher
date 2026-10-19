import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/weather_service.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_type.dart';
import 'package:sn_launcher/src/widgets/clock_block.dart';

/// Layout tests for the clock block.
///
/// These exist because of a bug that no other test could see. The clock face
/// size slider worked, and the date line moved — in the wrong direction. The
/// sign of the offset was inverted, so raising the zoom pushed "Sun, Oct 18"
/// *down* into the digits and it rendered printed through the top of them.
///
/// The bug survived because everything that checked this block checked a
/// property, not a position: the zoom was applied, the date was present, both
/// assertions passed, and two words sat on top of each other.
///
/// The only thing that catches it is measuring the two rectangles and asking
/// whether they overlap.
void main() {
  const size = Size(800, 1340);
  final metrics = NestMetrics.forSize(size);

  Widget harness(double zoom) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: ClockBlock(
              metrics: metrics,
              type: NestType(metrics),
              palette: AmbientPalette.at(12),
              weather: const WeatherNow(
                temperatureC: 21,
                condition: WeatherCondition.partlyCloudy,
              ),
              now: DateTime(2026, 10, 18, 14, 15, 30),
              zoom: zoom,
              // The glyph's idle animation never stops, so pumpAndSettle would
              // spin until it times out. It is not what is under test here.
              animateWeather: false,
            ),
          ),
        ),
      );

  /// The painted boxes of the date text and the clock text.
  ({Rect date, Rect clock}) rectsAt(WidgetTester tester, double zoom) {
    final dateBox = tester.getRect(find.text('Sun, Oct 18'));
    final clockBox = tester.getRect(find.text('14:15'));
    return (date: dateBox, clock: clockBox);
  }

  group('the date and the clock do not collide', () {
    // 1.0 is the measured layout and must not move.
    testWidgets('at zoom 1.0 the date sits above the clock', (tester) async {
      await tester.pumpWidget(harness(1.0));
      await tester.pumpAndSettle();
      final r = rectsAt(tester, 1.0);
      expect(r.date.bottom, lessThanOrEqualTo(r.clock.top + 0.5),
          reason: 'the date must finish above the clock');
    });

    // The regression. At 1.2 the clock is taller, so the date has to get out
    // of its way; before the fix it moved down instead and overlapped.
    for (final zoom in [1.05, 1.1, 1.15, 1.2]) {
      testWidgets('at zoom $zoom they still do not overlap', (tester) async {
        await tester.pumpWidget(harness(zoom));
        await tester.pumpAndSettle();
        final r = rectsAt(tester, zoom);
        expect(r.date.bottom, lessThanOrEqualTo(r.clock.top + 0.5),
            reason: 'at $zoom the date bottom (${r.date.bottom}) is inside the '
                'clock (top ${r.clock.top}) — the date is being pushed the '
                'wrong way');
      });
    }

    testWidgets('the date moves UP as the zoom rises', (tester) async {
      await tester.pumpWidget(harness(1.0));
      await tester.pumpAndSettle();
      final at1 = rectsAt(tester, 1.0).date.bottom;

      await tester.pumpWidget(harness(1.2));
      await tester.pumpAndSettle();
      final at12 = rectsAt(tester, 1.2).date.bottom;

      expect(at12, lessThan(at1),
          reason: 'a taller clock must push the date upward, not downward');
    });
  });

  group('the temperature and the weather glyph scale with the clock', () {
    testWidgets('the temperature text grows with the zoom', (tester) async {
      await tester.pumpWidget(harness(1.0));
      await tester.pumpAndSettle();
      final small = tester.getRect(find.text('21°'));

      await tester.pumpWidget(harness(1.2));
      await tester.pumpAndSettle();
      final large = tester.getRect(find.text('21°'));

      expect(large.height, greaterThan(small.height),
          reason: 'a 1.2x clock with a 1.0x temperature reads as two '
              'unrelated accidents rather than one clock');
    });

    testWidgets('the whole block stays on screen at maximum zoom', (tester) async {
      await tester.pumpWidget(harness(1.2));
      await tester.pumpAndSettle();
      final clockBox = tester.getRect(find.text('14:15'));
      expect(clockBox.left, greaterThanOrEqualTo(-0.5));
      expect(clockBox.right, lessThanOrEqualTo(size.width + 0.5));
      expect(clockBox.bottom, lessThanOrEqualTo(size.height + 0.5));
    });
  });
}

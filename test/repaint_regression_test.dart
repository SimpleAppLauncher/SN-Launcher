import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/screens/nest_shell.dart';
import 'package:sn_launcher/src/services/assistant_service.dart';
import 'package:sn_launcher/src/services/clock_service.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/services/location_service.dart';
import 'package:sn_launcher/src/services/platform_bridge.dart';
import 'package:sn_launcher/src/services/settings_store.dart';
import 'package:sn_launcher/src/services/todo_service.dart';
import 'package:sn_launcher/src/services/weather_service.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/widgets/weather_page.dart';

/// The bug: the weather page showed a temperature and no place name.
///
/// `LocationService` had resolved, the place had been cached, and the weather
/// had fetched — `WeatherService` only fetches once it has coordinates, so
/// seeing weather at all proves a place existed. And the place name still did
/// not appear, because nothing repainted the page.
///
/// The reason was structural rather than a missing call: `_buildCarousel`
/// wrapped every page's *content* inside an `AnimatedBuilder`'s builder.
/// `AnimatedBuilder` delegates to `ListenableBuilder`, which caches the widget
/// its builder returned and only rebuilds when the animation notifies. A
/// `setState` from the location service rebuilt the subtree and was handed
/// straight back the cached widget.
///
/// So the page corrected itself the moment you swiped away and back — which is
/// why this looked like weather that "sometimes" had a location rather than a
/// bug with a cause.
///
/// These tests hold the page still and change state underneath it. No page
/// animation, no navigation: if the screen cannot be repainted by anything
/// other than a swipe, it is broken.
void main() {
  const size = Size(800, 1340);

  // Render with each shipped config, so the tests exercise the real JSON rather
  // than a hand-written feature set that could drift from it.
  FeatureFlags efFlags() =>
      FeatureFlags.parse(File('assets/features.ef.json').readAsStringSync(), 'ef');
  FeatureFlags reducedFlags() => FeatureFlags.parse(
    File('assets/features.json').readAsStringSync(),
    'reduced',
  );

  late Directory tmp;
  late LocationService location;
  late ShellController controller;
  late TodoService todo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sn_repaint_test');
    location = LocationService(
      const PlatformBridge(),
      SettingsStore(fallbackPath: '${tmp.path}/store.json'),
    );
    todo = TodoService(
      SettingsStore(fallbackPath: '${tmp.path}/todo.json'),
    );
    controller = ShellController(
      metrics: NestMetrics.forSize(size),
      vsync: const _NeverVsync(),
    );
    controller.setPaletteForTest(AmbientPalette.at(12));
    controller.setSheetForTest(0);
  });

  tearDown(() {
    location.dispose();
    controller.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });


  /// Pumps a bounded window rather than waiting for quiescence.
  ///
  /// `pumpAndSettle` cannot be used on the weather page: the condition glyph
  /// animates continuously, so the tree never goes idle and it times out. A
  /// fixed 800 ms is longer than any navigation here settles in — the longest
  /// is the 300 ms spring — and does not depend on the animations stopping.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpShell(WidgetTester tester) async {
    // Mirrors the harness the other shell tests use: a MaterialApp carrying the
    // real font, a Material ancestor for the to-do TextField, and decorations
    // switched off so the tree is not animating for unrelated reasons while we
    // are testing whether it repaints.
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'GoogleSans'),
        home: Material(
          color: const Color(0xFF000000),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: NestShell(
              controller: controller,
              clock: ClockService(autoTick: false),
              weather: WeatherService(),
              assistant: AssistantService(),
              todo: todo,
              location: location,
              animateDecorations: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('the weather page never implies knowledge it does not have', () {
    testWidgets('a failed lookup is stated, not hidden', (tester) async {
      FeatureFlags.forTesting = efFlags();
      addTearDown(() => FeatureFlags.forTesting = reducedFlags());

      await pumpShell(tester);
      controller.goToPage(ShellPage.weather);
      await settle(tester);

      // No place, and the lookup failed. Showing a confident 21° with nothing
      // else on the screen reads as "this is the weather where you are", which
      // is a claim the app cannot make. It has to say it does not know.
      location.setPlaceForTesting(
        null,
        error: 'Could not work out where this is',
      );
      await tester.pump();

      expect(find.byType(WeatherPage).hitTestable(), findsOneWidget);
      expect(find.textContaining('Could not work out'), findsOneWidget,
          reason: 'the page must say when it does not know where it is');
    });
  });

  group('the weather page repaints without being navigated to', () {
    testWidgets('a place that arrives later still appears', (tester) async {
      FeatureFlags.forTesting = efFlags();
      addTearDown(() => FeatureFlags.forTesting = reducedFlags());

      await pumpShell(tester);
      controller.goToPage(ShellPage.weather);
      await settle(tester);

      // Nothing has resolved yet, so there is no name to show.
      expect(find.textContaining('Sydney'), findsNothing);

      // This is the moment that used to be invisible: the location resolves
      // while the user is already looking at the page. No swipe, no
      // navigation, no animation — just state changing underneath.
      location.setPlaceForTesting(const GeoPlace(
        latitude: -33.87,
        longitude: 151.21,
        name: 'Sydney',
        source: 'wifi',
      ));
      await tester.pump();

      expect(find.byType(WeatherPage).hitTestable(), findsOneWidget);
      expect(find.text('Sydney'), findsOneWidget,
          reason: 'the weather page must show where the weather is from as '
              'soon as it knows — without waiting for a swipe');
    });

    testWidgets('the source of the fix is shown, not just the name',
        (tester) async {
      FeatureFlags.forTesting = efFlags();
      addTearDown(() => FeatureFlags.forTesting = reducedFlags());

      await pumpShell(tester);
      controller.goToPage(ShellPage.weather);
      await settle(tester);

      location.setPlaceForTesting(const GeoPlace(
        latitude: -33.87,
        longitude: 151.21,
        name: 'Sydney',
        source: 'wifi',
      ));
      await tester.pump();

      // A location derived from the network is not the same as one the device
      // knows, and the page says which it is. This is the project's rule: a
      // screen must never assert something more precise than it knows.
      expect(find.textContaining('Wi-Fi'), findsOneWidget);
    });

    testWidgets('a place with no name falls back to coordinates',
        (tester) async {
      FeatureFlags.forTesting = efFlags();
      addTearDown(() => FeatureFlags.forTesting = reducedFlags());

      await pumpShell(tester);
      controller.goToPage(ShellPage.weather);
      await settle(tester);

      // A device-sourced place has coordinates and no name, because nothing
      // reverse-geocodes it yet. It must still say *something* rather than
      // showing a bare temperature with no idea where it came from.
      location.setPlaceForTesting(const GeoPlace(
        latitude: -33.87,
        longitude: 151.21,
        source: 'gps',
      ));
      await tester.pump();

      expect(find.textContaining('-33.87'), findsOneWidget);
    });
  });
}

/// The controller is driven directly in these tests, so its ticker is never
/// pumped. A ticker that never fires is fine; one that throws is not.
class _NeverVsync implements TickerProvider {
  const _NeverVsync();
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

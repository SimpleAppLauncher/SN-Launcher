import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/location_service.dart';
import 'package:sn_launcher/src/services/weather_service.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_type.dart';
import 'package:sn_launcher/src/widgets/weather_artwork.dart';
import 'package:sn_launcher/src/widgets/weather_page.dart';

const _size = Size(800, 1340);

Widget page(WeatherNow w, {GeoPlace? place, bool locating = false}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'GoogleSans'),
      home: Material(
        color: const Color(0xFF000000),
        child: SizedBox(
          width: _size.width,
          height: _size.height,
          child: WeatherPage(
            weather: w,
            place: place,
            metrics: NestMetrics.forSize(_size),
            palette: AmbientPalette.at(12),
            type: NestType(NestMetrics.forSize(_size)),
            locating: locating,
          ),
        ),
      ),
    );

Future<void> loadRealFonts() async {
  // Without this every glyph renders as a filled rectangle — the Ahem font
  // Flutter's test environment substitutes — and the screenshots cannot be
  // looked at, which is the entire reason they exist. This exact failure mode
  // has shipped a "passing" icon test here before.
  for (final entry in {
    'GoogleSans': 'assets/fonts/GoogleSans-400.ttf',
    'Poppins': 'assets/fonts/Poppins-Regular.ttf',
    // The condition glyph is a Material Symbols glyph. Without this font it
    // renders as nothing at all, so the page looks like it has no icon and a
    // screenshot cannot tell you whether the icon is there.
    'MaterialIcons': 'assets/fonts/MaterialSymbolsRounded.ttf',
  }.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(File(entry.value).readAsBytes().then((b) =>
          ByteData.view(Uint8List.fromList(b).buffer)));
    await loader.load();
  }
}

void main() {
  setUpAll(loadRealFonts);

  group('the sentence says it like a person', () {
    test('rain, in the afternoon, reads as a sentence', () {
      expect(
        WeatherCondition.rain.sentence(15),
        "It's raining this afternoon.",
      );
    });

    test('the time of day is the part that makes it human', () {
      expect(WeatherCondition.rain.sentence(9), "It's raining this morning.");
      expect(WeatherCondition.rain.sentence(15), "It's raining this afternoon.");
      expect(WeatherCondition.rain.sentence(19), "It's raining this evening.");
      expect(WeatherCondition.rain.sentence(23), "It's raining tonight.");
      expect(WeatherCondition.rain.sentence(2), "It's raining tonight.");
    });

    test('no condition reads as a non-claim', () {
      // "unknown" must not be dressed up as anything. Saying the sky is doing
      // something unclear is honest; guessing "it's clear" is not.
      expect(WeatherCondition.unknown.sentence(14),
          'The sky is doing something unclear this afternoon.');
    });

    test('every condition produces a full sentence with a full stop', () {
      for (final c in WeatherCondition.values) {
        for (final hour in [0, 8, 13, 17, 22]) {
          final s = c.sentence(hour);
          expect(s.endsWith('.'), isTrue, reason: '"$s" has no full stop');
          expect(s.length, greaterThan(8), reason: '"$s" is too terse');
        }
      }
    });

    test('thunder is phrased as a presence, not a state', () {
      // "it's thundering" is not English. "there's a thunderstorm" is.
      expect(WeatherCondition.thunder.sentence(14),
          "There's a thunderstorm this afternoon.");
    });
  });

  group('the page renders', () {
    testWidgets('shows the sentence and the temperature', (tester) async {
      await tester.pumpWidget(page(const WeatherNow(
        temperatureC: 14,
        condition: WeatherCondition.rain,
      )));
      await tester.pump();
      expect(find.text('14°'), findsOneWidget);
      expect(find.textContaining('raining'), findsOneWidget);
    });

    testWidgets('shows the place when it has one', (tester) async {
      await tester.pumpWidget(page(
        const WeatherNow(temperatureC: 9, condition: WeatherCondition.cloudy),
        place: const GeoPlace(
          latitude: -33.87,
          longitude: 151.21,
          name: 'Sydney',
          source: 'wifi',
        ),
      ));
      await tester.pump();
      expect(find.text('Sydney'), findsOneWidget);
    });
  });

  group('screenshots', () {
    // Written so the page can actually be looked at. Every bug in this
    // project's history that mattered was invisible to a passing test and
    // obvious in a picture: four dots at four sizes, text wrapping mid-word,
    // two words printed through each other.
    final dir = Directory('build/weather_shots');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    for (final entry in {
      WeatherCondition.rain: 14,
      WeatherCondition.clear: 27,
      WeatherCondition.snow: -3,
      WeatherCondition.fog: 9,
      WeatherCondition.thunder: 18,
    }.entries) {
      testWidgets('${entry.key} renders to a file', (tester) async {
        tester.view.physicalSize = const Size(1600, 2680);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(page(WeatherNow(
          temperatureC: entry.value.toDouble(),
          condition: entry.key,
        )));
        await tester.pump(const Duration(milliseconds: 100));

        // toImage and the PNG encoder do real asynchronous work outside the
        // test's fake-async zone. Without runAsync they never complete and the
        // test hangs rather than failing, which is a miserable way to find out.
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          final image = await boundary.toImage(pixelRatio: 1.0);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null) return;
          File('${dir.path}/${entry.key.name}.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        });
      });
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';

/// Does every hour of the Dynamic theme actually produce readable text?
///
/// This exists because of a screenshot. The Dynamic theme at 07:43 on a Galaxy
/// Tab A7 Lite rendered a digest page where "Weather", "Music" and every body
/// line were washed out over a pale peach gradient — the cards were legible at
/// the right-hand edge of the screen and illegible through the middle, because
/// the background is a gradient and the card fill is translucent.
///
/// Day and Night were both fine, which is why nothing noticed: the failing
/// palette exists only in the interpolation between keyframes, and nobody was
/// looking at 07:43.
///
/// The cause was not the interpolation being wrong. It was that
/// `hasReadableInk` existed, was documented as the thing that prevents exactly
/// this, and had zero callers.

void main() {
  // Ten-minute steps, not hourly: the ramp is smootherstep between keyframes,
  // so the worst point is not on an hour boundary and a 24-sample sweep would
  // walk straight past it.
  const steps = 144;

  test('every minute of the day has readable ink', () {
    final bad = <String>[];
    for (var i = 0; i < steps; i++) {
      final hour = i * 24 / steps;
      final p = AmbientPalette.at(hour);
      if (!p.hasReadableInk) {
        bad.add('${hour.toStringAsFixed(2)}h '
            '(ink lum ${p.onSurface.computeLuminance().toStringAsFixed(3)}, '
            'surface lum ${p.surface.computeLuminance().toStringAsFixed(3)})');
      }
    }
    expect(bad, isEmpty, reason: 'unreadable hours: ${bad.join('; ')}');
  });

  test('the ambient light sensor cannot wash text out', () {
    // adaptToAmbientLight moves the background and leaves every ink colour
    // alone, so a dark theme's text can be slid past legibility by the sensor.
    for (final level in [0.0, 0.15, 0.3, 0.5, 0.7, 0.85, 1.0]) {
      for (var i = 0; i < steps; i++) {
        final hour = i * 24 / steps;
        final p = AmbientPalette.at(hour, ambientBrightness: level);
        expect(
          p.hasReadableInk,
          isTrue,
          reason: 'unreadable at ${hour.toStringAsFixed(2)}h, ambient $level',
        );
      }
    }
  });

  test('the pinned themes are untouched', () {
    // ensureReadableInk returns `this` when contrast already passes, so this
    // guards against a fix that quietly restyles Day or Night.
    for (final theme in NestTheme.values) {
      if (theme == NestTheme.dynamic) continue;
      final p = AmbientPalette.of(theme);
      expect(p.hasReadableInk, isTrue, reason: theme.name);
      expect(p.ensureReadableInk().onSurface, p.onSurface, reason: theme.name);
    }
  });

  test('the guard is doing real work, not merely being present', () {
    // Proves the hazard is real rather than theoretical: taken *without* the
    // guard, these palettes genuinely fail contrast. 2 of 48 come out of the
    // ambient-light path.
    var unguarded = 0;
    for (var i = 0; i < 24; i++) {
      final p = AmbientPalette.at(i.toDouble());
      for (final level in [0.0, 1.0]) {
        if (!p.adaptToAmbientLight(level).hasReadableInk) unguarded++;
      }
    }
    expect(unguarded, greaterThan(0),
        reason: 'premise: adaptToAmbientLight really does break contrast');
  });

  test('contrast is measured against the card fill, not the page behind it', () {
    // Documents a gap that is *not* closed. The digest cards sit on `surface`,
    // which is translucent, so the true background is the gradient underneath —
    // luminance 0.435 at the hour from the screenshot. A guard that only reads
    // the card fill can pass while the page still looks weak over a bright
    // gradient. The card fill is opaque enough here to carry it, but that is a
    // property of the card, not of the palette, and nothing asserts it.
    final p = AmbientPalette.at(7.72);
    expect(p.hasReadableInk, isTrue);
    expect(
      p.backgroundStops().last.computeLuminance(),
      greaterThan(0.3),
      reason: 'premise: the background behind the cards really is bright',
    );
  });

  test('the hour from the screenshot is fixed', () {
    // 07:43, the time the digest page was photographed unreadable.
    expect(AmbientPalette.at(7.72).hasReadableInk, isTrue);
  });
}
/// Weather, said the way a person would say it.
///
/// The brief was "oh at this time there's rain" — a sentence, not a table of
/// numbers. A Nest Hub does not say "PRECIPITATION 62%" on a screen you glance
/// at from across a kitchen; it tells you what is happening and lets the number
/// sit underneath.
///
/// Two rules this is built on:
///
///  * **Only what the data supports.** No "feels like" unless the API returned
///    a feels-like, no "until 6pm" unless there is a forecast. The API here
///    returns current conditions only, so the sentence never claims a time
///    range it cannot know.
///  * **Time of day only where it reads naturally.** "It's raining this
///    afternoon" is how people talk. "It's raining at 14:37" is not. Midnight
///    gets "tonight" and before noon gets "this morning", because that is the
///    word for it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/weather_service.dart';


extension WeatherSentence on WeatherCondition {
  /// The clause describing what is happening, e.g. `it's raining`.
  String get clause => switch (this) {
        WeatherCondition.clear => "it's clear",
        WeatherCondition.partlyCloudy => "it's a bit cloudy",
        WeatherCondition.cloudy => "it's overcast",
        WeatherCondition.fog => "it's foggy",
        WeatherCondition.drizzle => "it's drizzling",
        WeatherCondition.rain => "it's raining",
        WeatherCondition.snow => "it's snowing",
        WeatherCondition.thunder => "there's a thunderstorm",
        WeatherCondition.unknown => "the sky is doing something unclear",
      };

  /// The whole sentence.
  ///
  /// [hour] is the local hour, because "tonight" is a different sentence from
  /// "this afternoon" and it is the part that makes this read as something a
  /// person wrote rather than something a lookup table produced.
  String sentence(int hour) {
    final String partOfDay;
    if (hour >= 21 || hour < 5) {
      partOfDay = 'tonight';
    } else if (hour < 12) {
      partOfDay = 'this morning';
    } else if (hour < 18) {
      partOfDay = 'this afternoon';
    } else {
      partOfDay = 'this evening';
    }
    return '${capitalise(clause)} $partOfDay.';
  }

  static String capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Atmospheric artwork for the weather page.
///
/// Drawn in-app rather than fetched. Three reasons, in order of importance:
///
///  1. **It works offline.** A launcher on a wall cannot depend on a network
///     round trip to decide what the sky looks like.
///  2. **It costs nothing.** No licence to clear, no attribution to render, and
///     no megabytes on a device with 2 GB of RAM. The photo rotation already
///     downloads several hundred KB a day; this does not add to it.
///  3. **It cannot be wrong about licensing.** The hardest constraint in this
///     project is that a launcher cannot honour share-alike, so an image from
///     the internet is a licence decision every single time. Paint is not.
///
/// The trade is honest: this is illustration, not photography. It reads as
/// weather from across a room, which is the job.
class WeatherArtwork extends StatelessWidget {
  const WeatherArtwork({
    super.key,
    required this.condition,
    required this.ink,
    this.animate = true,
    this.tint,
  });

  final WeatherCondition condition;

  /// The page's ink colour, so the artwork belongs to the same sky it sits on.
  final Color ink;
  final bool animate;

  /// Optional multiply tint, used to seat the artwork into a photographic
  /// background rather than fighting it.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _WeatherArtworkPainter(
          condition: condition,
          ink: ink,
          seed: condition.index * 7919,
          animate: animate,
          tint: tint,
        ),
        isComplex: true,
        willChange: animate,
      ),
    );
  }
}

class _WeatherArtworkPainter extends CustomPainter {
  _WeatherArtworkPainter({
    required this.condition,
    required this.ink,
    required int seed,
    required this.animate,
    this.tint,
  }) : _random = math.Random(seed);

  final WeatherCondition condition;
  final Color ink;
  final bool animate;
  final Color? tint;

  /// One generator for the whole pass, seeded per condition.
  ///
  /// This has to be a single instance held in a field. As a getter returning
  /// `math.Random(seed)` it handed back a *newly seeded* generator on every
  /// access, so every "random" value was the same first value and all 130 rain
  /// streaks landed on one pixel. The page looked empty.
  ///
  /// Seeded rather than random so the same weather always draws the same
  /// pattern — someone looks at this screen every morning and a pattern that
  /// reshuffles each repaint reads as noise.
  final math.Random _random;

  @override
  void paint(Canvas canvas, Size size) {
    switch (condition) {
      case WeatherCondition.rain:
      case WeatherCondition.thunder:
      case WeatherCondition.drizzle:
        _rain(canvas, size);
      case WeatherCondition.snow:
        _snow(canvas, size);
      case WeatherCondition.fog:
        _fog(canvas, size);
      case WeatherCondition.cloudy:
      case WeatherCondition.partlyCloudy:
        _clouds(canvas, size);
      case WeatherCondition.clear:
      case WeatherCondition.unknown:
        _haze(canvas, size);
    }
    if (tint != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = tint!
          ..blendMode = BlendMode.srcATop
          ..color = tint!.withValues(alpha: 0.18),
      );
    }
  }

  Paint get _soft => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = ink.withValues(alpha: 0.22);

  void _rain(Canvas canvas, Size size) {
    final heavy = condition != WeatherCondition.drizzle;
    final count = heavy ? 130 : 70;
    final paint = _soft
      ..strokeWidth = heavy ? 1.6 : 1.1
      ..color = ink.withValues(alpha: heavy ? 0.30 : 0.20);
    for (var i = 0; i < count; i++) {
      final x = _random.nextDouble() * size.width;
      final y = _random.nextDouble() * size.height;
      final len = size.height * (heavy ? 0.055 : 0.032);
      canvas.drawLine(Offset(x, y), Offset(x - len * 0.28, y + len), paint);
    }
  }

  void _snow(Canvas canvas, Size size) {
    final paint = Paint()..color = ink.withValues(alpha: 0.34);
    for (var i = 0; i < 90; i++) {
      final c = Offset(
        _random.nextDouble() * size.width,
        _random.nextDouble() * size.height,
      );
      canvas.drawCircle(c, 1.2 + _random.nextDouble() * 2.4, paint);
    }
  }

  void _fog(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.height * 0.055
      ..color = ink.withValues(alpha: 0.10);
    for (var i = 0; i < 7; i++) {
      final y = size.height * (0.18 + i * 0.11);
      final inset = size.width * (0.04 + _random.nextDouble() * 0.06);
      canvas.drawLine(
        Offset(inset, y),
        Offset(size.width - inset, y),
        paint,
      );
    }
  }

  /// Clouds, in the top third of the page.
  ///
  /// Two things were wrong when this first shipped and both were only visible
  /// on a device screenshot, not in a test:
  ///
  ///  - **Overlapping alpha compounds.** Fifteen soft circles at 0.11 each,
  ///    overlapping, stack to roughly 0.8 where they cross. The page looked
  ///    like it was behind a field of soap bubbles.
  ///  - **The circles were enormous** — up to 0.22 of the page height, which
  ///    on this screen is nearly 300 px across, and they sat on top of the
  ///    temperature.
  ///
  /// So: fewer, much smaller, confined to the sky above the reading, and drawn
  /// through a single-alpha layer so overlaps do not compound.
  void _clouds(Canvas canvas, Size size) {
    // One path, filled once.
    //
    // Drawing fifteen overlapping circles at alpha 0.11 each compounds where
    // they cross — the stack reaches roughly 0.8 and the page ends up looking
    // like it is behind a field of soap bubbles. Filling a single path means
    // the overlaps are one region at one strength, which is what "cloudy"
    // looks like.
    //
    // Confined to the top third as well: the first version put 300px circles
    // straight across the temperature, which is not weather, it is a mistake.
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final cx = size.width * (0.16 + _random.nextDouble() * 0.68);
      final cy = size.height * (0.05 + _random.nextDouble() * 0.24);
      final r = size.height * (0.030 + _random.nextDouble() * 0.034);
      path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      path.addOval(Rect.fromCircle(
          center: Offset(cx + r * 0.85, cy + r * 0.16), radius: r * 0.66));
      path.addOval(Rect.fromCircle(
          center: Offset(cx - r * 0.80, cy + r * 0.20), radius: r * 0.56));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = ink.withValues(alpha: 0.09)
        ..style = PaintingStyle.fill,
    );
  }

  /// A low sun behind haze. Also one path, for the same reason as the clouds.
  void _haze(Canvas canvas, Size size) {
    final path = Path();
    final cx = size.width * 0.74;
    final cy = size.height * 0.16;
    for (var i = 5; i > 0; i--) {
      path.addOval(Rect.fromCircle(
          center: Offset(cx, cy), radius: size.height * 0.055 * i));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = ink.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_WeatherArtworkPainter old) =>
      old.condition != condition ||
      old.ink != ink ||
      old.tint != tint;
}

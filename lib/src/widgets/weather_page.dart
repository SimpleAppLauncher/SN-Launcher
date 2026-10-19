import 'package:flutter/material.dart';

import '../services/location_service.dart';
import '../services/weather_service.dart';
import 'weather_artwork.dart';
import '../theme/ambient_palette.dart';
import 'weather_glyph.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';

/// The weather, on a page of its own.
///
/// The weather used to be a card on the digest page, beside four others. That
/// was the wrong shape: the weather is the one thing on a Nest display that
/// deserves the whole screen, and a card squeezed into 155px showed a
/// temperature and two words.
///
/// **The background is the weather.** A Nest changes the colour of its panel
/// with the conditions, and that is the single strongest thing about seeing
/// the weather on one — the room's light changes. So the gradient here is
/// derived from the condition rather than from the time of day, and the whole
/// page is drawn in it.
///
/// **It says where it is, and how it knows.** A location derived from an IP
/// lookup is a guess; one derived from the device's own WiFi is not. The page
/// says which, because a temperature with no idea what it is a temperature
/// *of* is not much use.
class WeatherPage extends StatelessWidget {
  const WeatherPage({
    super.key,
    required this.weather,
    required this.place,
    this.locationError = '',
    required this.metrics,
    required this.palette,
    required this.type,
    this.locating = false,
  });

  final WeatherNow weather;
  final GeoPlace? place;

  /// Why the location could not be worked out, if it could not.
  ///
  /// Shown on the page rather than swallowed. A bare temperature with no idea
  /// where it came from is the single worst thing this screen could do: it
  /// looks authoritative and is not. If we cannot place the reading, the page
  /// says so instead of implying the number is about wherever you are.
  final String locationError;
  final NestMetrics metrics;
  final AmbientPalette palette;
  final NestType type;

  /// True while the location is being worked out.
  final bool locating;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final sky = _sky(weather.condition);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: sky,
        ),
      ),
      child: Stack(
        children: [
          // The weather, drawn. Rain streaks, snow, fog banks, a hazy sun —
          // enough that the page reads as weather from across a kitchen
          // rather than as a blue rectangle with a number on it.
          Positioned.fill(
            child: WeatherArtwork(
              condition: weather.condition,
              ink: _ink(sky),
            ),
          ),
          // The whole page is drawn in the sky's ink, not the palette's. A pale
          // sky needs dark text; a storm needs light text. Deciding it here
          // rather than per widget is what keeps the page coherent.
          Positioned.fill(
            child: DefaultTextStyle(
              style: type.caption(color: sky.last == Colors.white
                  ? const Color(0xFF0B1020)
                  : const Color(0xFFF7F9FF)),
              child: const SizedBox.shrink(),
            ),
          ),
          // Positioned.fill, not a bare child. The Stack's default fit is
          // loose, so an unpositioned Column gets loose constraints, sizes
          // itself to its widest child and sits in the top-left corner. The
          // temperature and the sentence were jammed against the left edge
          // instead of centred. Nothing caught it: every text was present,
          // every assertion passed, and it looked like a design choice in a
          // screenshot until you measured where the words actually were.
          Positioned.fill(
            child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: m.px(48),
                vertical: m.px(32),
              ),
              child: Column(
                children: [
                  _placeLine(m, sky),
                  const Spacer(),
                  WeatherGlyph(
                    condition: weather.condition,
                    color: _ink(sky),
                    animate: false,
                    size: Size(m.px(120), m.px(120)),
                  ),
                  SizedBox(height: m.px(18)),
                  // The temperature, in the clock's own face. The Nest sets
                  // the weather in the same type as the clock, and reusing it
                  // is what makes the page read as one design.
                  Text(
                    weather.shortLabel,
                    style: type.clock(color: _ink(sky)).copyWith(
                      fontSize: m.px(NestMetrics.clockFontSize) * 1.1,
                      letterSpacing:
                          type.clock(color: _ink(sky)).letterSpacing! * 1.1,
                    ),
                  ),
                  SizedBox(height: m.px(4)),
                  Text(
                    weather.condition.label,
                    style: type.sheetTitle(color: _ink(sky)),
                  ),
                  SizedBox(height: m.px(14)),
                  _highLow(m, sky),
                  SizedBox(height: m.px(10)),
                  // "It's raining this afternoon." A sentence, because that is
                  // how a person would say it and this is a screen someone
                  // glances at from across a room.
                  Text(
                    weather.condition.sentence(metrics.size.height > 0
                        ? DateTime.now().hour
                        : 12),
                    style: type.caption(color: _ink(sky).withValues(alpha: 0.8)),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  _footer(m, sky),
                ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeLine(NestMetrics m, List<Color> sky) {
    final name = place?.displayName ?? weather.location;
    if (!locating && name.isEmpty) {
      // Nothing to say about where this is. Say that, rather than showing a
      // confident-looking temperature and letting it be assumed.
      if (locationError.isEmpty) return const SizedBox.shrink();
      return Text(
        locationError,
        style: type.caption(color: _ink(sky).withValues(alpha: 0.6)),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (locating)
          Padding(
            padding: EdgeInsets.only(right: m.px(8)),
            child: SizedBox(
              width: m.px(14),
              height: m.px(14),
              child: CircularProgressIndicator(
                strokeWidth: m.px(2),
                valueColor: AlwaysStoppedAnimation(_ink(sky)),
              ),
            ),
          ),
        Flexible(
          child: Text(
            locating ? 'Working out where this is…' : name,
            style: type.caption(color: _ink(sky).withValues(alpha: 0.75)),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _highLow(NestMetrics m, List<Color> sky) {
    final high = weather.highC;
    final low = weather.lowC;
    if (high == null && low == null) return const SizedBox.shrink();
    final ink = _ink(sky).withValues(alpha: 0.85);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (high != null) ...[
          Text('H', style: type.caption(color: ink.withValues(alpha: 0.6))),
          SizedBox(width: m.px(4)),
          Text('${high.round()}°', style: type.caption(color: ink)),
        ],
        SizedBox(width: m.px(18)),
        if (low != null) ...[
          Text('L', style: type.caption(color: ink.withValues(alpha: 0.6))),
          SizedBox(width: m.px(4)),
          Text('${low.round()}°', style: type.caption(color: ink)),
        ],
      ],
    );
  }

  Widget _footer(NestMetrics m, List<Color> sky) {
    final ink = _ink(sky).withValues(alpha: 0.55);
    final source = place?.source;
    final line = switch (source) {
      'wifi' => 'Location from this device’s Wi-Fi',
      'gps' => 'Location from this device',
      'ip' => 'Approximate location, from the network',
      'manual' => 'Location set by hand',
      'cached' => 'Location from earlier',
      _ => null,
    };
    if (line == null) return const SizedBox.shrink();
    return Text(
      line,
      style: type.caption(color: ink),
      textAlign: TextAlign.center,
    );
  }

  /// The ink for the sky: dark on a pale sky, light on a deep one.
  Color _ink(List<Color> sky) {
    // The average luminance of the gradient decides it, so a page that is
    // dark at the top and light at the bottom does not end up with unreadable
    // text in the middle.
    final avg = sky
            .map((c) => c.computeLuminance())
            .reduce((a, b) => a + b) /
        sky.length;
    return avg > 0.45 ? const Color(0xFF0B1020) : const Color(0xFFF7F9FF);
  }

  /// The sky for a condition.
  ///
  /// A Nest's panel changes with the weather: blue and clear, a flat grey for
  /// cloud, a deep slate for a storm, and a cold white-blue for snow. These
  /// are invented rather than measured, because there is no photograph of a
  /// Nest Hub showing weather to measure from — which is the one thing on this
  /// page that is an eyeball rather than a measurement.
  static List<Color> _sky(WeatherCondition c) => switch (c) {
        WeatherCondition.clear => const [
            Color(0xFF4FA3E3),
            Color(0xFF8FCBF0),
            Color(0xFFDCEFFA),
          ],
        WeatherCondition.partlyCloudy => const [
            Color(0xFF6FA8D6),
            Color(0xFFA9C6DF),
            Color(0xFFE3E9EE),
          ],
        WeatherCondition.cloudy => const [
            Color(0xFF7C8A99),
            Color(0xFFA8B4C0),
            Color(0xFFD2D9DF),
          ],
        WeatherCondition.fog => const [
            Color(0xFF9AA6AC),
            Color(0xFFC2CACD),
            Color(0xFFE6EAEA),
          ],
        WeatherCondition.drizzle => const [
            Color(0xFF5E7284),
            Color(0xFF8A9DAB),
            Color(0xFFC3CFD7),
          ],
        WeatherCondition.rain => const [
            Color(0xFF3E5265),
            Color(0xFF63788A),
            Color(0xFF9DB0BD),
          ],
        WeatherCondition.snow => const [
            Color(0xFF6E7F92),
            Color(0xFFA3B3C4),
            Color(0xFFE6EEF5),
          ],
        WeatherCondition.thunder => const [
            Color(0xFF1E2733),
            Color(0xFF3A4756),
            Color(0xFF6B7A8B),
          ],
        WeatherCondition.unknown => const [
            Color(0xFF4A5568),
            Color(0xFF7C8798),
            Color(0xFFBFC7D1),
          ],
      };
}

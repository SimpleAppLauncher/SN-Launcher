import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';

/// Exact-value tests for the geometry.
///
/// Every other test in this repository asks a question like "does it overflow"
/// or "does it overlap". Those questions have a wide tolerance, and a wide
/// tolerance is what lets a layout regression through: move the clock by six
/// pixels and nothing complains, because nothing was measuring.
///
/// This file pins the numbers themselves. If a constant changes, the test
/// fails and the reason says what the constant was before and what it is now,
/// which is the difference between a red test and a red test you can act on.
///
/// The thresholds are the interesting part. `isSquare` is `aspect < 1.35`,
/// `isLandscape` is `aspect >= 1.35` — so the two meet exactly at 1.35 and
/// there is no gap and no overlap. A mutation that turns `<` into `<=` moves
/// that boundary by one pixel and these tests catch it.
void main() {
  group('the scale factor', () {
    test('the design canvas is the Nest Hub at 1024x600', () {
      expect(NestMetrics.designSize, const Size(1024, 600));
    });

    test('on the design canvas the scale is exactly 1', () {
      expect(NestMetrics.forSize(const Size(1024, 600)).u, 1.0);
    });

    test('on the Hub Max the scale is exactly 1.25', () {
      // 1280/1024 is 1.25 and 800/600 is 1.3333; the smaller wins.
      expect(NestMetrics.forSize(const Size(1280, 800)).u, 1.25);
    });

    test('an ultrawide window is limited by its height', () {
      // 2000/1024 = 1.953 but 900/600 = 1.5, so the canvas fits by height.
      expect(NestMetrics.forSize(const Size(2000, 900)).u, 1.5);
    });

    test('a portrait window scales by width, with the 1.28 boost', () {
      // 800/1024 = 0.78125; times 1.28 = 1.0 exactly.
      expect(NestMetrics.forSize(const Size(800, 1280)).u, 1.0);
    });

    test('a square window also scales by width', () {
      // 1000/1024 = 0.9766; times 1.28 = 1.25 exactly.
      expect(NestMetrics.forSize(const Size(1000, 1000)).u, 1.25);
    });

    test('a tall window is still capped by its height', () {
      // widthScale would be (400/1024)*1.28 = 0.5, heightCap 3000/600 = 5.
      // The height cap never wins for a portrait window, but if the window is
      // both narrow and short the smaller of the two must be used.
      final m = NestMetrics.forSize(const Size(400, 200));
      expect(m.u, lessThanOrEqualTo(0.5));
    });

    test('px multiplies by the scale', () {
      final m = NestMetrics.forSize(const Size(1280, 800));
      expect(m.px(100), 125.0);
      expect(m.px(0), 0.0);
      expect(m.px(NestMetrics.clockFontSize), 81 * 1.25);
    });

    test('the scale never goes negative for a degenerate window', () {
      final m = NestMetrics.forSize(const Size(0, 0));
      expect(m.u, greaterThanOrEqualTo(0));
      expect(m.aspect, 1.7, reason: 'a zero-height window reports 16:10');
    });
  });

  group('the aspect bands', () {
    test('the Nest Hub is landscape', () {
      final m = NestMetrics.forSize(const Size(1024, 600));
      expect(m.aspect, closeTo(1.70667, 0.0001));
      expect(m.isLandscape, isTrue);
      expect(m.isSquare, isFalse);
      expect(m.isPortrait, isFalse);
    });

    test('a 3:4 window is portrait', () {
      final m = NestMetrics.forSize(const Size(1080, 1440));
      expect(m.isPortrait, isTrue);
      expect(m.isSquare, isFalse);
      expect(m.isLandscape, isFalse);
    });

    test('a 1:1 window is square, not portrait', () {
      final m = NestMetrics.forSize(const Size(1000, 1000));
      expect(m.isPortrait, isFalse);
      expect(m.isSquare, isTrue);
      expect(m.isLandscape, isFalse);
    });

    test('the square and landscape bands meet exactly at 1.35', () {
      // 1350/1000 is exactly 1.35 — the boundary itself.
      final at = NestMetrics.forSize(const Size(1350, 1000));
      expect(at.aspect, 1.35);
      expect(at.isSquare, isFalse, reason: '1.35 is not below 1.35');
      expect(at.isLandscape, isTrue, reason: '1.35 is not under 1.35');
    });

    test('a hair under the boundary is square', () {
      final m = NestMetrics.forSize(const Size(1349, 1000));
      expect(m.aspect, lessThan(1.35));
      expect(m.isSquare, isTrue);
      expect(m.isLandscape, isFalse);
    });

    test('the narrow band is 720 wide', () {
      expect(NestMetrics.forSize(const Size(719, 600)).isNarrow, isTrue);
      expect(NestMetrics.forSize(const Size(720, 600)).isNarrow, isFalse);
    });
  });

  group('the aspect bonus', () {
    test('a 16:10 window gets no bonus', () {
      expect(NestMetrics.forSize(const Size(1024, 600)).aspectExtra, 0.0);
    });

    test('an ultrawide window gets the extra width', () {
      // 2000/900 = 2.2222; 1024/600 = 1.70667; the difference is 0.51556.
      final m = NestMetrics.forSize(const Size(2000, 900));
      expect(m.aspectExtra, closeTo(0.515556, 0.0001));
    });

    test('a narrow window never gets a negative bonus', () {
      expect(NestMetrics.forSize(const Size(800, 1280)).aspectExtra, 0.0);
    });
  });

  group('the clock anchor', () {
    test('a landscape window keeps the measured Nest Hub position', () {
      final m = NestMetrics.forSize(const Size(1024, 600));
      expect(m.clockBottomDistance, closeTo(600 - 534, 0.001));
    });

    test('the landscape anchor scales with the panel', () {
      final m = NestMetrics.forSize(const Size(1280, 800));
      expect(m.clockBottomDistance, closeTo(800 - 534 * 1.25, 0.001));
    });

    test('a square window anchors the clock a seventh of the way up', () {
      final m = NestMetrics.forSize(const Size(1000, 1000));
      expect(m.clockBottomDistance, closeTo(140, 0.001));
    });

    test('a portrait window anchors the clock a fifth of the way up', () {
      final m = NestMetrics.forSize(const Size(1080, 1440));
      expect(m.clockBottomDistance, closeTo(288, 0.001));
    });

    test('the date always sits one design-gap above the clock', () {
      for (final size in [
        const Size(1024, 600),
        const Size(1000, 1000),
        const Size(1080, 1440),
        const Size(2000, 900),
      ]) {
        final m = NestMetrics.forSize(size);
        expect(m.dateBottomDistance - m.clockBottomDistance,
            closeTo(m.px(89), 0.001));
      }
    });

    test('the album title always sits seven design pixels below the clock', () {
      for (final size in [
        const Size(1024, 600),
        const Size(1000, 1000),
        const Size(1080, 1440),
      ]) {
        final m = NestMetrics.forSize(size);
        expect(m.clockBottomDistance - m.albumTitleBottomDistance,
            closeTo(m.px(7), 0.001));
      }
    });
  });

  group('the sheet', () {
    test('the sheet takes 49.6% of the height', () {
      final m = NestMetrics.forSize(const Size(1024, 600));
      expect(m.sheetHeight, closeTo(297.6, 0.001));
      expect(m.sheetTop, closeTo(302.4, 0.001));
    });

    test('the sheet top and height always add up to the window height', () {
      for (final size in [
        const Size(1024, 600),
        const Size(1280, 800),
        const Size(1000, 1000),
        const Size(1080, 1440),
      ]) {
        final m = NestMetrics.forSize(size);
        expect(m.sheetTop + m.sheetHeight, closeTo(size.height, 0.001));
      }
    });

    test('the rows are fractions of the sheet, not of the screen', () {
      final m = NestMetrics.forSize(const Size(1024, 600));
      final h = m.sheetHeight;
      expect(m.sheetLocalAppRowCenter, closeTo(h * 0.347, 0.001));
      expect(m.sheetLocalDividerY, closeTo(h * 0.573, 0.001));
      expect(m.sheetLocalQsRowCenter, closeTo(h * 0.824, 0.001));
      expect(m.sheetLocalHandleY, closeTo(h * 0.072, 0.001));
    });

    test('the sheet rows keep their order down the sheet', () {
      final m = NestMetrics.forSize(const Size(1280, 800));
      expect(m.sheetLocalHandleY, lessThan(m.sheetLocalAppRowCenter));
      expect(m.sheetLocalAppRowCenter, lessThan(m.sheetLocalDividerY));
      expect(m.sheetLocalDividerY, lessThan(m.sheetLocalQsRowCenter));
    });
  });

  group('the drawer grid', () {
    test('the column count steps at the documented widths', () {
      expect(NestMetrics.forSize(const Size(1600, 900)).appGridColumns, 6);
      expect(NestMetrics.forSize(const Size(1500, 900)).appGridColumns, 6);
      expect(NestMetrics.forSize(const Size(1499, 900)).appGridColumns, 5);
      expect(NestMetrics.forSize(const Size(1100, 900)).appGridColumns, 5);
      expect(NestMetrics.forSize(const Size(1099, 900)).appGridColumns, 4);
      expect(NestMetrics.forSize(const Size(850, 900)).appGridColumns, 4);
      expect(NestMetrics.forSize(const Size(849, 900)).appGridColumns, 3);
      expect(NestMetrics.forSize(const Size(640, 900)).appGridColumns, 3);
      expect(NestMetrics.forSize(const Size(639, 900)).appGridColumns, 2);
    });

    test('the Nest Hub itself gets four columns, not six', () {
      // 1024 is under the 1100 step and over the 850 step, so it lands on four.
      expect(NestMetrics.forSize(const Size(1024, 600)).appGridColumns, 4);
    });
  });

  group('the measured constants', () {
    test('the clock is 81 design pixels with -2.15 tracking', () {
      expect(NestMetrics.clockFontSize, 81);
      expect(NestMetrics.clockLetterSpacing, -2.15);
    });

    test('the date is 23 design pixels', () {
      expect(NestMetrics.dateFontSize, 23);
    });

    test('the temperature is 35 design pixels', () {
      expect(NestMetrics.tempFontSize, 35);
    });

    test('the album title is 15 design pixels, not 25', () {
      expect(NestMetrics.albumTitleFontSize, 15);
    });

    test('the app badge is 80 across with 118 between centres', () {
      expect(NestMetrics.appBadgeSize, 80);
      expect(NestMetrics.appRowSpacing, 118);
    });

    test('the sheet fractions are the measured ones', () {
      expect(NestMetrics.sheetTopFraction, 0.496);
      expect(NestMetrics.appRowCenterFraction, 0.347);
      expect(NestMetrics.sheetDividerFraction, 0.573);
      expect(NestMetrics.qsRowCenterFraction, 0.824);
      expect(NestMetrics.handleFraction, 0.072);
    });
  });
}

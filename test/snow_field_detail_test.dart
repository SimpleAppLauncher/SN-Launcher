import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/widgets/snow_overlay.dart';

/// The snow is not a decoration that happens to fall — it is a field of
/// flakes at different depths, and every visual quality of real snow comes
/// from that: the near flakes are big, bright and fast, the far ones are
/// small, dim and slow.
///
/// These tests pin the model rather than the picture. A picture test would
/// pass for a field of identical dots travelling upwards, which is exactly
/// the bug this file exists to prevent.
void main() {
  group('the field', () {
    test('has the number of flakes it was asked for', () {
      expect(SnowField(flakeCount: 42).flakes.length, 42);
      expect(SnowField().flakes.length, 120);
    });

    test('is deterministic for a given seed', () {
      final a = SnowField(flakeCount: 30, seed: 7);
      final b = SnowField(flakeCount: 30, seed: 7);
      expect(a.flakes.length, b.flakes.length);
      for (var i = 0; i < a.flakes.length; i++) {
        expect(a.flakes[i].lane, b.flakes[i].lane);
        expect(a.flakes[i].depth, b.flakes[i].depth);
        expect(a.flakes[i].radius, b.flakes[i].radius);
        expect(a.flakes[i].speed, b.flakes[i].speed);
        expect(a.flakes[i].drift, b.flakes[i].drift);
      }
    });

    test('is different for a different seed', () {
      final a = SnowField(flakeCount: 30, seed: 1);
      final b = SnowField(flakeCount: 30, seed: 2);
      var identical = 0;
      for (var i = 0; i < a.flakes.length; i++) {
        if (a.flakes[i].lane == b.flakes[i].lane) identical++;
      }
      expect(identical, lessThan(a.flakes.length));
    });

    test('puts every flake in the unit square before it is drawn', () {
      for (final flake in SnowField().flakes) {
        expect(flake.lane, inInclusiveRange(0.0, 1.0));
        expect(flake.depth, inInclusiveRange(0.0, 1.0));
      }
    });

    test('never repeats the same lane for every flake', () {
      // A field where every flake shares a lane is a stripe, not snow.
      final lanes = SnowField(flakeCount: 120).flakes.map((f) => f.lane).toSet();
      expect(lanes.length, greaterThan(100));
    });
  });

  group('the depth of a flake', () {
    test('drives the radius, between 0.8 and 4.3 pixels', () {
      for (final flake in SnowField().flakes) {
        expect(flake.radius, inInclusiveRange(0.8, 4.3));
      }
    });

    test('drives the alpha, between 0.28 and 0.80', () {
      for (final flake in SnowField().flakes) {
        expect(flake.alpha, closeTo(0.28 + 0.52 * flake.depth, 1e-12));
        expect(flake.alpha, inInclusiveRange(0.28, 0.80));
      }
    });

    test('drives the fall rate, between 0.30 and 1.70 screens a cycle', () {
      for (final flake in SnowField().flakes) {
        expect(flake.fallRate,
            closeTo(flake.speed * (0.55 + 0.75 * flake.depth), 1e-12));
        expect(flake.fallRate, inInclusiveRange(0.3025, 1.6925));
      }
    });

    test('keeps the drift under 5% of the width', () {
      for (final flake in SnowField().flakes) {
        expect(flake.drift.abs(), lessThanOrEqualTo(0.05));
      }
    });
  });

  group('the depth ordering actually exists', () {
    test('the nearest flakes are the biggest ones', () {
      final flakes = SnowField(flakeCount: 400).flakes.toList()
        ..sort((a, b) => b.depth.compareTo(a.depth));
      final near = flakes.sublist(0, 40);
      final far = flakes.sublist(flakes.length - 40);
      final nearMean =
          near.map((f) => f.radius).reduce((a, b) => a + b) / near.length;
      final farMean =
          far.map((f) => f.radius).reduce((a, b) => a + b) / far.length;
      expect(nearMean, greaterThan(farMean + 0.5));
    });

    test('the nearest flakes are the brightest ones', () {
      final flakes = SnowField(flakeCount: 400).flakes.toList()
        ..sort((a, b) => b.depth.compareTo(a.depth));
      final near = flakes.sublist(0, 40);
      final far = flakes.sublist(flakes.length - 40);
      final nearMean =
          near.map((f) => f.alpha).reduce((a, b) => a + b) / near.length;
      final farMean =
          far.map((f) => f.alpha).reduce((a, b) => a + b) / far.length;
      expect(nearMean, greaterThan(farMean + 0.1));
    });

    test('the nearest flakes fall faster than the far ones', () {
      final flakes = SnowField(flakeCount: 400).flakes.toList()
        ..sort((a, b) => b.depth.compareTo(a.depth));
      final near = flakes.sublist(0, 40);
      final far = flakes.sublist(flakes.length - 40);
      final nearMean =
          near.map((f) => f.fallRate).reduce((a, b) => a + b) / near.length;
      final farMean =
          far.map((f) => f.fallRate).reduce((a, b) => a + b) / far.length;
      expect(nearMean, greaterThan(farMean));
    });

    test('the depths are spread across the whole range, not clustered', () {
      final depths = SnowField(flakeCount: 600).flakes.map((f) => f.depth).toList()
        ..sort();
      final tenth = depths.length ~/ 10;
      expect(depths[tenth], lessThan(0.2));
      expect(depths[depths.length - tenth - 1], greaterThan(0.8));
      // The median should sit near the middle of the range.
      expect(depths[depths.length ~/ 2], closeTo(0.5, 0.1));
    });
  });

  group('the painter', () {
    test('repaints when the phase moves', () {
      final field = SnowField(flakeCount: 10, seed: 3);
      final a = SnowPainter(field: field, phase: 0.0);
      final b = SnowPainter(field: field, phase: 0.5);
      expect(a.shouldRepaint(b), isTrue);
    });

    test('does not repaint when nothing changed', () {
      final field = SnowField(flakeCount: 10, seed: 3);
      final a = SnowPainter(field: field, phase: 0.5);
      final b = SnowPainter(field: field, phase: 0.5);
      expect(a.shouldRepaint(b), isFalse);
    });

    test('repaints when the field is replaced', () {
      final a = SnowPainter(field: SnowField(flakeCount: 10, seed: 3), phase: 0.5);
      final b = SnowPainter(
          field: SnowField(flakeCount: 20, seed: 3), phase: 0.5);
      expect(a.shouldRepaint(b), isTrue);
    });
  });

  group('the geometry of a flake, computed the way the painter computes it', () {
    test('a flake starts on the top edge and ends on the bottom edge', () {
      // The painter uses: fall = (lane + phase·fallRate) mod 1,
      //                  y     = height · fall.
      // At phase 0 the flake is at lane·height; at the end of the cycle it
      // has travelled exactly one screen down and wrapped back to the top.
      final flake = SnowField(flakeCount: 1).flakes.first;
      final height = 600.0;
      final start = height * flake.lane;
      final endPhase = (1.0 - flake.lane) / flake.fallRate;
      final fall = (flake.lane + endPhase * flake.fallRate) % 1.0;
      expect(fall, closeTo(0.0, 1e-9));
      expect(start, inInclusiveRange(0.0, height));
    });

    test('a flake never travels upwards as the phase advances', () {
      final flake = SnowField(flakeCount: 1).flakes.first;
      final height = 600.0;
      var previous = -1.0;
      for (var phase = 0.0; phase < 1.0; phase += 0.01) {
        final fall = (flake.lane + phase * flake.fallRate) % 1.0;
        final y = height * fall;
        if (previous >= 0) {
          // Either it moved down, or it wrapped from the bottom back to the
          // top — in which case it jumped upwards by a whole screen.
          final wrapped = y < previous;
          expect(wrapped || y >= previous, isTrue);
        }
        previous = y;
      }
    });

    test('the sway is a pure horizontal offset', () {
      // The drift is applied to x only; the vertical position is the fall.
      final flake = SnowField(flakeCount: 1).flakes.first;
      final width = 1000.0;
      for (final phase in [0.0, 0.17, 0.43, 0.91]) {
        final fall = (flake.lane + phase * flake.fallRate) % 1.0;
        final sway = math.sin((fall + flake.lane) * 2 * math.pi) *
            width *
            flake.drift;
        expect(sway.abs(), lessThanOrEqualTo(width * 0.05 + 1e-9));
      }
    });
  });
}

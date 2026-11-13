import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/theme/nest_motion.dart';

/// The motion constants are the difference between a launcher that feels
/// physical and one that feels like a web page. Every number in
/// `nest_motion.dart` is therefore pinned here — not just "a spring exists",
/// but the mass, the stiffness, the damping and the damping ratio, because
/// those four numbers are what decide whether the sheet settles or wobbles.
///
/// The analytical solution of a damped oscillator is used as the oracle:
///
///   ζ = c / (2·√(k·m))        the damping ratio
///   ω = √(k/m)                 the natural frequency
///   x(t) = 1 − (1 + ωt)·e^(−ωt)   for ζ = 1 (critically damped)
///
/// so the expectations below are not copies of the implementation — they are
/// the physics, computed independently.
void main() {
  /// The damping ratio of a spring, computed from its own description.
  double zeta(SpringDescription s) =>
      s.damping / (2 * math.sqrt(s.stiffness * s.mass));

  /// The natural frequency of a spring, in radians per second.
  double omega(SpringDescription s) => math.sqrt(s.stiffness / s.mass);

  group('the durations', () {
    test('are the three the design calls for', () {
      expect(kNestFast, const Duration(milliseconds: 200));
      expect(kNestMedium, const Duration(milliseconds: 300));
      expect(kNestSlow, const Duration(milliseconds: 420));
    });

    test('are ordered fast, medium, slow', () {
      expect(kNestFast < kNestMedium, isTrue);
      expect(kNestMedium < kNestSlow, isTrue);
    });
  });

  group('the curves', () {
    test('are the three Flutter curves they are documented as', () {
      expect(kNestEase, Curves.easeInOutCubicEmphasized);
      expect(kNestDecelerate, Curves.easeOutCubic);
      expect(kNestAccelerate, Curves.easeInCubic);
    });

    test('the ease curve starts and ends flat, so nothing snaps', () {
      expect(kNestEase.transform(0.0), 0.0);
      expect(kNestEase.transform(1.0), 1.0);
      // The first tenth of the journey covers less than a fifth of the
      // distance — a curve that starts too fast reads as a jump.
      expect(kNestEase.transform(0.1), lessThan(0.2));
      expect(kNestEase.transform(0.9), greaterThan(0.8));
    });

    test('the decelerate curve never goes backwards', () {
      var previous = 0.0;
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        final value = kNestDecelerate.transform(t);
        expect(value, greaterThanOrEqualTo(previous));
        previous = value;
      }
    });

    test('the accelerate curve never goes backwards either', () {
      var previous = 0.0;
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        final value = kNestAccelerate.transform(t);
        expect(value, greaterThanOrEqualTo(previous));
        previous = value;
      }
    });
  });

  group('the springs', () {
    test('all have a mass of one', () {
      expect(kNestPageSpring.mass, 1.0);
      expect(kNestSheetSpring.mass, 1.0);
      expect(kNestSnapSpring.mass, 1.0);
      expect(kNestSheetCloseSpring.mass, 1.0);
    });

    test('the page spring is critically damped', () {
      // ζ = 41 / (2·√420) = 1.0003
      expect(zeta(kNestPageSpring), closeTo(1.0, 0.001));
    });

    test('the sheet spring is critically damped', () {
      // ζ = 40 / (2·√400) = 1.0000
      expect(zeta(kNestSheetSpring), closeTo(1.0, 0.0005));
    });

    test('the snap spring is slightly under-damped on purpose', () {
      // ζ = 45 / (2·√700) = 0.8505 — the one place a little overshoot is
      // wanted, because a sheet that is flicked should bounce a touch.
      expect(zeta(kNestSnapSpring), closeTo(0.8505, 0.001));
    });

    test('the sheet-close spring is critically damped or a hair over', () {
      // ζ = 46 / (2·√520) = 1.0086
      expect(zeta(kNestSheetCloseSpring), closeTo(1.0086, 0.001));
    });

    test('the page spring is stiffer than the sheet spring', () {
      expect(kNestPageSpring.stiffness, greaterThan(kNestSheetSpring.stiffness));
    });

    test('the snap spring is the stiffest of them', () {
      expect(kNestSnapSpring.stiffness, greaterThan(kNestPageSpring.stiffness));
    });
  });

  group('nestSpring', () {
    test('starts at the value it was given', () {
      final sim = nestSpring(kNestPageSpring, 0.3, 1.0, 0);
      expect(sim.x(0.0), closeTo(0.3, 1e-12));
    });

    test('ends at the target', () {
      final sim = nestSpring(kNestPageSpring, 0.0, 1.0, 0);
      expect(sim.x(1.0), closeTo(1.0, 1e-4));
    });

    test('a critically damped spring never overshoots', () {
      // This is the whole reason the carousel uses ζ = 1: an overshoot on a
      // 0..1 AnimationController is clipped flat, and a clipped overshoot
      // reads as a stutter.
      for (final spring in [kNestPageSpring, kNestSheetSpring]) {
        final sim = nestSpring(spring, 0.0, 1.0, 0);
        var highest = 0.0;
        for (var t = 0.0; t <= 2.0; t += 0.002) {
          highest = math.max(highest, sim.x(t));
        }
        expect(highest, lessThanOrEqualTo(1.0 + 1e-9),
            reason: '${spring.stiffness}/${spring.damping} overshot');
      }
    });

    test('the snap spring does overshoot, but by less than two percent', () {
      final sim = nestSpring(kNestSnapSpring, 0.0, 1.0, 0);
      var highest = 0.0;
      for (var t = 0.0; t <= 2.0; t += 0.001) {
        highest = math.max(highest, sim.x(t));
      }
      expect(highest, greaterThan(1.004));
      expect(highest, lessThan(1.02));
    });

    test('an exactly critically damped spring matches the analytic solution '
        'of a critically damped oscillator', () {
      // x(t) = 1 − (1 + ωt)·e^(−ωt)
      //
      // The sheet spring is the one that is exactly critically damped:
      // ζ = 40 / (2·√400) = 1.0 to the last bit, so Flutter uses the
      // critically-damped branch of its solver and the closed form applies.
      const exact = SpringDescription(mass: 1, stiffness: 400, damping: 40);
      final sim = nestSpring(exact, 0.0, 1.0, 0);
      final w = omega(exact);
      for (final t in [0.05, 0.1, 0.25, 0.5]) {
        final expected = 1 - (1 + w * t) * math.exp(-w * t);
        expect(sim.x(t), closeTo(expected, 1e-9), reason: 'at t=$t');
      }
    });

    test('the page spring, which is a hair overdamped, tracks the critically '
        'damped curve to within a thousandth', () {
      // The page spring is 420/41: ζ = 41 / (2·√420) = 1.0003, so Flutter
      // solves it as an overdamped system rather than the closed form. The
      // difference is real but tiny — it converges a hair sooner — and the
      // test pins it so a change to the damping ratio cannot go unnoticed.
      final sim = nestSpring(kNestPageSpring, 0.0, 1.0, 0);
      final w = omega(kNestPageSpring);
      for (final t in [0.05, 0.1, 0.25, 0.5]) {
        final expected = 1 - (1 + w * t) * math.exp(-w * t);
        expect(sim.x(t), closeTo(expected, 1e-3), reason: 'at t=$t');
      }
    });

    test('the page spring is more than 99.9% of the way there after half a '
        'second', () {
      final sim = nestSpring(kNestPageSpring, 0.0, 1.0, 0);
      expect(sim.x(0.5), greaterThan(0.999));
    });

    test('a fast fling still converges instead of ringing forever', () {
      final sim = nestSpring(kNestPageSpring, 0.0, 1.0, 2400);
      expect(sim.isDone(2.0), isTrue);
    });

    test('the simulation reports itself finished once it has settled', () {
      final sim = nestSpring(kNestPageSpring, 0.0, 1.0, 0);
      expect(sim.isDone(0.0), isFalse);
      expect(sim.isDone(1.0), isTrue);
    });
  });

  group('clampNestVelocity', () {
    test('leaves a reasonable velocity alone', () {
      expect(clampNestVelocity(0), 0);
      expect(clampNestVelocity(100), 100);
      expect(clampNestVelocity(-100), -100);
      expect(clampNestVelocity(2400), 2400);
    });

    test('clamps a fling to the maximum', () {
      expect(clampNestVelocity(3000), 2400);
      expect(clampNestVelocity(-3000), -2400);
      expect(clampNestVelocity(1e9), 2400);
      expect(clampNestVelocity(-1e9), -2400);
    });

    test('honours a custom maximum', () {
      expect(clampNestVelocity(500, max: 300), 300);
      expect(clampNestVelocity(-500, max: 300), -300);
      expect(clampNestVelocity(200, max: 300), 200);
    });

    test('turns a NaN into zero rather than letting it through', () {
      expect(clampNestVelocity(double.nan), 0);
      expect(clampNestVelocity(double.nan).isFinite, isTrue);
    });

    test('clamps an infinity rather than propagating it', () {
      expect(clampNestVelocity(double.infinity), 2400);
      expect(clampNestVelocity(double.negativeInfinity), -2400);
    });
  });
}

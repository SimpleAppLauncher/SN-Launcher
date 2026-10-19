/// Motion.
///
/// Two ideas, deliberately kept apart:
///
///  * **Eased curves** for transitions nobody is touching. Material 3's own
///    "emphasised" token, which is the standard this app already lives in.
///  * **Springs** for the surfaces a finger is on — the page carousel and the
///    launcher sheet. A spring carries the velocity it was released with and
///    starts from wherever it happens to be when it is next touched, so a
///    second swipe during a transition continues the motion instead of
///    restarting it.
///
/// The second point is the whole reason for springs. An eased curve has a
/// fixed duration and a fixed shape: interrupt one halfway and the remainder
/// is played from the beginning at the beginning's speed, which reads as the
/// interface hesitating. A spring has no fixed duration — it settles when it
/// settles — so interruption is free rather than a special case.
///
/// What this deliberately does *not* do is import an identity. A spring is
/// physics, not a skin; it is how this app makes a swipe feel like a swipe
/// without pretending to be something it is not.
library;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

// ── Durations ───────────────────────────────────────────────────────────────
//
// Only for the eased path. The springs derive their own.

const Duration kNestFast = Duration(milliseconds: 200);
const Duration kNestMedium = Duration(milliseconds: 300);
const Duration kNestSlow = Duration(milliseconds: 420);

/// Material 3's emphasised easing — the standard curve for a transition that
/// draws attention to where the user just sent it.
///
/// Replaces the generic `Cubic(0.4, 0, 0.2, 1)`, which is a leftover from
/// Material 1 and has been superseded by the token below.
const Curve kNestEase = Curves.easeInOutCubicEmphasized;

/// Entering: decelerate, so the thing settles rather than stopping dead.
const Curve kNestDecelerate = Curves.easeOutCubic;

/// Leaving: accelerate, so the thing leaves.
const Curve kNestAccelerate = Curves.easeInCubic;

// ── Springs ─────────────────────────────────────────────────────────────────
//
// A `SpringDescription` is mass / stiffness / damping. What matters is the
// damping ratio, ζ = damping / (2·√(stiffness·mass)):
//
//   ζ < 1  overshoots and comes back
//   ζ = 1  critical — fastest approach with no overshoot
//   ζ > 1  sluggish, no overshoot
//
// The ratios below are computed, not guessed, and each one exists because of
// what the surface does.

/// The page carousel — critically damped (ζ = 1.0), no overshoot.
///
/// An overshooting page transition travels *past* the target page, which shows
/// a sliver of the page you did not ask for and then springs back. On a
/// full-bleed carousel that reads as a wobble, not as responsiveness. The
/// responsiveness here comes from carrying the finger's velocity, not from
/// going further than the user meant.
///
///   ζ = 41 / (2·√420) = 41 / 40.99 ≈ 1.00
const SpringDescription kNestPageSpring =
    SpringDescription(mass: 1, stiffness: 420, damping: 41);

/// The launcher sheet — critically damped (ζ = 1.0), no overshoot.
///
/// A sheet is the obvious place to want overshoot: it is a free-floating
/// surface, and a little bounce is what sells something as having mass. This
/// one cannot have it. `_sheetAnim` is an ordinary `AnimationController`, so
/// its value is clamped to 0..1, and an under-damped spring's overshoot gets
/// clipped flat at the top — the sheet would surge to fully open and *stop
/// dead*, which looks like a stutter rather than a bounce.
///
/// So it is critically damped and approaches the stop smoothly. The velocity
/// and interruption behaviour, which is most of the point, is unaffected:
/// only the overshoot is given up.
///
///   ζ = 40 / (2·√400) = 40 / 40.00 = 1.00
const SpringDescription kNestSheetSpring =
    SpringDescription(mass: 1, stiffness: 400, damping: 40);

/// Taps and confirmations — ζ ≈ 0.85, stiffer, settles quickly.
///
///   ζ = 45 / (2·√700) = 45 / 52.92 ≈ 0.85
const SpringDescription kNestSnapSpring =
    SpringDescription(mass: 1, stiffness: 700, damping: 45);

/// The spring for [dismissing] the sheet — stiffer than [kNestSheetSpring], so a
/// dismissal closes decisively instead of trailing off.
///
///   ζ = 46 / (2·√520) = 46 / 45.61 ≈ 1.01
const SpringDescription kNestSheetCloseSpring =
    SpringDescription(mass: 1, stiffness: 520, damping: 46);

/// Builds a spring from wherever [value] currently is to [target], carrying
/// [velocity] (in units per second) into the simulation.
///
/// Starting from the live value rather than a remembered one is what makes an
/// interrupted transition continue instead of stutter.
Simulation nestSpring(
  SpringDescription spring,
  double value,
  double target,
  double velocity,
) =>
    SpringSimulation(spring, value, target, velocity);

/// Clamps a gesture velocity into a range the springs behave well in.
///
/// Velocity arrives from a real finger and is unbounded — a hard flick can
/// read several thousand px/s. Fed straight into a spring that produces a
/// target overshoot large enough to be visible on a critically damped
/// carousel, which is exactly the wobble [kNestPageSpring] exists to avoid.
/// The cap is high enough that an ordinary flick is unaffected.
double clampNestVelocity(double velocity, {double max = 2400}) =>
    velocity.isNaN ? 0 : velocity.clamp(-max, max).toDouble();

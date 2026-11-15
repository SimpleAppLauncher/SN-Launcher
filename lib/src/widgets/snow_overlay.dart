import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Falling snow.
///
/// One painter, not one widget per flake. A hundred and twenty small
/// `CustomPaint` widgets would each be their own layer on a weak GPU, and the
/// whole point of the launcher's ambient background is that it is a single
/// paint pass (see `ambient_background.dart`).
///
/// The flakes are laid out from a seeded generator, so the arrangement is the
/// same on every device and — more importantly — the same on every frame when
/// [animate] is false. A test that pumps two frames and compares the painted
/// output has to get the same answer both times, or the assertion is noise.
///
/// ## Depth
///
/// A field of identical white dots does not read as snow, it reads as dust on
/// the lens. Real snow has depth: the flakes nearest the window are larger,
/// brighter and faster, and the ones far away are small, dim and slow. That
/// is what [SnowFlake.depth] carries, and it costs three multiplications and
/// no extra drawing.
class SnowOverlay extends StatefulWidget {
  const SnowOverlay({super.key, this.animate = true, this.flakeCount = 120});

  /// When false the snow is a still picture of snow: the phase never advances.
  ///
  /// The shell already has a decoration-animation switch for tests, and this
  /// is the second consumer of it.
  final bool animate;

  /// How many flakes to draw. Fewer on a small screen: a phone-sized window
  /// with a hundred and twenty flakes reads as a snowstorm, not as snow.
  final int flakeCount;

  @override
  State<SnowOverlay> createState() => _SnowOverlayState();
}

class _SnowOverlayState extends State<SnowOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  /// The animation's position in time, in cycles, and never wrapping.
  ///
  /// The controller's own value runs 0 → 1 and starts again. That is fine for
  /// an animation that is supposed to loop, and terrible for this one: each
  /// flake falls a *fraction of the screen* per cycle, so restarting the
  /// phase moved every flake at once. In the default field, 97 of the 120
  /// flakes jumped, one of them by 94% of the screen height, every twelve
  /// seconds — the field blinked rather than fell.
  ///
  /// The field's centre of mass barely moved, because the flakes that leapt
  /// upwards and the flakes that dropped a little cancelled each other out.
  /// That is why it went unnoticed for so long.
  ///
  /// So the phase is accumulated instead: it only ever goes forwards, and the
  /// only discontinuity left is each flake's own recycle at the bottom of the
  /// screen, which is staggered and is what snow looks like.
  double _phase = 0;

  /// The controller's value at the last tick, so the next one can be turned
  /// into an advance rather than a position.
  double _lastValue = 0;

  /// The field, built once.
  ///
  /// It used to be built inside the painter's builder, which runs on every
  /// frame — that is a hundred and twenty random numbers a frame on a device
  /// that is meant to sit on a wall. The arrangement is deterministic, so
  /// building it once changes nothing that is drawn.
  late SnowField _field = SnowField(flakeCount: widget.flakeCount);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_accumulate);
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(SnowOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flakeCount != oldWidget.flakeCount) {
      _field = SnowField(flakeCount: widget.flakeCount);
    }
    if (widget.animate && !_controller.isAnimating) {
      // repeat() restarts the controller from zero, so the next tick is an
      // advance from zero and not a jump from wherever it was left.
      _lastValue = 0;
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  /// Turns the controller's looping value into a running total.
  void _accumulate() {
    final value = _controller.value;
    if (!_controller.isAnimating) {
      _lastValue = value;
      return;
    }
    var advance = value - _lastValue;
    // The controller wrapped: it ran out at 1 and started again at 0. The
    // advance across that boundary is the part that is left, not a negative
    // one.
    if (advance < 0) advance += 1.0;
    _phase += advance;
    _lastValue = value;
  }

  @override
  void dispose() {
    _controller.removeListener(_accumulate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: SnowPainter(
            field: _field,
            phase: widget.animate ? _phase : 0.0,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// One flake's fixed properties. Everything that does not change between
/// frames lives here, so the painter's per-frame work is arithmetic only.
class SnowFlake {
  const SnowFlake({
    required this.lane,
    required this.speed,
    required this.drift,
    required this.radius,
    required this.depth,
  });

  /// Where across the screen this flake sits, 0..1.
  final double lane;

  /// How fast it falls, as a fraction of the screen height per cycle.
  final double speed;

  /// How far it sways sideways, as a fraction of the screen width.
  final double drift;

  /// Its radius in logical pixels.
  final double radius;

  /// 0 = far away, 1 = right in front of the viewer.
  final double depth;

  /// Its opacity, 0..1. Near flakes are brighter.
  double get alpha => 0.28 + 0.52 * depth;

  /// Its fall speed. Near flakes fall faster, which is what parallax is.
  double get fallRate => speed * (0.55 + 0.75 * depth);
}

/// The arrangement of flakes: where they are, how big, how deep.
///
/// Public and deterministic so it can be asserted on directly. The seed is
/// fixed, so two [SnowField]s with the same flake count are identical — which
/// is what makes "the same picture twice" a meaningful test.
class SnowField {
  SnowField({this.flakeCount = 120, this.seed = 20261112})
      : flakes = _build(flakeCount, seed);

  final int flakeCount;
  final int seed;
  final List<SnowFlake> flakes;

  /// Lays the field out from one seeded generator, consumed in order.
  ///
  /// The size and the speed of a flake are derived from its depth rather than
  /// drawn independently, so a distant flake really is small and slow and a
  /// near one really is big and fast. Drawing all five values independently
  /// would scatter them evenly, which looks mechanical.
  static List<SnowFlake> _build(int count, int seed) {
    final random = math.Random(seed);
    return List<SnowFlake>.generate(count, (i) {
      final lane = random.nextDouble();
      final depth = random.nextDouble();
      final radius = 0.8 + depth * 2.6 + random.nextDouble() * 0.9;
      final speed = 0.55 + random.nextDouble() * 0.75;
      final drift = (random.nextDouble() - 0.5) * (0.03 + depth * 0.07);
      return SnowFlake(
        lane: lane,
        speed: speed,
        drift: drift,
        radius: radius,
        depth: depth,
      );
    }, growable: false);
  }
}

/// Paints the field.
class SnowPainter extends CustomPainter {
  SnowPainter({required this.field, required this.phase});

  /// 0..1 through one fall cycle.
  final double phase;

  final SnowField field;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // A soft white, not pure white — a pure-white flake on a dark photo is a
    // hard dot, and there are a hundred and twenty of them.
    final paint = Paint();

    for (final flake in field.flakes) {
      // The fall is a wrap: a flake that leaves the bottom reappears at the
      // top, so the field never empties out.
      //
      // `fall` is the fraction of the journey completed, so it grows with
      // time — and y grows downward. `y = height * fall` therefore puts a flake
      // at the top when it has not fallen yet and at the bottom when it has,
      // and the wrap sends it back to the top. The inverted form,
      // `height * (1 - fall)`, is the same field travelling upwards, and it
      // looks exactly as convincing while it is wrong.
      final fall = (flake.lane + phase * flake.fallRate) % 1.0;
      final y = size.height * fall;
      // The sway is wider for near flakes, because they are closer to the
      // viewer and the wind moves them more.
      final sway =
          math.sin((fall + flake.lane) * math.pi * 2) * size.width * flake.drift;
      final x = size.width * flake.lane + sway;

      if (x < -flake.radius || x > size.width + flake.radius) continue;

      paint.color = const Color(0xFFEAF2FF).withValues(alpha: flake.alpha);
      canvas.drawCircle(Offset(x, y), flake.radius, paint);
    }
  }

  @override
  bool shouldRepaint(SnowPainter old) =>
      old.phase != phase || old.field.flakeCount != field.flakeCount;
}

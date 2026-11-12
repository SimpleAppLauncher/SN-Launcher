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

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(SnowOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _SnowPainter(
            phase: widget.animate ? _controller.value : 0.0,
            flakeCount: widget.flakeCount,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SnowPainter extends CustomPainter {
  _SnowPainter({required this.phase, required this.flakeCount});

  /// 0..1 through one fall cycle.
  final double phase;

  final int flakeCount;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // A soft white, not pure white — a pure-white flake on a dark photo is a
    // hard dot, and there are a hundred and twenty of them.
    final paint = Paint()..color = const Color(0xFFEAF2FF).withValues(alpha: 0.75);

    final random = math.Random(20261112);
    for (var i = 0; i < flakeCount; i++) {
      // Each flake gets its own lane across the screen, its own fall speed
      // and its own sideways drift, so the field does not move as one sheet.
      final lane = random.nextDouble();
      final speed = 0.6 + random.nextDouble() * 0.8;
      final drift = (random.nextDouble() - 0.5) * 0.06;
      final radius = 1.0 + random.nextDouble() * 2.2;

      // The fall is a wrap: a flake that leaves the bottom reappears at the
      // top, so the field never empties out.
      final fall = (lane + phase * speed) % 1.0;
      final y = size.height * (1.0 - fall);
      final sway = math.sin((fall + lane) * math.pi * 2) * size.width * drift;
      final x = size.width * lane + sway;

      if (x < -radius || x > size.width + radius) continue;

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SnowPainter old) =>
      old.phase != phase || old.flakeCount != flakeCount;
}

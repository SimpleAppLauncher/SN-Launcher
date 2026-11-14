import 'package:flutter/material.dart';

import '../models/nest_action.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_icons.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';
import '../services/timer_service.dart';

/// The voice command button.
///
/// A button, and not a tap anywhere on the screen. The shell used to start
/// listening on any tap at all, which meant every touch on a launcher was
/// also a request to open the microphone — on a device that is meant to sit
/// on a wall and be touched by everyone in the room.
///
/// The button says what it is: a microphone, pressed. When there is no
/// microphone to press — no permission, no recogniser — it is greyed out
/// rather than hidden, because a launcher that quietly drops a control is
/// worse than one that shows it and admits it cannot work.
class MicButton extends StatelessWidget {
  const MicButton({
    super.key,
    required this.metrics,
    required this.type,
    required this.palette,
    required this.activity,
    required this.onPressed,
    this.available = true,
  });

  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;

  /// What the assistant is doing, so the button can look like it.
  final AssistActivity activity;

  /// Called when the button is pressed. Null disables it.
  final VoidCallback? onPressed;

  /// Whether there is anything to listen with.
  final bool available;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final listening = activity == AssistActivity.listening;
    final colour = available
        ? palette.onSurface.withValues(alpha: listening ? 0.95 : 0.55)
        : palette.onSurface.withValues(alpha: 0.22);

    return Semantics(
      button: true,
      label: 'Voice command',
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: m.px(36),
          height: m.px(36),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.surface.withValues(alpha: listening ? 0.45 : 0.22),
          ),
          child: Icon(
            listening ? NestIcons.Stop : NestIcons.Mic,
            size: m.px(20),
            color: colour,
          ),
        ),
      ),
    );
  }
}

/// The countdown the launcher shows when a timer is running.
///
/// It is here, on screen, because a timer the user cannot see is not a timer.
/// The old behaviour wrote a label into a native field that nothing ever
/// read, and told the user the timer was set.
class TimerChip extends StatelessWidget {
  const TimerChip({
    super.key,
    required this.metrics,
    required this.type,
    required this.palette,
    required this.timer,
    this.onTap,
  });

  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;

  /// The countdown being shown.
  ///
  /// The chip listens to the service itself, so the seconds tick without the
  /// launcher rebuilding around it.
  final TimerService timer;

  /// Called when the chip is tapped. Null when it is not interactive.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: timer,
      builder: (context, _) {
        final m = metrics;
        final finished = timer.finished;
        final labelText = finished ? 'Timer finished' : timer.label;
        final colour = finished
            ? palette.onSurfaceStrong
            : palette.onSurface.withValues(alpha: 0.82);

        return Semantics(
          label: 'Timer, $labelText',
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: m.px(14),
                vertical: m.px(6),
              ),
              decoration: BoxDecoration(
                color: palette.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(m.px(999)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    finished ? NestIcons.AlarmOn : NestIcons.AccessTime,
                    size: m.px(16),
                    color: colour,
                  ),
                  SizedBox(width: m.px(8)),
                  Text(
                    labelText,
                    style: type.caption(color: colour),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

/// A repeating callback that can be stopped.
///
/// An interface rather than a bare function so the service can stop what it
/// started. A periodic timer that nothing can cancel is a leak, and a
/// launcher that is meant to sit on a wall for months cannot afford one.
abstract class Ticker {
  void start(Duration interval, void Function() onTick);

  void stop();
}

/// The real ticker: a periodic timer.
class _SystemTicker implements Ticker {
  Timer? _timer;

  @override
  void start(Duration interval, void Function() onTick) {
    _timer = Timer.periodic(interval, (_) => onTick());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// A countdown the user asked for, and can see.
///
/// This exists because the assistant used to answer "setting a timer for five
/// minutes" by calling a native method that stored a label nobody ever read.
/// The launcher said the timer was set and nothing happened, which is the one
/// thing this project is not allowed to do.
///
/// The countdown is computed from the clock rather than from how many times
/// something has ticked, so it is right even on a screen that only repaints
/// once a minute.
class TimerService extends ChangeNotifier {
  TimerService({
    DateTime Function()? now,
    Ticker? ticker,
  })  : _now = now ?? DateTime.now,
        _ticker = ticker ?? _SystemTicker();

  final DateTime Function() _now;
  final Ticker _ticker;

  /// How often the countdown refreshes itself.
  ///
  /// One second, because a countdown that updates every ten seconds is not a
  /// countdown. The ticker only runs while a timer is actually running, so
  /// an idle launcher pays nothing for it.
  static const Duration _tick = Duration(seconds: 1);

  DateTime? _deadline;
  bool _finished = false;

  /// Whether a countdown is running right now.
  bool get running => _deadline != null && !_finished;

  /// Whether the countdown reached zero and is waiting to be dismissed.
  bool get finished => _finished;

  /// When the countdown ends, or null when there is none.
  DateTime? get deadline => _deadline;

  /// How long is left. Never negative.
  Duration get remaining {
    final deadline = _deadline;
    if (deadline == null) return Duration.zero;
    final left = deadline.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  /// The countdown as it is shown: `4:18`, or `1:02:00` past an hour.
  String get label {
    if (_deadline == null) return '';
    final left = remaining;
    final hours = left.inHours;
    final minutes = left.inMinutes.remainder(60);
    final seconds = left.inSeconds.remainder(60);
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
    }
    return '$minutes:$ss';
  }

  /// Start a countdown, replacing any that is already running.
  void start(Duration duration) {
    _ticker.stop();
    _deadline = _now().add(duration);
    _finished = false;
    _ticker.start(_tick, _onTick);
    notifyListeners();
  }

  /// Stop the countdown and take it off the screen.
  void cancel() {
    _ticker.stop();
    _deadline = null;
    _finished = false;
    notifyListeners();
  }

  /// Dismiss a countdown that has already reached zero.
  void clear() {
    if (!_finished) return;
    _finished = false;
    _deadline = null;
    notifyListeners();
  }

  void _onTick() {
    if (_deadline == null) return;
    if (!_now().isBefore(_deadline!)) {
      _ticker.stop();
      _finished = true;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.stop();
    super.dispose();
  }
}

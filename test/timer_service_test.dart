import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/timer_service.dart';

/// A ticker the test drives by hand, so a countdown can be stepped through
/// without waiting a minute for it.
class _FakeTicker implements Ticker {
  void Function()? _onTick;
  bool running = false;

  @override
  void start(Duration interval, void Function() onTick) {
    _onTick = onTick;
    running = true;
  }

  @override
  void stop() {
    _onTick = null;
    running = false;
  }

  void tick() => _onTick?.call();
}

void main() {
  late _FakeTicker ticker;
  late DateTime now;

  setUp(() {
    ticker = _FakeTicker();
    now = DateTime(2026, 11, 14, 9, 30);
  });

  TimerService service() => TimerService(
        now: () => now,
        ticker: ticker,
      );

  test('a timer that was never started is not running', () {
    final timer = service();

    expect(timer.running, isFalse);
    expect(timer.remaining, Duration.zero);
    expect(timer.label, isEmpty);
  });

  test('a started timer counts down', () {
    final timer = service()..start(const Duration(minutes: 5));

    expect(timer.running, isTrue);
    expect(timer.remaining, const Duration(minutes: 5));
    expect(timer.label, '5:00');
  });

  test('the countdown follows the clock', () {
    final timer = service()..start(const Duration(minutes: 5));

    now = now.add(const Duration(seconds: 42));
    ticker.tick();

    expect(timer.remaining, const Duration(minutes: 4, seconds: 18));
    expect(timer.label, '4:18');
  });

  test('a long timer reads in hours', () {
    final timer = service()..start(const Duration(hours: 1, minutes: 2));

    expect(timer.label, '1:02:00');
  });

  test('the timer stops at zero and says it finished', () {
    final timer = service()..start(const Duration(seconds: 2));

    now = now.add(const Duration(seconds: 2));
    ticker.tick();

    expect(timer.running, isFalse);
    expect(timer.finished, isTrue);
    expect(ticker.running, isFalse);
  });

  test('a finished timer keeps its last label until it is cleared', () {
    final timer = service()..start(const Duration(seconds: 2));

    now = now.add(const Duration(seconds: 2));
    ticker.tick();

    expect(timer.label, '0:00');
    timer.clear();
    expect(timer.label, isEmpty);
    expect(timer.finished, isFalse);
  });

  test('cancelling stops the timer', () {
    final timer = service()..start(const Duration(minutes: 5));

    timer.cancel();

    expect(timer.running, isFalse);
    expect(timer.finished, isFalse);
    expect(ticker.running, isFalse);
  });

  test('starting a second timer replaces the first', () {
    final timer = service()..start(const Duration(minutes: 5));

    now = now.add(const Duration(seconds: 30));
    timer.start(const Duration(minutes: 1));

    expect(timer.remaining, const Duration(minutes: 1));
  });

  test('a timer that never gets ticked still reads the right time', () {
    // The countdown is computed from the clock, not from how many times
    // something has ticked. A launcher that only repaints on the minute must
    // not show a stale timer.
    final timer = service()..start(const Duration(minutes: 5));

    now = now.add(const Duration(minutes: 2));

    expect(timer.remaining, const Duration(minutes: 3));
    expect(timer.label, '3:00');
  });
}

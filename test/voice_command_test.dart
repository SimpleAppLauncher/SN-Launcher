import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/assistant_service.dart';
import 'package:sn_launcher/src/services/platform_bridge.dart';
import 'package:sn_launcher/src/services/timer_service.dart';

/// A platform that remembers what it was told to do.
class _FakePlatform extends PlatformBridge {
  double volume = 0.5;
  double brightness = 0.5;
  final List<String> mediaKeys = [];

  @override
  Future<double?> getVolumeFraction() async => volume;

  @override
  Future<int?> setVolume(double value) async {
    volume = value.clamp(0.0, 1.0);
    return (volume * 100).round();
  }

  @override
  Future<double?> getBrightness() async => brightness;

  @override
  Future<double?> setBrightness(double value) async {
    brightness = value.clamp(0.0, 1.0);
    return brightness;
  }

  @override
  Future<bool> sendMediaKey(String action) async {
    mediaKeys.add(action);
    return true;
  }
}

/// A ticker the test drives by hand.
class _FakeTicker implements Ticker {
  void Function()? _onTick;

  @override
  void start(Duration interval, void Function() onTick) => _onTick = onTick;

  @override
  void stop() => _onTick = null;

  void tick() => _onTick?.call();
}

void main() {
  late _FakePlatform platform;
  late TimerService timer;
  late DateTime now;
  late AssistantService assistant;

  setUp(() {
    platform = _FakePlatform();
    now = DateTime(2026, 11, 14, 9, 30);
    timer = TimerService(now: () => now, ticker: _FakeTicker());
    assistant = AssistantService(
      platform: platform,
      timer: timer,
    );
    // Speech is off in these tests: the point is what the launcher *did*, and
    // a text-to-speech engine in a unit test proves nothing about that.
    assistant.configure(enabled: true, speechEnabled: false);
  });

  tearDown(() {
    assistant.dispose();
    timer.dispose();
  });

  group('what it understands', () {
    test('the time is answered from the device clock', () async {
      final intent = await assistant.handleTyped('what time is it');

      expect(intent.kind, AssistKind.local);
      expect(intent.title, 'The time');
    });

    test('the date is answered from the device clock', () async {
      final intent = await assistant.handleTyped("what's the date");

      expect(intent.kind, AssistKind.local);
      expect(intent.title, 'The date');
    });

    test('a request the launcher cannot do is not pretended to work', () async {
      final intent = await assistant.handleTyped('make me a sandwich');

      expect(intent.kind, AssistKind.failed);
      expect(intent.reply, isNotEmpty);
    });

    test('nothing heard is not a command', () async {
      final intent = await assistant.handleTyped('   ');

      expect(intent.kind, AssistKind.failed);
    });
  });

  group('what it does', () {
    test('turning the volume up turns the volume up', () async {
      final intent = await assistant.handleTyped('turn up the volume');

      expect(intent.kind, AssistKind.local);
      expect(platform.volume, greaterThan(0.5));
    });

    test('muting sets the volume to nothing', () async {
      await assistant.handleTyped('mute');

      expect(platform.volume, 0);
    });

    test('dimming the screen dims it', () async {
      await assistant.handleTyped('make it dimmer');

      expect(platform.brightness, lessThan(0.5));
    });

    test('playing music raises the media key', () async {
      await assistant.handleTyped('play some music');

      expect(platform.mediaKeys, contains('play'));
    });

    test('pausing raises the pause key', () async {
      await assistant.handleTyped('pause');

      expect(platform.mediaKeys, contains('pause'));
    });
  });

  group('the timer', () {
    test('a timer is a countdown the user can see', () async {
      final intent = await assistant.handleTyped('set a timer for 5 minutes');

      expect(intent.kind, AssistKind.local);
      expect(timer.running, isTrue);
      expect(timer.remaining, const Duration(minutes: 5));
      expect(timer.label, '5:00');
    });

    test('a timer in seconds is in seconds', () async {
      await assistant.handleTyped('set a timer for 30 seconds');

      expect(timer.remaining, const Duration(seconds: 30));
    });

    test('a timer in hours is in hours', () async {
      await assistant.handleTyped('remind me in 2 hours');

      expect(timer.remaining, const Duration(hours: 2));
    });

    test('a timer that cannot be shown is not claimed to be set', () async {
      // Without a countdown on screen, saying "setting a timer" would be a
      // promise the launcher cannot keep.
      final bare = AssistantService(platform: platform);
      addTearDown(bare.dispose);
      bare.configure(enabled: true, speechEnabled: false);

      final intent = await bare.handleTyped('set a timer for 5 minutes');

      expect(intent.kind, AssistKind.failed);
    });
  });
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/nest_action.dart';
import 'platform_bridge.dart';

/// Result of a launch attempt, surfaced in the UI as a small toast.
enum LaunchOutcome { launched, notInstalled, failed }

/// Opens real applications from launcher icons.
///
/// One code path covers every target:
///  * **Android** — a deep link (`spotify:`) or an https fallback, opened with
///    [url_launcher]'s platform channel. Nothing heavier is needed, which keeps
///    the APK small and cold-start cheap on 1 GB tablets.
///  * **Linux** — try the native binary first (`spotify`), fall back to
///    `xdg-open`.
///  * **macOS** — `open -a <app>` when we know the bundle id, else `open <url>`.
class ActionLauncher {
  const ActionLauncher();

  /// Tizen's url_launcher implementation only supports platformDefault.
  ///
  /// Tizen reports itself as Linux to Dart, so this also selects the right
  /// mode on the Linux desktop, where url_launcher_linux has the same
  /// restriction. Android and macOS keep externalApplication.
  static LaunchMode get _mode => !kIsWeb && Platform.isLinux
      ? LaunchMode.platformDefault
      : LaunchMode.externalApplication;

  /// Custom scheme → macOS bundle identifier, so tapping "Spotify" on a Mac
  /// opens the real app instead of a browser error page.
  static const Map<String, String> _macBundleIds = {
    'spotify:': 'com.spotify.client',
    'https://music.youtube.com': 'com.google.ytmusic',
    'https://www.youtube.com': 'com.google.ytmusic',
  };

  Future<LaunchOutcome> launch(NestAction action) async {
    // Installed apps are launched by package name. A deep link is not a
    // substitute: it opens a browser or a chooser, not necessarily the app
    // whose icon the user just touched.
    final packageName = action.intentPackage;
    if (action.isInstalledApp && packageName != null) {
      final opened = await const PlatformBridge().launchApp(packageName);
      if (opened) return LaunchOutcome.launched;
      // Fall through only if the package has a deep link configured. A raw
      // installed app has none, so this returns notInstalled below.
    }

    final url = action.intentUrl;
    if (url != null) {
      try {
        if (await canLaunchUrl(Uri.parse(url))) {
          if (await launchUrl(
            Uri.parse(url),
            mode: _mode,
          )) {
            return LaunchOutcome.launched;
          }
        }
      } catch (e) {
        debugPrint('ActionLauncher: primary launch failed: $e');
      }
    }

    final exec = action.linuxExec;
    if (exec != null && !kIsWeb && Platform.isLinux) {
      try {
        final r = await Process.run('which', [exec]);
        if (r.exitCode == 0) {
          await Process.start(exec, const []);
          return LaunchOutcome.launched;
        }
      } catch (_) {/* fall through */}
      try {
        final r = await Process.run('xdg-open', [exec]);
        if (r.exitCode == 0) return LaunchOutcome.launched;
      } catch (_) {/* fall through */}
    }

    // macOS bundle id route.
    if (!kIsWeb && Platform.isMacOS && url != null) {
      final bundle = _macBundleIds[url];
      if (bundle != null) {
        try {
          final r = await Process.run('open', ['-b', bundle]);
          if (r.exitCode == 0) return LaunchOutcome.launched;
        } catch (_) {/* fall through */}
      }
    }

    // Last resort: hand the deep link to the OS.
    if (url != null && !kIsWeb) {
      try {
        if (Platform.isLinux || Platform.isMacOS) {
          final r = await Process.run('xdg-open', [url]);
          if (r.exitCode == 0) return LaunchOutcome.launched;
        }
      } catch (_) {/* fall through */}
    }

    return url == null ? LaunchOutcome.notInstalled : LaunchOutcome.failed;
  }

  /// Opens an arbitrary web address (settings links, feedback, docs).
  Future<bool> openUrl(String url) async {
    try {
      return await launchUrl(Uri.parse(url), mode: _mode);
    } catch (_) {
      return false;
    }
  }
}
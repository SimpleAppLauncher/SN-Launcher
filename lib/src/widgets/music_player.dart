import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/adblock.dart';

/// In-app music player backed by the system WebView.
///
/// ## Laziness contract (read before wiring this up)
///
/// The `WebViewController` is created in [initState], i.e. the moment this
/// widget is first mounted — **never** at app start. Idle cold start on the
/// target tablet is 0.8 s and a WebView costs a few hundred MB of address
/// space plus a Chromium compositor thread; constructing one eagerly would
/// regress that for a feature most sessions never open. Build this widget
/// only when the music page is actually opened, and dispose it (or at least
/// stop its audio) when the page closes.
///
/// ## What the ad filtering does and does not do
///
/// Requests to hosts on [AdBlock]'s list are cancelled before they leave the
/// WebView, and a small injected script removes common ad containers and
/// stubs `window.adsbygoogle`. That is enough to kill YouTube's pre-roll /
/// overlay / sidebar ads, which are fetched as ordinary requests from
/// doubleclick-style domains and live in identifiable DOM nodes.
///
/// It is **not** enough for Spotify, and the UI says so: Spotify's ad break is
/// spliced into the same audio stream as the content by its servers, so no
/// URL filter can see it, and the player requires a login regardless. Each
/// source carries a [canBlockAds] capability flag and the header states
/// plainly whether filtering applies — never claim Spotify ads are blocked.
///
/// ## Android specifics
///
/// `JavaScriptMode.unrestricted` is set explicitly: web players refuse to run
/// with scripting disabled. DOM storage (`domStorageEnabled`) has no
/// cross-platform setter in webview_flutter 4.x and does not need one — the
/// endorsed Android implementation turns it on unconditionally in
/// `AndroidWebViewController`'s constructor (verified against
/// webview_flutter_android 4.14.1, `android_webview_controller.dart`), which
/// is what Spotify's localStorage-backed login depends on. That is also why
/// this file deliberately does not import the Android implementation package:
/// there is nothing to set, and importing it would add an undeclared direct
/// dependency for zero benefit.
class MusicPlayer extends StatefulWidget {
  const MusicPlayer({
    super.key,
    required this.url,
    required this.title,
    required this.backgroundColor,
    required this.foregroundColor,
    this.canBlockAds,
    this.onClose,
  });

  /// Entry URL. Must be `http`/`https`; anything else shows the error card.
  final String url;

  /// Human label for the source, shown in the header and error card.
  final String title;

  /// Page background. Also used behind the loading overlay so a cold WebView
  /// never flashes white on an ambient display.
  final Color backgroundColor;

  /// Text / icon colour for the header, overlays and controls.
  final Color foregroundColor;

  /// Whether ad filtering is effective for this source.
  ///
  /// `null` (the default) infers it from [url]: true for the YouTube family,
  /// false for everything else (including Spotify, whose ads are inserted
  /// server-side into the audio stream and cannot be filtered by any URL
  /// filter). Pass an explicit value only to override the inference.
  final bool? canBlockAds;

  /// Closes the player.
  ///
  /// The player used to be a full-screen route, so it had no close button —
  /// the back gesture did it. It now lives in a panel on the launcher, which
  /// has no back gesture of its own, so it needs one.
  final VoidCallback? onClose;

  @override
  State<MusicPlayer> createState() => _MusicPlayerState();
}

class _MusicPlayerState extends State<MusicPlayer> {
  WebViewController? _controller;

  /// Whether the page-side filter actually installed.
  ///
  /// Set from the script's own return value, not assumed.
  bool _filterInstalled = false;

  /// 0–100 from the platform, or -1 before the first callback.
  int _progress = -1;

  /// Set when the main frame fails to load; drives the error card.
  String? _failure;

  /// Backstop for loads that never resolve.
  ///
  /// Android reports most network failures through `onWebResourceError`, but
  /// the plugin's error mapper throws on Chromium net codes it does not
  /// recognise (DNS failure -105, connection refused -101, …), so the
  /// callback can be skipped entirely. Without this the spinner would hang
  /// forever; with it, a stalled load ends on the honest error card.
  Timer? _watchdog;

  static const Duration _loadTimeout = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_loadTimeout, () {
      if (!mounted || _failure != null || _progress >= 100) return;
      setState(() {
        _failure = 'The page did not finish loading. '
            'Check the network connection and try again.';
      });
    });
  }

  /// Builds the WebView and starts the first load. Called once, from
  /// [initState] — this is the lazy boundary described on [MusicPlayer].
  void _open() {
    final Uri? target = Uri.tryParse(widget.url);
    if (target == null ||
        !(target.isScheme('http') || target.isScheme('https'))) {
      _failure = 'This source is not a web address:\n${widget.url}';
      return;
    }

    final WebViewController controller = WebViewController()
      // Without unrestricted JS every music site refuses to play.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Keeps the cold WebView from flashing white over the ambient display.
      ..setBackgroundColor(widget.backgroundColor)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onProgress: (int progress) {
            if (!mounted || _failure != null) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!mounted || _failure != null) return;
            setState(() => _progress = 0);
            _injectCosmeticFilter();
          },
          onPageFinished: (_) {
            _injectCosmeticFilter();
            _watchdog?.cancel();
            if (!mounted || _failure != null) return;
            setState(() => _progress = 100);
          },
          onWebResourceError: _onWebResourceError,
        ),
      );

    _controller = controller;
    controller.loadRequest(target);
    _armWatchdog();
  }

  /// Ad requests are cancelled here, before the socket opens.
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final Uri? uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;

    if (AdBlock.shouldBlock(uri)) return NavigationDecision.prevent;

    final String scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' ||
        scheme == 'https' ||
        // blob:/data: are how players address their own media and inline
        // documents; they must stay inside the WebView.
        scheme == 'blob' ||
        scheme == 'data' ||
        scheme == 'about') {
      return NavigationDecision.navigate;
    }

    // Anything else (spotify:, intent:, mailto:, market: …) is not ours to
    // render. Hand main-frame cases to the OS instead of dying silently;
    // suppress subframe attempts, which are almost always redirect junk.
    if (request.isMainFrame) {
      unawaited(
        launchUrl(uri, mode: LaunchMode.externalApplication)
            .catchError((Object _) => false),
      );
    }
    return NavigationDecision.prevent;
  }

  void _onWebResourceError(WebResourceError error) {
    // Android's Chromium stack reports cancelled loads (our own ad blocking,
    // a superseded redirect) as error code -3, net::ERR_ABORTED. The plugin
    // relabels it `unsupportedAuthScheme`, but it is not a load failure the
    // user should ever see.
    if (error.errorCode == -3) return;

    // Subframe and subresource hiccups (one dead ad pixel, one failed font)
    // must never surface as a page error.
    if (error.isForMainFrame == false) return;

    _watchdog?.cancel();
    if (!mounted) return;
    setState(() {
      _failure = error.description.isEmpty
          ? 'The page could not be loaded.'
          : error.description;
    });
  }

  /// Removes ad containers and neutralises `adsbygoogle`.
  ///
  /// Re-injected on every page start/finish because SPA navigation wipes the
  /// document. The script is idempotent (guarded by `__snLauncherFilter`) and
  /// entirely wrapped in try/catch: a filter that throws must never be able
  /// to break the page it is filtering.
  void _injectCosmeticFilter() {
    _controller?.runJavaScript(_filterJs).then((Object? result) {
      // The page reports whether it actually installed the filter. Without
      // that, "ads blocked" is a claim about a list of domains that nothing
      // ever consulted.
      final installed = result == true;
      if (installed != _filterInstalled && mounted) {
        setState(() => _filterInstalled = installed);
      }
    }).catchError((Object e) {
      debugPrint('MusicPlayer: filter injection failed: $e');
      return null;
    });
  }

  /// Whether ads are actually being blocked.
  ///
  /// Both conditions have to hold: the site has to be one where blocking is
  /// possible at all, and the filter has to have actually installed. Before,
  /// this was decided by the URL alone, so the player claimed to be blocking
  /// ads before it had blocked anything.
  bool get _effectiveCanBlockAds =>
      _filterInstalled && (widget.canBlockAds ?? _canBlockAdsForHost(widget.url));

  /// YouTube serves its ads as real requests from real ad domains, so the
  /// URL filter reaches them. Everything else is false: claiming otherwise
  /// (Spotify above all) would be a lie, since its ads are inside the stream.
  static bool _canBlockAdsForHost(String url) {
    final String host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be' ||
        host.endsWith('.youtu.be');
  }

  @override
  Widget build(BuildContext context) {
    final Color fg = widget.foregroundColor;
    return ColoredBox(
      color: widget.backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: widget.title,
            canBlockAds: _effectiveCanBlockAds,
            onClose: widget.onClose,
            foregroundColor: fg,
            backgroundColor: widget.backgroundColor,
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_controller != null && _failure == null)
                  WebViewWidget(controller: _controller!),
                if (_controller != null &&
                    _failure == null &&
                    _progress < 100)
                  ColoredBox(
                    color: widget.backgroundColor,
                    child: Center(
                      child: CircularProgressIndicator(
                        // Indeterminate at -1, real progress once known.
                        value: _progress < 0 ? null : _progress / 100,
                        color: fg,
                      ),
                    ),
                  ),
                if (_failure != null)
                  _ErrorCard(
                    title: widget.title,
                    message: _failure!,
                    foregroundColor: fg,
                    backgroundColor: widget.backgroundColor,
                    onRetry: _controller == null
                        ? null
                        : () {
                            setState(() {
                              _failure = null;
                              _progress = -1;
                            });
                            _armWatchdog();
                            _controller!.reload();
                          },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Source title plus an honest statement of what ad filtering does here.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.canBlockAds,
    this.onClose,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final String title;
  final bool canBlockAds;
  final VoidCallback? onClose;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final Color muted = foregroundColor.withValues(alpha: 0.65);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(color: foregroundColor.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'GoogleSans',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: foregroundColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (onClose != null) ...[
            IconButton(
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, color: foregroundColor),
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              visualDensity: VisualDensity.compact,
              tooltip: 'Close',
            ),
            const SizedBox(width: 8),
          ],
          Icon(
            canBlockAds ? Icons.block : Icons.speaker_phone_outlined,
            size: 16,
            color: muted,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              canBlockAds
                  ? 'Ad filtering on — best effort'
                  : 'Ad filtering unavailable — ads are inside the stream',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'GoogleSans',
                fontSize: 12,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of a blank rectangle when the page cannot be loaded.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.title,
    required this.message,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.onRetry,
  });

  final String title;
  final String message;
  final Color foregroundColor;
  final Color backgroundColor;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final Color muted = foregroundColor.withValues(alpha: 0.7);
    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 48, color: muted),
                const SizedBox(height: 16),
                Text(
                  "Couldn't load $title",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'GoogleSans',
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: foregroundColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'GoogleSans',
                    fontSize: 13,
                    color: muted,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: foregroundColor,
                      foregroundColor: backgroundColor,
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cosmetic-filter payload. Runs inside the page, so it is plain ES5-flavoured
/// JS with every operation guarded: this script may only ever remove ad nodes
/// and stub one global, never throw into the host page.
/// The filter, with the blocklist baked in.
///
/// The list lives in [kBlockedHostSuffixes] so it is testable in Dart, and it
/// is injected into the page as JSON so the page-side filter and the Dart side
/// agree on exactly one list. Two lists is how "blocked" and "not blocked"
/// end up disagreeing.
///
/// **This is the part that was missing.** The blocklist existed, was tested,
/// and was never consulted by anything: there was no request interception at
/// all, only a DOM sweep that removed the ad boxes after they had already been
/// fetched. The page-side filter below blocks the ad *requests* — which is
/// what stops the ad being fetched in the first place.
///
/// `webview_flutter` 4.x does not expose `shouldInterceptRequest`, so a
/// native interceptor is not available without writing a platform view. Doing
/// it in the page is the difference between "the ad was fetched and then
/// hidden" and "the ad was never fetched".
String get _filterJs => '''
(function () {
  try {
    if (window.__snLauncherFilter) {
      return window.__snLauncherFilterInstalled === true;
    }
    window.__snLauncherFilter = true;

    var HOSTS = ${jsonEncode(kBlockedHostSuffixes)};

    function blocked(url) {
      try {
        var host = String(url).toLowerCase();
        var m = host.match(/^https?:\\/\\/([^\\/]+)/);
        if (m) host = m[1];
        else {
          var p2 = host.indexOf('//');
          if (p2 >= 0) {
            host = host.substring(p2 + 2);
            var slash = host.indexOf('/');
            if (slash >= 0) host = host.substring(0, slash);
          }
        }
        host = host.split(':')[0];
        if (!host) return false;
        for (var i = 0; i < HOSTS.length; i++) {
          var sfx = HOSTS[i];
          if (host === sfx || host.endsWith('.' + sfx)) return true;
        }
        return false;
      } catch (e) { return false; }
    }

    // fetch
    try {
      var origFetch = window.fetch;
      if (origFetch && !origFetch.__snPatched) {
        var patchedFetch = function (input, init) {
          var url = (typeof input === 'string') ? input : (input && input.url);
          if (blocked(url)) {
            return Promise.reject(new TypeError('Network request blocked'));
          }
          return origFetch.apply(this, arguments);
        };
        patchedFetch.__snPatched = true;
        window.fetch = patchedFetch;
      }
    } catch (e) {}

    // XMLHttpRequest
    try {
      var XHR = window.XMLHttpRequest;
      if (XHR && XHR.prototype && !XHR.prototype.open.__snPatched) {
        var origOpen = XHR.prototype.open;
        var patchedOpen = function (method, url) {
          this.__snUrl = url;
          return origOpen.apply(this, arguments);
        };
        patchedOpen.__snPatched = true;
        XHR.prototype.open = patchedOpen;

        var origSend = XHR.prototype.send;
        XHR.prototype.send = function () {
          if (blocked(this.__snUrl)) {
            try {
              Object.defineProperty(this, 'readyState',
                {value: 4, configurable: true});
            } catch (e) {}
            try { this.dispatchEvent(new Event('error')); } catch (e) {}
            return;
          }
          return origSend.apply(this, arguments);
        };
      }
    } catch (e) {}

    // sendBeacon - a lot of ad reporting goes through it.
    try {
      if (navigator.sendBeacon && !navigator.sendBeacon.__snPatched) {
        var origBeacon = navigator.sendBeacon.bind(navigator);
        var patchedBeacon = function (url) {
          if (blocked(url)) return false;
          return origBeacon(url);
        };
        patchedBeacon.__snPatched = true;
        navigator.sendBeacon = patchedBeacon;
      }
    } catch (e) {}

    var SELECTORS = [
      'ins.adsbygoogle',
      '.ytp-ad-module',
      '.ytp-ad-overlay',
      '.video-ads',
      '[id^="google_ads"]',
      '.ad-container',
      '#player-ads',
      '.promoted-video-renderer'
    ];
    var QUERY = SELECTORS.join(',');

    function sweep() {
      try {
        var nodes = document.querySelectorAll(QUERY);
        for (var i = 0; i < nodes.length; i++) {
          var n = nodes[i];
          if (n && n.parentNode) n.parentNode.removeChild(n);
        }
      } catch (e) {}
    }

    // Coalesced so a busy DOM (YouTube swaps nodes constantly) costs at most
    // one sweep per 200 ms — this hardware is weak.
    var scheduled = false;
    function schedule() {
      if (scheduled) return;
      scheduled = true;
      setTimeout(function () { scheduled = false; sweep(); }, 200);
    }

    try {
      if (document.documentElement) {
        new MutationObserver(schedule).observe(document.documentElement, {
          childList: true,
          subtree: true
        });
      }
    } catch (e) {}

    try {
      if (!window.adsbygoogle) {
        window.adsbygoogle = {
          pushed: {},
          push: function () { return 0; },
          loaded: true,
          length: 0
        };
      }
    } catch (e) {}

    sweep();
    try {
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', sweep);
      }
    } catch (e) {}

    window.__snLauncherFilterInstalled = true;
    return true;
  } catch (e) {
    return false;
  }
})();
''';

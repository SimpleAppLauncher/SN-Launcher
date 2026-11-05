import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'device_media_watcher.dart';
import 'feature_flags.dart';
import 'settings_store.dart';
import '../state/shell_controller.dart';

// Private fields keep the service API small; the constructor still takes
// public names so callers outside this library can construct it.
// ignore_for_file: prefer_initializing_formals

/// EF-only LAN remote control.
///
/// This is deliberately not a cloud service and not a TV/D-pad shim. It serves
/// a small HTML control page and a token-protected JSON command endpoint on the
/// local network. The normal (reduced) build never constructs or starts this
/// service because `remoteControl` is off in its feature file.
class RemoteControlService extends ChangeNotifier {
  RemoteControlService({
    required SettingsStore settings,
    required DeviceMediaWatcher media,
    this.preferredPort = 8765,
  }) : _settings = settings,
       _media = media;

  final SettingsStore _settings;
  final DeviceMediaWatcher _media;
  final int preferredPort;

  HttpServer? _server;
  ShellController? _controller;
  bool _enabled = false;
  bool _starting = false;
  bool _disposed = false;
  String _token = '';
  String? _error;
  List<String> _addresses = const <String>[];
  int _port = 8765;

  bool get enabled => _enabled;
  bool get running => _server != null;
  bool get starting => _starting;
  String get token => _token;
  String? get error => _error;
  List<String> get addresses => List<String>.unmodifiable(_addresses);
  int get port => _server?.port ?? _port;
  bool get hasController => _controller != null;

  void attach(ShellController controller) {
    _controller = controller;
  }

  /// Restore the persisted switch and token, then start the server only when
  /// both the build flag and the user's switch allow it.
  Future<void> restore() async {
    await _settings.load();
    _enabled = _settings.read(
      SettingKeys.remoteControlEnabled,
      false,
      (value) => value == 'true',
    );
    _token = _settings.get(SettingKeys.remoteControlToken) ?? '';
    if (!FeatureFlags.current.isOn('remoteControl')) {
      _enabled = false;
      _changed();
      return;
    }
    if (!_enabled) {
      _changed();
      return;
    }
    await start();
  }

  Future<void> setEnabled(bool value) async {
    if (value && !FeatureFlags.current.isOn('remoteControl')) {
      _error = 'Remote control is not available in this build.';
      _changed();
      return;
    }
    if (_enabled == value) {
      if (value && !running && !starting) {
        await start();
      }
      return;
    }
    _enabled = value;
    await _settings.put(SettingKeys.remoteControlEnabled, '$value');
    if (value) {
      await start();
    } else {
      await stop();
    }
    _changed();
  }

  Future<void> regenerateToken() async {
    _token = _newToken();
    await _settings.put(SettingKeys.remoteControlToken, _token);
    _changed();
  }

  Future<void> start() async {
    if (!FeatureFlags.current.isOn('remoteControl')) {
      _error = 'Remote control is not available in this build.';
      _changed();
      return;
    }
    if (_server != null || _starting) return;
    final controller = _controller;
    if (controller == null) {
      _error = 'The launcher is not ready yet.';
      _changed();
      return;
    }
    if (_token.isEmpty) {
      _token = _newToken();
      await _settings.put(SettingKeys.remoteControlToken, _token);
    }

    _starting = true;
    _error = null;
    _changed();

    HttpServer? server;
    try {
      try {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          preferredPort,
          shared: false,
        );
      } on SocketException {
        // The preferred port is normally free, but a second launcher or a
        // previous process can hold it. Falling back to an ephemeral port is
        // better than making the switch look broken.
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          0,
          shared: false,
        );
      }
      _server = server;
      _port = server.port;
      _addresses = await _lanAddresses();
      server.listen(
        _handle,
        onError: (Object error, StackTrace stack) {
          _error = 'Remote server error: $error';
          _changed();
        },
        cancelOnError: false,
      );
      _starting = false;
      _changed();
    } catch (error) {
      _server = null;
      _starting = false;
      _error = 'Could not start the remote server: $error';
      debugPrint('SNREMOTE start failed: $error');
      await server?.close(force: true);
      _changed();
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _addresses = const <String>[];
    _starting = false;
    if (server != null) {
      await server.close(force: true);
    }
    _changed();
  }

  Future<List<String>> _lanAddresses() async {
    final addresses = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4 &&
              !address.isLoopback &&
              !addresses.contains(address.address)) {
            addresses.add(address.address);
          }
        }
      }
    } catch (error) {
      debugPrint('SNREMOTE address lookup failed: $error');
    }
    return addresses.isEmpty ? const <String>['127.0.0.1'] : addresses;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/favicon.ico') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
      if (request.method == 'GET' && path == '/') {
        await _html(request, _controlPage);
        return;
      }
      if (request.method == 'GET' && path == '/api/state') {
        if (!_authorized(request)) {
          await _unauthorized(request);
          return;
        }
        await _json(request, HttpStatus.ok, _state());
        return;
      }
      if (request.method == 'POST' && path == '/api/command') {
        if (!_authorized(request)) {
          await _unauthorized(request);
          return;
        }
        final body = await _readBody(request);
        if (body == null) {
          await _json(request, HttpStatus.badRequest, <String, Object?>{
            'ok': false,
            'error': 'Body must be a JSON object under 4 KB.',
          });
          return;
        }
        await _execute(request, body);
        return;
      }
      await _json(request, HttpStatus.notFound, <String, Object?>{
        'ok': false,
        'error': 'Not found.',
      });
    } catch (error) {
      debugPrint('SNREMOTE request failed: $error');
      try {
        await _json(request, HttpStatus.internalServerError, <String, Object?>{
          'ok': false,
          'error': 'Request failed.',
        });
      } catch (_) {
        // The response may already be closed; nothing useful to add.
      }
    }
  }

  bool _authorized(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    var supplied = '';
    if (header != null && header.startsWith('Bearer ')) {
      supplied = header.substring('Bearer '.length).trim();
    }
    if (supplied.isEmpty) {
      supplied = request.uri.queryParameters['token'] ?? '';
    }
    return _constantTimeEquals(supplied, _token);
  }

  bool _constantTimeEquals(String supplied, String expected) {
    if (expected.isEmpty) return false;
    final length = supplied.length > expected.length
        ? supplied.length
        : expected.length;
    var difference = supplied.length ^ expected.length;
    for (var i = 0; i < length; i++) {
      final a = i < supplied.length ? supplied.codeUnitAt(i) : 0;
      final b = i < expected.length ? expected.codeUnitAt(i) : 0;
      difference |= a ^ b;
    }
    return difference == 0;
  }

  Future<Map<String, Object?>?> _readBody(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > 4096) return null;
    }
    if (bytes.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _state() {
    final controller = _controller!;
    final session = _media.session;
    return <String, Object?>{
      'ok': true,
      'page': controller.page.name,
      'pages': controller.availablePages.map((page) => page.name).toList(),
      'sheet': controller.sheetProgress,
      'brightness': controller.brightness,
      'volume': controller.volume,
      'theme': controller.theme.name,
      'media': session == null
          ? null
          : <String, Object?>{
              'package': session.package,
              'title': session.title,
              'artist': session.artist,
              'album': session.album,
              'playing': session.playing,
              'canPlay': session.canPlay,
              'canPause': session.canPause,
              'canNext': session.canNext,
              'canPrevious': session.canPrevious,
              'position': session.position.inMilliseconds,
              'duration': session.duration.inMilliseconds,
            },
    };
  }

  Future<void> _execute(HttpRequest request, Map<String, Object?> body) async {
    final controller = _controller!;
    final command = body['command'];
    if (command is! String) {
      await _json(request, HttpStatus.badRequest, <String, Object?>{
        'ok': false,
        'error': 'Missing command.',
      });
      return;
    }

    switch (command) {
      case 'page':
        final name = body['page'];
        if (name is! String) {
          await _json(request, HttpStatus.badRequest, <String, Object?>{
            'ok': false,
            'error': 'page must be a page name.',
          });
          return;
        }
        ShellPage? page;
        for (final candidate in ShellPage.values) {
          if (candidate.name == name) {
            page = candidate;
            break;
          }
        }
        final accepted =
            page != null && controller.availablePages.contains(page);
        if (accepted) controller.goToPage(page);
        await _accepted(request, command, accepted);
        return;

      case 'sheet':
        final action = body['action'];
        if (action == 'open') {
          if (controller.sheetProgress < 0.5) controller.toggleSheet();
        } else if (action == 'close') {
          controller.closeSheet();
        } else if (action == 'toggle') {
          controller.toggleSheet();
        } else {
          await _json(request, HttpStatus.badRequest, <String, Object?>{
            'ok': false,
            'error': 'sheet action must be open, close or toggle.',
          });
          return;
        }
        await _accepted(request, command, true);
        return;

      case 'brightness':
        final delta = _number(body['delta']);
        if (delta == null) {
          await _json(request, HttpStatus.badRequest, <String, Object?>{
            'ok': false,
            'error': 'brightness needs a numeric delta.',
          });
          return;
        }
        controller.nudgeBrightness(delta.clamp(-1.0, 1.0));
        await _accepted(request, command, true);
        return;

      case 'volume':
        final delta = _number(body['delta']);
        if (delta == null) {
          await _json(request, HttpStatus.badRequest, <String, Object?>{
            'ok': false,
            'error': 'volume needs a numeric delta.',
          });
          return;
        }
        controller.nudgeVolume(delta.clamp(-1.0, 1.0));
        await _accepted(request, command, true);
        return;

      case 'theme':
        controller.cycleTheme();
        await _accepted(request, command, true);
        return;

      case 'media':
        final action = body['action'];
        if (action is! String ||
            !const <String>{
              'play',
              'pause',
              'next',
              'previous',
            }.contains(action)) {
          await _json(request, HttpStatus.badRequest, <String, Object?>{
            'ok': false,
            'error': 'media action must be play, pause, next or previous.',
          });
          return;
        }
        final accepted = await _media.command(action);
        await _accepted(request, command, accepted);
        return;

      default:
        await _json(request, HttpStatus.badRequest, <String, Object?>{
          'ok': false,
          'error': 'Unknown command.',
        });
    }
  }

  double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<void> _accepted(
    HttpRequest request,
    String command,
    bool accepted,
  ) async {
    await _json(request, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'command': command,
      'accepted': accepted,
    });
  }

  Future<void> _json(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) async {
    final response = request.response;
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _html(HttpRequest request, String body) async {
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.html;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(body);
    await response.close();
  }

  Future<void> _unauthorized(HttpRequest request) async {
    await _json(request, HttpStatus.unauthorized, <String, Object?>{
      'ok': false,
      'error': 'Missing or invalid token.',
    });
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  String _newToken() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List<String>.generate(
      32,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  @override
  void dispose() {
    _disposed = true;
    _server?.close(force: true);
    _server = null;
    super.dispose();
  }

  static const String _controlPage = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SN-Launcher remote</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 24px; font: 16px/1.45 system-ui, sans-serif; background: #111; color: #eee; }
  main { max-width: 620px; margin: 0 auto; }
  h1 { font-size: 24px; margin: 0 0 4px; }
  p { color: #aaa; }
  label { display: block; margin: 18px 0 6px; color: #ccc; }
  input { width: 100%; padding: 10px 12px; border: 1px solid #333; border-radius: 8px; background: #1b1b1b; color: #eee; }
  button { padding: 10px 14px; margin: 4px 4px 4px 0; border: 1px solid #444; border-radius: 999px; background: #222; color: #eee; font: inherit; cursor: pointer; }
  button:active { background: #333; }
  .row { margin: 12px 0; }
  .status { min-height: 24px; color: #8fd18f; }
  .warn { color: #e0b36a; }
  #pages { display: flex; flex-wrap: wrap; }
</style>
</head>
<body>
<main>
  <h1>SN-Launcher remote</h1>
  <p>EF build only. This page talks directly to the launcher on your LAN over
  HTTP. It is not a TV remote and it does not expose a cloud service.</p>
  <label for="token">Token from Settings → Remote control</label>
  <input id="token" type="password" autocomplete="off" spellcheck="false">
  <div class="row"><button id="save">Use token</button><button id="refresh">Refresh</button></div>
  <div id="status" class="status"></div>
  <div class="row"><strong>Page</strong><div id="pages"></div></div>
  <div class="row"><strong>Sheet</strong><br>
    <button data-sheet="open">Open</button>
    <button data-sheet="close">Close</button>
    <button data-sheet="toggle">Toggle</button>
  </div>
  <div class="row"><strong>Brightness</strong><br>
    <button data-brightness="-0.1">−</button>
    <button data-brightness="0.1">+</button>
    <strong>Volume</strong><br>
    <button data-volume="-0.1">−</button>
    <button data-volume="0.1">+</button>
  </div>
  <div class="row"><strong>Theme</strong><br><button id="theme">Next theme</button></div>
  <div class="row"><strong>Media</strong><br>
    <button data-media="previous">Previous</button>
    <button data-media="play">Play</button>
    <button data-media="pause">Pause</button>
    <button data-media="next">Next</button>
  </div>
  <p class="warn">HTTP is not encrypted. Use this only on a trusted local network,
  and treat the token like a password.</p>
</main>
<script>
let token = localStorage.getItem('sn-launcher-token') || '';
const $ = (id) => document.getElementById(id);
const status = (text, warn = false) => { $('status').textContent = text; $('status').className = warn ? 'status warn' : 'status'; };
$('token').value = token;
$('save').onclick = () => { token = $('token').value.trim(); localStorage.setItem('sn-launcher-token', token); status('Token saved. Refreshing…'); refresh(); };
$('refresh').onclick = refresh;

async function call(path, body) {
  if (!token) { status('Enter the token shown in Settings → Remote control.', true); return null; }
  try {
    const response = await fetch(path, {
      method: body ? 'POST' : 'GET',
      headers: { 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok || data.ok === false) { status(data.error || ('HTTP ' + response.status), true); return null; }
    return data;
  } catch (error) { status('Could not reach the launcher: ' + error, true); return null; }
}

async function command(body) {
  const data = await call('/api/command', body);
  if (data) { status(data.accepted ? 'Sent.' : 'The launcher did not accept that command.', !data.accepted); refresh(); }
}

async function refresh() {
  const data = await call('/api/state');
  if (!data) return;
  status('Connected. Page: ' + data.page);
  const pages = $('pages');
  pages.textContent = '';
  for (const page of data.pages) {
    const button = document.createElement('button');
    button.textContent = page[0].toUpperCase() + page.slice(1);
    button.onclick = () => command({ command: 'page', page });
    pages.appendChild(button);
  }
  $('theme').textContent = 'Theme: ' + data.theme + ' (next)';
}

for (const button of document.querySelectorAll('[data-sheet]')) button.onclick = () => command({ command: 'sheet', action: button.dataset.sheet });
for (const button of document.querySelectorAll('[data-brightness]')) button.onclick = () => command({ command: 'brightness', delta: Number(button.dataset.brightness) });
for (const button of document.querySelectorAll('[data-volume]')) button.onclick = () => command({ command: 'volume', delta: Number(button.dataset.volume) });
for (const button of document.querySelectorAll('[data-media]')) button.onclick = () => command({ command: 'media', action: button.dataset.media });
$('theme').onclick = () => command({ command: 'theme' });
refresh();
</script>
</body>
</html>''';
}

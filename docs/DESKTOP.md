# Desktop builds — Linux and macOS

Both versions of SN-Launcher build for Linux and macOS. The Android build is
the primary target; these are the same Dart, the same two feature JSON files,
the same everything else.

## The honest part first: you cannot build either of these from a Mac

**Linux cannot be cross-compiled at all.** Flutter does not build a Linux
desktop binary on macOS or Windows — the toolchain is the toolchain, and a
Linux build needs a Linux machine.

**macOS needs the full Xcode**, not just the Command Line Tools. The build
needs the macOS SDK and an AppKit build phase. If `xcode-select -p` points at
`/Library/Developer/CommandLineTools`, `flutter build macos` will stop with
*"Xcode not installed"* even though `xcodebuild` is on your PATH and
`clang` works.

So the builds happen in CI. `.github/workflows/desktop.yml` builds both on
`ubuntu-24.04` and `macos-14` runners, for both feature sets, and uploads the
results as artefacts. Push a tag and the binaries appear.

To build one yourself:

```bash
# Linux, on a Linux machine
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
flutter build linux --release --dart-define=SN_FEATURES=assets/features.json

# macOS, on a Mac with the full Xcode
flutter build macos --release --dart-define=SN_FEATURES=assets/features.json
```

Use `assets/features.ef.json` for the ef build, and
`--dart-define=SN_BUILD_NAME=ef` to match.

## What is different on the desktop

The Dart is the same, and the codebase was written with this in mind: every
method channel catches `MissingPluginException` and answers with a null rather
than throwing, and `SettingsStore` falls back to a file in the system temp
directory when the platform channel is not there — which on Android is the
app's private cache and on a desktop is `/tmp`.

| | Desktop |
| --- | --- |
| The clock, the calendar, the to-do list, the themes | work |
| The photo frame, the rotating background | work; the cache is in the temp directory, so it is not persistent |
| The weather page | works; the location falls back to an IP lookup, which is city-level |
| The radio player | **no** — it is a Media3 foreground service, which is an Android thing |
| The voice assistant | **no** — the speech recogniser is Android only |
| The dock and the app drawer | work; they launch applications on the machine |
| The now-playing card | works, and reads another application's playing state — see below |

## Showing another application's now-playing

This is the part that exists for **NCS-SMLauncher**, and it is deliberately
simple, because the other side is a Python application and cannot be asked to
implement an Android `MediaSession`.

The mechanism is a file.

### The contract

Any application on the machine may write a JSON object to a known path, and
SN-Launcher will show it on the now-playing card.

```json
{
  "title":      "Some track",
  "artist":     "Some artist",
  "album":      "Some album",
  "positionMs": 61500,
  "durationMs": 240000,
  "playing":    true,
  "source":     "NCS-SMLauncher"
}
```

Every field except `title` is optional.

### Where the file goes

1. `$SN_LAUNCHER_NOW_PLAYING` if it is set. This is the explicit contract, and
   the one to use when the other application wants a specific path.
2. Otherwise `$XDG_CACHE_HOME/sn_launcher/now_playing.json`, or
   `~/.cache/sn_launcher/now_playing.json` on Linux.
3. Otherwise `~/Library/Caches/sn_launcher/now_playing.json` on macOS.

### Rules for the writer

- **Write atomically.** Write to a temporary file in the same directory and
  rename it over the target. A half-written file is a JSON parse error, and a
  parse error means "nothing is playing" — so a non-atomic writer makes the
  card flicker off and on.
- **Clear it when you stop.** Delete the file, or write `{"playing": false}`.
  A file left behind by a crashed application is ignored after fifteen
  seconds anyway, so the card cannot show a track that stopped playing hours
  ago — but clearing it is better.
- **Do not write it more often than once a second.** The reader only redraws
  when the reading actually changes, so a faster writer costs nothing but a
  little CPU.

### Reading it from Python, for NCS-SMLauncher

```python
import json, os, pathlib, tempfile

def now_playing_path() -> pathlib.Path:
    override = os.environ.get("SN_LAUNCHER_NOW_PLAYING")
    if override:
        return pathlib.Path(override)
    if sys.platform == "darwin":
        return pathlib.Path.home() / "Library/Caches/sn_launcher/now_playing.json"
    cache = os.environ.get("XDG_CACHE_HOME") or (pathlib.Path.home() / ".cache")
    return cache / "sn_launcher/now_playing.json"

def publish(title, artist="", album="", position_ms=0, duration_ms=0, playing=True):
    path = now_playing_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    reading = {
        "title": title, "artist": artist, "album": album,
        "positionMs": position_ms, "durationMs": duration_ms,
        "playing": playing, "source": "NCS-SMLauncher",
    }
    # Atomic: same directory, then rename. A reader must never see half a file.
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as f:
        json.dump(reading, f)
        tmp = f.name
    os.replace(tmp, path)
```

### On Android

This file contract is **not** used on Android. There the platform already has
the right mechanism — `MediaSession` — and using it means the card shows music
from Spotify, YouTube Music, SoundCloud and anything else that publishes a
session, rather than only from applications that know about this file.

That path needs the notification-listener permission, which is why the reduced
build does not have it and the ef build does.

## The tests

`test/external_now_playing_test.dart` is the whole contract, exercised. It
covers the file being missing, empty, malformed, an array rather than an
object, having no title, being too old, and the reader not waking the UI for a
position that moved less than a second.

Those are the ways a file somebody else is writing goes wrong, and every one
of them has to be survivable.

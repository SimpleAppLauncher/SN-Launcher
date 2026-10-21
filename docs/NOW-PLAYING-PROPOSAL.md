Proposed: a now-playing bridge between SN-Launcher and NCS-SMLauncher.

The problem. NCS-SMLauncher is a Python/pygame application and SN-Launcher is
a Flutter application, mostly for Android. They cannot talk through the
platform, because a desktop application cannot publish an Android
MediaSession -- that is the mechanism SN-Launcher already uses on a phone to
show what Spotify or YouTube Music is playing.

The proposal: a file.

Either application may write a small JSON object to a known path, and
SN-Launcher will show it on its now-playing card. No dependency either way, no
sockets, no ports, nothing to run.

    {
      "title":      "Some track",
      "artist":     "Some artist",
      "album":      "Some album",
      "positionMs": 61500,
      "durationMs": 240000,
      "playing":    true,
      "source":     "NCS-SMLauncher"
    }

Every field except "title" is optional.

Where the file goes:
  1. $SN_LAUNCHER_NOW_PLAYING, if set -- the explicit contract
  2. $XDG_CACHE_HOME/sn_launcher/now_playing.json, or
     ~/.cache/sn_launcher/now_playing.json on Linux
  3. ~/Library/Caches/sn_launcher/now_playing.json on macOS

What the writer has to do:
  - Write atomically. Write to a temporary file in the same directory and
    rename it over the target. A half-written file is a JSON parse error,
    and a parse error reads as "nothing is playing", so a non-atomic writer
    makes the card flicker off and on.
  - Clear it when playback stops, or write {"playing": false}.
  - Do not write it more than once a second. The reader only redraws when the
    reading actually changes.

Python side, for NCS-SMLauncher:

    import json, os, pathlib, sys, tempfile

    def now_playing_path() -> pathlib.Path:
        override = os.environ.get("SN_LAUNCHER_NOW_PLAYING")
        if override:
            return pathlib.Path(override)
        if sys.platform == "darwin":
            return pathlib.Path.home() / "Library/Caches/sn_launcher/now_playing.json"
        cache = os.environ.get("XDG_CACHE_HOME") or (pathlib.Path.home() / ".cache")
        return cache / "sn_launcher/now_playing.json"

    def publish(title, artist="", album="", position_ms=0,
                 duration_ms=0, playing=True):
        path = now_playing_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        reading = {
            "title": title, "artist": artist, "album": album,
            "positionMs": position_ms, "durationMs": duration_ms,
            "playing": playing, "source": "NCS-SMLauncher",
        }
        with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as f:
            json.dump(reading, f)
            tmp = f.name
        os.replace(tmp, path)   # atomic

The reader side is already implemented and tested in SN-Launcher
(test/external_now_playing_test.dart covers the file being missing, empty,
malformed, an array, having no title, being too old, and the reader not
waking the UI for a position that moved less than a second).

Two questions for the NCS-SMLauncher side:
  1. Does NCS-SMLauncher know the track title, artist and duration at the point
     it would publish? If the duration is not known, publish durationMs 0 and
     the card will show no scrubber rather than a wrong one.
  2. Is a path of the caller's choosing acceptable, or should SN-Launcher
     publish a path NCS-SMLauncher can hard-code? The environment variable
     covers the first case; a fixed path covers the second.

This is a proposal, not something either side has done yet. Nothing in
SN-Launcher depends on NCS-SMLauncher existing.

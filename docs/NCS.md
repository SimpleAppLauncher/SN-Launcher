# Music — driven by NCS-SMLauncher

The ef build's music page is a **remote control**, not a player. The library,
the decoding and the audio all live in [NCS-SMLauncher][ncs]; the tablet draws
the library and sends button presses back over the network.

That split is the point. A wall panel that owns the audio stops the music when
it restarts, and it has to fit a decoder and a library into 1–4 GB of e-waste.
A wall panel that is only a remote does neither — and the music keeps playing
when you swipe back to the clock.

[ncs]: https://github.com/SimpleAppLauncher/NCS-SMLauncher

## What it looks like

A feed of square artwork ("Quick picks"), the queue below it ("Up next"), and a
mini player pinned to the bottom. Tapping the mini player opens the full player:
large artwork, the timeline, the transport row, the volume.

The shape is the one every streaming app on a phone has settled on — the same
shape YouTube Music uses. The colours, the type and the icons are the
launcher's own; nothing here is Google's artwork, logo or branding, and the
page never calls itself YouTube Music.

![The music page](shots/music.png)

![The full player](shots/music-player.png)

Both are rendered from the widget with the bundled fonts, not drawn by hand:
`SN_CAPTURE=1 flutter test test/capture_music_page_test.dart --update-goldens`.
The test is skipped by default, because a golden file that has to match byte for
byte across machines fails for reasons that have nothing to do with the page.

## The protocol

HTTP, on whatever machine runs the player.

| Method | Path | |
| --- | --- | --- |
| `GET` | `/state` | The snapshot. Polled every two seconds. |
| `POST` | `/control` | `{"action": "...", "value": 0.5, "id": "..."}` |
| `GET` | `/browse` | Optional. The library. |
| `GET` | `/art/<id>.png` | Optional. Artwork bytes. |

### `/state`

```json
{
  "playing": true,
  "server": "NCS-SMLauncher",
  "positionMs": 61000,
  "durationMs": 240000,
  "volume": 0.8,
  "track": {
    "id": "track-1",
    "title": "Everything In Its Right Place",
    "artist": "Radiohead",
    "album": "Kid A",
    "durationMs": 240000,
    "artwork": "/art/track-1.png"
  },
  "queue": [
    {"id": "track-2", "title": "Kid A", "artist": "Radiohead",
     "durationMs": 250000}
  ]
}
```

`title` is the only field that must be non-empty. A track with no artist is an
album nobody tagged, not an error.

`artwork` may be a path or an absolute URL. A path is resolved against the
address the client actually reached, so a player behind a reverse proxy still
works.

### `/control`

| `action` | `value` | `id` |
| --- | --- | --- |
| `play` | — | optional: the track to play |
| `pause` | — | — |
| `next` | — | — |
| `previous` | — | — |
| `seek` | milliseconds | — |
| `volume` | 0.0–1.0 | — |
| `shuffle` | — | — |
| `repeat` | — | — |

`shuffle` and `repeat` are accepted by the server but **not drawn** by the
launcher. The snapshot carries no state for either, so a toggle could not show
whether it was on; the buttons go in when `/state` can say what they are doing.
The five that are drawn all have feedback in the snapshot: play and pause move
`playing`, next and previous move the track, seek moves `positionMs`, volume
comes back as `volume`.

Unknown actions must be accepted and ignored. A control surface that rejects
verbs it does not know breaks the day the other side learns a new one.

`play` with an `id` is the extension that makes the artwork grid work: without
it the launcher can start and stop what is playing but cannot choose what.

### Why polling and not SSE

The proposal included `GET /events` as a Server-Sent Events stream. The client
polls `/state` instead.

Two seconds is indistinguishable from a push on a wall display, and a poll
survives a server that implements half the contract — which, while the other
side is being rewritten, is the likely case. If `/events` lands later the client
can switch without the protocol changing; the snapshot is the same either way.

## Trying it without the real player

`tool/ncs_mock_server.py` speaks exactly this protocol with eight generated
tracks and generated artwork, so the page can be built and looked at before the
player exists.

```bash
python3 tool/ncs_mock_server.py --port 8737
```

It prints the address to type into the launcher:

```
NCS-SMLauncher mock player
  listening on http://0.0.0.0:8737
  enter this in the launcher:  http://192.168.1.20:8737
```

Nothing is downloaded and there are no dependencies — the artwork is drawn by
the script, so it is a test fixture rather than a queue of licensed images.

## Where the address is stored

`SettingKeys.ncsBaseUrl`, set from the page's connect card or its settings
dialog, and read on the first use of the client rather than at construction —
settings are not loaded yet at construction time.

## What is verified, and what is not

Verified:

- `test/ncs_client_test.dart` — the client against a **real loopback HTTP
  server**: state, control bodies, seek values, browse, a 500, a closed port,
  malformed JSON, and the position arithmetic between polls.
- `test/ncs_music_page_test.dart` — the page renders the track, the sections,
  the mini player, the player's name, the pause button sending `pause`, and the
  unreachable state keeping the address in the field.
- `tool/ncs_mock_server.py` — exercised with `curl`: state, a pause that reads
  back as paused, the library, and a valid 512×512 PNG.

Not verified:

- **The page has never been seen on the tablet.** Nobody has built the ef APK
  with it and swiped to it.
- The full player's layout at the tablet's real size — it is unit-tested at
  800×1340 but that is not the same as looking at it.
- The real NCS-SMLauncher, which is mid-rewrite and does not speak this yet.

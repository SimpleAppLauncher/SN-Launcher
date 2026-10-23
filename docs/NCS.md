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
on a portrait screen it stacks, and on the tablet's landscape panel the cover
sits on the left with the timeline, transport and volume beside it, so no
control is below the fold.

The shape is the one every streaming app has settled on — the same shape YouTube
Music uses. The colours, the type and the icons are the launcher's own; nothing
here is Google's artwork, logo or branding, and the page never calls itself
YouTube Music.

![The music page](shots/music.png)

![The full player](shots/music-player.png)

Both are photographs of the tablet (SM-X110, 1340×800), not mock-ups. The
capture test in `test/capture_music_page_test.dart` renders the same two views
to `build/shots` for working without the device; it is skipped by default, and
its covers are the gradient placeholder because the test binding does not decode
network images.

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

The body is sent with an explicit `Content-Length`. Dart chunks a request body
when it does not know the length, and a small server that reads only
`Content-Length` — `tool/ncs_mock_server.py` is one — then parses an empty body
and answers `400`. Every transport press was rejected that way until the device
made it visible; the client now sends the length, and the mock answers `204`.

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
dialog.

The client is constructed during the first frame, before the settings have come
off disk, so its saved address is adopted once `SettingsStore.load()` finishes
(`_restoreNcs` in `main.dart`). Before that, the value was being written and
never read: every launch opened the connect card again. Verified by force-
stopping the app on the tablet and watching it open straight into the live feed.

## What is verified, and what is not

Verified on the tablet — Samsung SM-X110, Android 15, 1340×800 landscape —
against `tool/ncs_mock_server.py` on the LAN:

- Connecting from the card with the keyboard's **Đi** key, with the Connect
  button fully above the keyboard while typing.
- The address surviving a force-stop: relaunch opens straight into the live feed.
- The feed: covers, the playing badge moving to the track after `play id=…`, the
  mini player, and scrolling to "Up next".
- Transport: pause, next and a grid tap each sent `POST /control`, the mock
  answered `204`, and `/state` read back what the page then showed.
- Seek and volume drags: 91 s → 182 s on a 240 s track, 0.75 → 0.275, both read
  back from the mock.
- The full player in landscape: cover left, controls right, volume on screen
  without scrolling.
- A frozen player: the feed and mini player stay, the chip turns amber and says
  "Reconnecting…", and returns to the player's name when it answers again.

Verified by tests:

- `test/ncs_client_test.dart` — the client against a **real loopback HTTP
  server**: state, control bodies (with a non-chunked `Content-Length`), seek
  values, browse, a 500, a closed port, malformed JSON, position arithmetic, and
  a refresh arriving during a poll.
- `test/ncs_music_page_test.dart` — the page at 1340×800 renders the track, the
  sections, the mini player, its cover URL, the player's name; pause sends
  `pause`; the card fits above a simulated keyboard; a missed poll keeps the
  feed and says "Reconnecting…"; an unreachable player keeps the address.
- `test/ncs_build_test.dart` — the music page is gated on `music` and
  `ncsPlayer`, and the reduced build has no hole in the carousel.

Not verified:

- **The real NCS-SMLauncher.** It does not speak this protocol yet; everything
  above is the mock.
- The first request after a long idle. On two freshly cleared installs the first
  connect attempt timed out and the card said "No player" until the poll two
  seconds later succeeded. The connect and response timeouts were raised from
  3/4 s to 6 s; after that, a third clean install reached the feed within three
  seconds with no error. One run is not a trend — watch for it.
- The artwork retry after a failed cover load (two attempts, then the gradient)
  is in the code and has not been forced on the device.
- A long session: memory, and the carousel keeping the page's poll alive.

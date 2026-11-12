# Status: what works, what does not, and what to do next

Written against the v0.3.0 release tree, plus the background-album and
Christmas-mode work that has landed since. **353 tests pass and six are
skipped**; `flutter analyze` is clean. The reduced and ef 0.3.0 APKs were built
and signature-verified, but ADB was offline during this release pass, so this
exact build was not installed on hardware. The Android now-playing strip,
external transport and live track replacement were verified earlier on the
Nokia T20 with Spotify and Notification access; the real installed-app
dock/drawer and live photo discovery were used in the T20 promo captures. Full
package-launch interaction and the time-based theme editor were not re-run on
hardware for 0.3.0. This file exists because the honest answer to "does it
work?" has been longer than a chat message should carry, and because the
previous answer to that question was wrong.

Everything below is graded against one standard, which is the only standard
that matters for a device sitting on a wall:

> **Verified** means it has been seen working on real hardware.

A passing test is not verification. A widget test proves a property; it cannot
prove that a person can see it. This project has now been bitten by that
distinction twice, and both times the thing that broke was invisible to the
whole test suite.

---

## 0.3.0 release assessment

- **Built:** six per-ABI APKs (reduced and ef, arm64-v8a/armeabi-v7a/x86_64).
  `versionName` is 0.3.0; the base `versionCode` is 9001, with the normal ABI
  split offsets 10001/11001/13001. All six use the release certificate
  `CN=SN-Launcher, OU=Android, O=SimpleAppLauncher, C=US`, SHA-256
  `94d75bcb19143281e16a98393b81f2467c3bd528632c696ffde8b3bdf4951804`.
- **Automated:** `flutter analyze` clean; **287 tests pass, 1 skipped**.
- **Hardware:** this exact 0.3.0 build was **not installed** in this pass because
  ADB was offline. Earlier T20 evidence covers the now-playing strip, transport
  and live track replacement, and the T20 promo captures show the real
  installed-app dock/drawer and live photo. Package launch and the time-based
  theme editor were not re-run on hardware for 0.3.0.
- **Still unverified:** the time-based theme schedule on hardware; the real
  NCS-SMLauncher and voice assistant; the EF-only LAN remote control on
  hardware (source complete, `flutter analyze` clean); store submission and
  data-safety review (not done).

---

## 1. Verified on hardware

| | Evidence |
| --- | --- |
| Clock face, date line | Screenshots at several times of day |
| Calendar page, with the date | Seen on device |
| To-do list — add, tick, delete | Typed "Buymilk", ticked it, survived a cold restart |
| Photo pool, 12 licence-verified images | Credits observed rendering and changing per photo |
| Theme switching, 5 themes | Seen on device |
| Show-seconds toggle | Observed ticking at 13:19:16 |
| Brightness | Works |
| Page carousel | ef 4 pages (home, digest, weather, music); reduced 2 (home, digest); the Home control page is off in both. Ef screenshots on SM-X110 and T20; reduced on the T20 |
| Weather page renders conditions | 21°, partly cloudy on the SM-X110 and T20; the T20 has no place photo because the place name still does not resolve (3a) |
| Music page (mock) | T20 ef release, SM-X110 ef release and SM-X110 profile: live feed over the LAN; pause/next read back from the mock on the T20 and profile; the T20's `adb reverse` was removed and it kept polling |
| Release builds | T20: both variants installed and exercised; SM-X110: ef installed and exercised; applicationIds checked; ef 4 pages, reduced 2 |
| Release idle cost | T20: home 2.6%, digest 2.3%, weather 3.3%, music 2.6%, reduced digest 0.3% |
| Release cold start | SM-X110 548 ms; T20 509–603 ms after first install; first T20 launch 3.3 s ef / 1.2 s reduced |
| Release memory | T20 PSS 102 MB ef / 81 MB reduced; SM-X110 140 MB ef |
| Background albums — Landscape / Cars / Fernando Alonso | macOS desktop release build: each album fetched a photograph from the Commons pool, captioned it with the album name and the photographer's name, and cached it in its own folder. Landscape fetched a live-discovered photograph, Cars a Renault F1 lineup, Alonso the 2012 Italian GP press conference |
| Christmas mode | macOS desktop release build: snow falling over the photograph, with the album caption and the clock still legible |

## 2. Built, tested, never seen on hardware

These pass their tests and have never been looked at by a person. The three
rows at the bottom are the exception: they have been seen on the macOS
desktop release build, and have never been seen on an Android tablet.

| | What the test proves | What nobody has checked |
| --- | --- | --- |
| Clock zoom 1.0–1.2 | The date and clock rectangles do not overlap, measured | How it actually looks |
| Spring motion | A thrown carousel arrives sooner than an eased one; a critically damped page spring does not overshoot | How it actually feels |
| Ad blocking (old WebView) | 8 URL cases pass in a node harness against the real 23-host list | The panel is on the disabled Home control page; neither shipped build opens it |
| Installed-app registry | `AppCatalog` adopts packages, labels and icon bytes; a pixel test proves the badge paints the bytes rather than a glyph; a 1280×800 render shows the grid and search field | Whether `queryIntentActivities` + `loadIcon` returns the expected list on the T20 or SM-X110, whether package launches work, and whether Android 11+ visibility behaves as declared |
| Labelled app row + grabber hit area | Renders at 1280×800 without overflow; the handle now has a 48 dp opaque target | Whether a thumb finds it, and whether tapping it opens the sheet without the drag listener swallowing the tap |
| Android now-playing | `DeviceMediaWatcher` maps mocked media sessions, permission state and pause/play; tests prove capability-gated external transport, that a new external song replaces the old one without a restart, and that unsupported controls are absent; the base manifest declares the notification-listener service | Whether Notification access can be granted on the T20/SM-X110, whether Spotify/SoundCloud/podcast/PiP accept play/pause/skip through `MediaController`, and whether artwork and titles survive background playback |
| Live photo discovery in the normal build | The feature-flag test now proves `photoDiscovery` is on; the licence filter and discovery pool have unit tests | Whether the normal build fetches and rotates a fresh Commons photo on the tablet, and whether that changes idle network/battery behaviour |
| Time-based theme schedule | Override windows resolve correctly for normal and past-midnight ranges; malformed entries are dropped; the schedule survives a controller restart; the Settings editor appears only while the theme is dynamic | Whether the Appearance editor fits and the palette visibly switches on the T20. Hardware smoke was skipped because ADB was offline |
| **Background albums — Landscape / Cars / Fernando Alonso** | 88 pool entries verified live against the Commons API (file exists, licence redistributable, thumbnail fetchable); each album bundles one hero with its sidecar JSON; the service caches per album; the Settings picker renders without overflow at 1:1, 4:3, 3:4 and 9:16; the reduced build's flag test proves `themePicker` is on | Whether the picker looks right on the tablet, and whether the downloaded photographs arrive and rotate there. Seen on macOS: the albums fetch, caption and credit correctly |
| **Christmas mode** | The palette passes the contrast check and reports itself as a night palette; the automatic window is closed on 30 Nov 23:59, open from 1 Dec 00:00 through 6 Jan 23:59, and closed from 7 Jan 00:00; the mode switch overrides a pinned theme; the snow switch is independent of the mode; the setting survives a restart; the snow paints without overflow at all 11 aspect shapes and is byte-identical across two frames when it is not animating | Whether the snow reads as snow rather than as noise on a 2000×1200 panel, and whether the Christmas palette is legible over a bright photograph. Seen on macOS: the snow falls over the photograph and the caption stays legible |
| **Live photo discovery (bug fix)** | The candidate filter used to test the file extension by asking whether the URL *ended with* `.jpg`; Commons now appends `?utm_source=…&utm_content=original`, so **every** discovered candidate was being rejected and discovery always returned nothing. The fix strips the query string. A test uses a real API payload with the tracking string, one without it, and a `.webm` with parameters that must still be refused | Whether a fresh Commons photograph now actually arrives and rotates on the tablet — the path that was silently dead before this fix. Seen on macOS: the Landscape album fetched a fresh discovered photograph ("Barranco Valle de la Fuente - Fuerteventura", H. Zell) and cached it |
| Tizen TV TPK | It builds for `profile tv`; the Samsung distributor certificate names the TV's DUID | Everything. It has never been installed or launched — sdb cannot open the device |

## 3. Known broken

### 3a. The weather place name has never once appeared

Symptom: the weather page shows a temperature and a condition, and no place
name and no "Location from this device's Wi-Fi" line. Seen again on the T20
release (23 Oct 2026): 21°, partly cloudy, no place name and no place photo.

What is known: the permission request path is present on both sides — Dart
calls `resolve(askPermission: true)`, and the Kotlin bridge returns
`reason: "permission"` when the grant is missing, which is exactly what the
Dart side watches for. The weather *does* load, and `WeatherService` only
fetches when it has been handed real coordinates, so a place object was
resolved and handed over.

Leading hypothesis: `GeoPlace` has a `name` that is only populated by the
IP-geocode fallback, and `displayName` falls back to coordinates — so a
device-sourced place should at least render as `-33.86, 151.21`. It renders as
nothing, which means the widget is not receiving the place at all, or
`_onLocationChanged` is not rebuilding the page. **This is a hypothesis and
instrumentation is in place to settle it. It is not fixed.**

There is a real design gap underneath it regardless: there is no reverse
geocoding. The device path yields coordinates with no name; the IP path yields
a name; the device path runs first and wins, so the name is never fetched. That
will need fixing whatever the immediate cause turns out to be.

### 3b. The ad blocker cannot work as built

Not a bug — a ceiling. Page-side blocking of `fetch` and `XMLHttpRequest`
only catches requests the page makes *in JavaScript*. YouTube serves its ads
through `<script src>` tags, `<img>` beacons and the `<video>` element. Those
are element loads, and no page-side patching can intercept them. It removes
some ad traffic and none of the ad scripts, which is indistinguishable from
"nothing happened".

Only a native `WebViewClient.shouldInterceptRequest` can block them, and
`webview_flutter` 4.x does not expose one.

### 3c. No shipped page plays audio

The old music panel was a full-screen WebView on the Home control page, and the
radio card's Media3 `PlaybackService` lives in the same disabled corner. Both
shipped configs disable that page, and the ef music page is a remote for
NCS-SMLauncher, so no page in either build plays audio or exposes a media
session. Background playback is the NCS player's job. The old WebView was not an
answer: on Android its renderer is suspended after roughly five minutes in the
background *even with a foreground service running*, and audio stops when the
screen locks. The launcher-side player code exists as that radio card's
service, but it is unreachable while `homeControl` is off.

## 4. Not built at all

- Native audio player, MediaSession, lock-screen controls in a shipped page
  (the radio card's `PlaybackService` exists on the disabled Home control page)
- Jellyfin integration
- Weather page redesign — the "at this time there is rain" treatment with a
  condition-appropriate background image
- Reverse geocoding
- A runtime location picker
- Any automated test that runs on a device; CI only builds the desktop targets
- A 72-hour soak on the T20, and the long-session memory/poll behaviour
- A hardware smoke run of the exact 0.3.0 APKs; the release is signed, but ADB
  was offline during the release pass
- Desktop targets — built in CI, never run here; the Linux build has never been launched

---

## 5. What to do, in this order

### Current, 26 Oct 2026

1. **Verify the installed-app drawer on both tablets.** This is the change that
   just landed and the only thing allowed to happen before new work. Install
   both variants, open the drawer, confirm the icons are the apps' own, tap a
   few, use search, then tap the grabber with a thumb. If the list is empty,
   read `adb logcat` for the package-manager query before changing the code.
2. **Run the Linux desktop build.** It has never been launched; the CI
   artefact is not a run. Do this on the machine that will host it. On desktop
   the catalog has no package manager, so it deliberately falls back to the
   built-in action set.
3. **Get the real NCS-SMLauncher contract.** The music page is verified against
   the mock only. Ask the player's author for the port, endpoints, library
   model and playback language, then test the page against the real server on
   the LAN.
4. **Soak the T20.** Leave the ef release on the home/weather/music pages for
   72 hours and watch PSS, the poll, and the carousel; then repeat the memory
   check. The current release PSS is 102 MB ef / 81 MB reduced. Re-measure
   after the app catalog, which keeps one 144 px PNG per installed app.
5. **Settle the weather place name (3a).** It is still the one bug that shows
   on the wall: conditions without a place.
6. **Release signing.** A proper keystore, so upgrades do not require an
   uninstall.

### Earlier plan (kept for the record; the native-player step is superseded by the NCS remote)

### Step 1 — Settle the location bug. It is the only thing here that is both broken and cheap.

Read the instrumentation on the device. Fix the cause. Verify a place name
actually appears. This is maybe an hour and it removes a bug that has shipped
broken and been documented as working.

### Step 2 — Verify what is already built.

Clock zoom at 1.0, 1.1 and 1.2 on the real screen. The carousel flicked hard
enough to feel the spring. The sheet thrown and caught. Twenty minutes, and it
converts two "tested" rows into two "verified" rows.

Nothing new gets built before this is done. The rule in `AGENTS.md` is that no
feature is added while something is unverified, and that rule exists because it
has been broken repeatedly.

### Step 3 — Decide the ad blocker, because it forces the music decision.

Three real options:

1. **Remove the WebView, build the native player.** The ad problem disappears
   with the WebView, and background music — the thing that was actually asked
   for — arrives. Also deletes roughly 300 MB of browser engine from a device
   that has about 2 GB to spare.
2. **Write a platform view with a native interceptor.** Keeps the WebView and
   makes the block real. More engineering, and it leaves the background-audio
   problem exactly where it is.
3. **Stop claiming it blocks ads**, and document what it actually does.

**Recommended: option 1.** It is the only one that solves two problems by
removing a cause, and it is the version that delivers the original request.

### Step 4 — Weather page redesign.

Contained, no external dependency, and it is a real ask. It goes *after* the
above because it is a new feature and there are still broken ones.

### Step 5 — Native player.

Verify it first against a public radio stream, which needs no server and can
be tested today. Background playback, the notification, and the lock-screen
controls are all provable without Jellyfin.

### Step 6 — Jellyfin.

Blocked until the server is back. Built against the documented HTTP API with
fixtures; the client is straightforward. **Do not** lift Jellyfin's client
source into this repository — write against the API.

### Step 7 — The Nest fidelity sweep.

Measure element positions from photographs of a real Hub and build metrics as
ratios of display width. Honest label: *measured from photographs, roughly ±3%*.
There is no published Nest specification — corner radii, icon sizes, padding
and type sizes have never been published by anyone — so "pixel-accurate" is not
achievable and should not be claimed again.

---

## 6. The honest ratio

At the time of writing: both older release variants are built, installed and
hardware-verified on the Nokia T20; the ef is also verified on the SM-X110. The
Home control page is off in both. The music page is verified against the mock
only; the real NCS-SMLauncher, the Linux desktop build, and a 72-hour soak are
still unverified.

The installed-app UI is a separate ratio: five pieces built (package query,
real icon rasterisation, package launch, labelled dock, searchable adaptive
drawer), **zero verified on hardware**, one render-harness pass and one pixel
test. Do not call those icons real until they have been seen on a tablet.

The newest work is a third ratio. **Built: three background albums (Landscape,
Cars, Fernando Alonso), one Christmas mode with a seasonal palette and falling
snow, and one fixed bug in live photo discovery. Verified: on the macOS
desktop release build, on all three albums and in both Christmas states;
zero on Android hardware.** Everything is covered by automated tests — 88 pool
entries checked against the live Commons API, the December window's four
boundary instants, the snow byte-identical across two frames — and the
macOS release build was run and looked at: each album fetched its
photograph, captioned it with the album name and the photographer's name,
and the snow fell over the picture. Both Android release variants also build
with all of this in them — the applicationIds were checked and are
`dev.snlauncher.snlauncher` and `dev.snlauncher.snlauncher.ef` — but neither
has been installed. The owner has not yet installed an Android build
containing any of it. Until that happens, the honest
description of the albums is "they work on the macOS desktop build", not
"the albums work on a tablet".

The number that matters is not the first one. It is that **three broken things
shipped in v0.1.2 and v0.1.3 while the test suite reported all green** — because
the tests asserted on state variables rather than on what the screen renders,
and because a page nobody could reach still reported itself as selected. The
current rule is the same one: a passing test is not a device check.

Until a device check runs after every change, that gap stays open.

---

## 7. The TV target

The Samsung `QA55Q60CAKXXV` is a target, not a third version. The TPK is built
from the same source and the same `SN_FEATURES` switch as the tablets, and both
configs keep `homeControl: false`.

State on 24–25 Oct 2026:

- TPK built: `build/tizen/tpk/com.giathinh.snlauncher.tv-1.0.0.tpk`.
- Signed with a Samsung author certificate and a Samsung distributor
  certificate whose device-id extension is
  `UUID:65F128FF-CD11-4D1A-AECF-491A2171D972`. The chain is Samsung VD Author
  CA / VD DEVELOPER Public CA, not the bundled public distributor.
- **Never installed.** On 25 Oct 2026 the TV was on (`PowerState: on`,
  developerMode 1, host IP `192.168.1.123`), but `26101` still accepts TCP and
  resets the sdb handshake. A full TCP 1–65535 scan found 15 open ports. None
  of the others speaks sdb; `26101` remains the only sdb endpoint. The daemon
  starts only after a hard power cycle, which is a physical step. The install
  command, the scan tool and the exact TV-side steps are in `docs/TIZEN.md`.

Because it has not run, none of the TV claims exist yet: 16:9 layout, D-pad
focus, remote Back, ef/reduced gating, the Tizen WebView, or the NCS feed. A
1920×1080 render from the test harness fits without overflow, but it is the
tablet shell: a drag handle, one row of icons, and no focus ring. The current
shell also still uses its tablet focus model: the root `Focus` claims
Left/Right for page changes, so horizontal traversal inside a page is not
implemented. That is the next code change, and it should be made with the TV
in front of us.

The TV does not change the honest ratio: it is a third **target**, not a third
build. There are still exactly two versions.


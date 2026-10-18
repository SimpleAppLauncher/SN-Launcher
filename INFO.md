# INFO.md — the technical record

Everything technical lives here. The [README](README.md) is the human-facing
summary; this is the part that explains *how*, *how well*, and *what is
wrong*.

---

## 0. The elephant in the room: attribution

### `giathinh` is not my account, and it was never a machine quirk

It is a **real, separate GitHub account** — id `57561631`, created 2019-11-09.
Mine is `Giathinh1234` — id `125528059`, created 2023-02-16, display name
"Thinh". Different account ids, different people.

**The name was put there by the agent that built this repository.** Not by me,
and not by any git configuration on the machine. The global git identity here
is `Gia Thịnh <giathinhbui0310@gmail.com>` and the repository's local identity
is `Giathinh1234 <Giathinh1234@users.noreply.github.com>`. There has never
been a configured identity called `giathinh` — the only occurrence of that
string in `~/.gitconfig` is inside the email address. The literal was almost
certainly scraped from the operating system's username, `/Users/giathinh`, and
written straight into a commit's author field. GitHub then matched it to that
stranger's account by email, and the repository listed **somebody else's
account as a contributor**.

There is one check that settles it beyond argument: the account was created in
**November 2019**. I was not writing code then, let alone anything on GitHub.
So it could not have been me, and it was not a configuration accident. It was
an agent writing the wrong name into a commit — my mistake, recorded here so
it cannot be quietly forgotten.

**That stranger did nothing.** They never pushed here, never opened a pull
request, and have no access to the repository. The work was mine; only the
*label* on it was wrong. The rewrite corrected a label — it did not remove
anybody's work, which is worth saying plainly because the earlier wording of
this file implied the opposite.

### This was built with OpenCode, not Claude Code

Worth stating outright, because a reader who sees "Nest Hub clone" and an
agent-written codebase will reach for the wrong conclusion:

> **Everything in this repository was produced with
> [OpenCode](https://opencode.ai). It was not built with Claude Code, and no
> part of it came from Anthropic.** There is no `Co-Authored-By: Claude`
> trailer anywhere in the history, and GitHub's contributor list for this
> repository contains exactly one account.

The OpenCode references already in the repository — `docs/MODELS.md` for the
model routing, `tool/chatlog.py` for the session transcripts — are
deliberate, so the tool is unambiguous without this line. The line is here as
well because "an agent wrote this" is easy to assume and "Claude wrote this" is
easier still, and a reader should not have to guess which.

### Verified rather than asserted

| | |
| --- | --- |
| Commits in the history | 31 — every author and committer `Giathinh1234 <Giathinh1234@users.noreply.github.com>` |
| GitHub's contributor list | `Giathinh1234`, 31 commits, and nobody else |
| `giathinh`'s contributions to this repo | none |
| Co-author trailers anywhere in the history | none |
| Tag objects (`v0.1.0`, `v0.1.1`) | both taggered `Giathinh1234` |

### The rule that came out of it

Never write an identity into this repository that is not mine, and never
attribute work to a tool that did not produce it. Both mistakes are now
written into `AGENTS.md` so that a future session inherits them instead of
rediscovering them.


| | |
| --- | --- |
| Repo | `github.com/Giathinh1234/SN-Launcher` — now owned by the `SimpleAppLauncher` org; the old URL redirects and keeps working |
| Commit identity | `Giathinh1234 <Giathinh1234@users.noreply.github.com>` |
| History | rewritten — no commit names any other account |

The rewrite was done with `filter-branch`, not `git filter-repo`, because
`filter-repo` is broken on this machine: it crashes, and its `--mailmap` flag
silently does nothing. `filter-branch` copies tag objects verbatim, so the
`v0.1.0` tag object was re-created by hand to fix its tagger.

### Licences of the assets

| Asset | Licence | Note |
| --- | --- | --- |
| Google Sans | SIL OFL 1.1 | Bundled genuinely, not approximated. The single biggest reason the clock reads as "Google". |
| Poppins | SIL OFL 1.1 | Weight 300 only, for the "Timeless Light" clock face. |
| Material Symbols Rounded | **Apache 2.0** | Not OFL — easy to get wrong when every other asset here is OFL. |
| The bundled photograph | Public domain (US National Park Service) | *Cub Lake at dawn* by **Debra Miller**. |
| The rotating photo pool | PD / CC0 / CC-BY only | No SA, NC or ND. Share-alike is not installable by a launcher. |
| Brand marks (Spotify, Netflix, Pandora, YouTube) | Drawn as paths | Not Google's Material symbols — substituting one approximation of a logo with another is strictly worse than either. |

---

## 1. How faithful is it, really?

The project's founding claim was "pixel-accurate to the real Nest — measure,
don't guess". That was **too strong**, and here is the honest accounting.

### What was measured

Google has never published a single dp metric, font size, colour value or
animation duration for the Nest launcher. So the constants in
`lib/src/theme/nest_metrics.dart` were *measured*, by this process:

1. Real photographs of a Nest Hub and a Nest Hub Max were downloaded.
2. The four display corners were found in each photo.
3. A homography was solved and the photo rectified onto the device's flat native
   canvas — `1024x600` for the Hub, `1280x800` for the Max.
4. Pixel runs for each glyph, icon and hairline were read off the rectified
   image with NumPy.

Rectified references live in `refs/`.

| Element | Measured on device | In this build |
| --- | --- | --- |
| Clock digit block | 61 px tall, y 461–521 | **61 px, y 461–521** |
| `"09:45"` run width | 195 px, x 69–264 | **194 px, x 69–262** |
| Date line | 120 px wide, cap top y 422 | **123 px, y 424** |
| Temperature | 42 px wide, 26 px cap | **42 px, 26 px** |
| Album title | 119 px wide, right edge x 973 | **117 px, x 970** |
| Drag handle | 41 x 5.6 px | matches |
| Sheet top | 49.6 % of screen height | matches |
| App badge | 100 px across (Max) | matches |
| App row pitch | ~148 px (Max) | **147 px** |
| Sheet surface colour | `#EFEDE6` | matches |

Max residual error is **9 px on a 1280-wide canvas (0.7 %)**.

Two things the naive approach gets wrong, both of which cost real time:

**The two devices are not the same shape.** The Nest Hub is 1024x600 (1.707) and
the Hub Max is 1280x800 (**1.600**). They share a 1.25x width scale but a 1.333x
height scale. Copying the Max's pixel offsets onto the Hub's canvas with one
uniform factor lands the sheet rows about 24px too low. Everything inside the
bottom sheet is therefore positioned as a **fraction of the sheet's own height**,
which is stable across both devices and across any odd-shaped screen.

**Google Sans sets its digits far wider than the Nest's clock.** Its digit
advance is 0.643 em, rendering `09:45` at 220px where the device measures
**195px**. The tracking has to be pulled in (`letterSpacing: -2.15`) to match.

### What is only eyeballed

The codebase carries **36 constants, 10 of them marked measured**, and
`tool/verify.py` asserts exactly **two** things: the clock block and the badge
pitch. Everything else — the sheet's internal spacing, the digest cards, the
settings page, the assistant lightbar — was looked at and adjusted by eye.

### Where it is knowingly *not* faithful

Two structural mismatches, both confirmed against the reference photograph in
`refs/Nest-Hub-app-launcher-1.png`:

**1. Navigation is a carousel; the device uses layers.** The real Nest Hub is
ambient photo → a **sheet that slides up over the photo** → a full app grid →
the Assistant. There is no horizontal page carousel. This project has
`ShellPage { home, digest, homeControl, discover }` and swipes sideways between
them. `digest` and `homeControl` are **not Nest surfaces at all** — they are
inventions here.

**2. Two of the seven quick-settings buttons are wrong.**

| # | Real device | This project | |
| --- | --- | --- | --- |
| 1 | ☀ brightness | brightness | ✓ |
| 2 | 🔊 volume | volume | ✓ |
| 3 | ▣ camera | camera | ✓ |
| 4 | **— microphone mute** | ☀ theme | ✗ |
| 5 | **⏰ timer** | ✨ digest | ✗ |
| 6 | 💬 feedback | feedback | ✓ |
| 7 | ⚙ settings | settings | ✓ |

The **count** (7) and the **pitch** (118px) are measured. Two of the **glyphs**
are not what the device shows.

---

## 2. Architecture

```
lib/
  main.dart                          entry: flags, orientation lock, immersive mode
  src/
    theme/
      nest_metrics.dart              every measured constant, design-canonical
      ambient_palette.dart           five themes + 24h time-of-day keyframes
      nest_type.dart                 Google Sans type scale
      nest_theme.dart                Material 3 ColorScheme from the palette
      nest_icons.dart                GENERATED by tool/build_icons.py
    models/
      nest_action.dart               21 "Actions on Google" + the quick-settings row
      photo_credit.dart              licence metadata for the bundled photograph
    services/
      feature_flags.dart             which features this build has
      clock_service.dart             aligned, minute-resolution ticking
      weather_service.dart           Open-Meteo, no key, degrades offline
      calendar_service.dart          CalendarContract feed, permission-aware
      platform_bridge.dart           typed MethodChannel wrapper
      settings_store.dart            tiny persistence, no plugin
      photo_frame_service.dart       rotation, licence gate, 12-entry pool
      assistant_service.dart         local intents, then Home Assistant / Gemini
      speech_to_text.dart            Android SpeechRecognizer
      action_launcher.dart           Android intents
    state/shell_controller.dart      pages, sheet, theme, brightness, volume
    widgets/
      ambient_background.dart        one-pass ambient gradient + drag handle
      nest_glyphs.dart               vector icon painters
      clock_block.dart               date / clock / weather / album title
      launcher_sheet.dart            app row + quick settings
      app_drawer.dart                six-column "See all" grid
      assistant_lightbar.dart        rainbow bar, replaces the deleted four-dot orb
    screens/nest_shell.dart          gesture layer and z-order
android/app/src/main/kotlin/dev/snlauncher/snlauncher/
      PlatformBridge.kt              brightness, volume, camera, calendar, media
      SpeechBridge.kt                TextToSpeech, voice enumeration
      SpeechRecognizerBridge.kt      microphone capture
      LightSensorBridge.kt           ambient light
      SettingsBridge.kt              SharedPreferences, 60 lines
```

---

## 3. Rendering: what runs on the GPU and what does not

**GPU does everything spatial.** Rasterisation and compositing run on Impeller
over Vulkan — every gradient, glyph path, badge and the sheet itself. The
ambient background is one `CustomPaint`; the launcher sheet is a
`RepaintBoundary` so it rasterises once and is then only blitted while it
slides. Measured GPU memory on the T20 is **564 KB**.

**CPU does everything blocking.** Anything that can stall — a socket read, a
JSON decode — runs on a worker isolate, never the UI thread:

```dart
// top-level, deliberately: inside a method the AOT compiler folds `this` into
// the closure context and Isolate.run refuses to send it.
Future<_WeatherReading?> _fetchOnWorker(double lat, double lon) =>
    Isolate.run(() => _fetchAndParse(lat: lat, lon: lon));
```

Frame *cost* stays on the UI thread where it belongs: layout, hit testing and
the gesture state machine.

**The GPU path can be swapped at build time.** Some older or badly-finned
Mali/Adreno drivers misbehave under Vulkan, and there the engine's Skia/OpenGL
backend is the reliable one:

```bash
flutter build apk --release -PenableImpeller=false
```

The switch is a Gradle property (`enableImpeller` in `android/gradle.properties`)
resolved into a manifest placeholder. Flutter is deprecating this escape hatch,
so treat it as a compatibility valve rather than a long-term strategy.

**Frame timing is measurable on-device**, which matters because `dumpsys gfxinfo`
reports zero frames for any Flutter app (Flutter bypasses Android's HWUI
pipeline) and SurfaceFlinger cannot sample a BLAST-backed surface:

```bash
flutter build apk --release --dart-define=PERF_OVERLAY=true
```

Adds a corner readout of average/worst frame cost and a jank count. Off by
default.

### Running on weak hardware

This is a 1–4 GB device target, so the architecture is built around cost.

**Vector icons, not PNGs.** A PNG icon set would cost several MB of decoded
texture resident on the GPU, which is precisely what a 1 GB tablet cannot
spare — and it would be blurry on a 4K monitor.

**One paint pass for the background.** The ambient gradient plus its centre
bloom is a single `CustomPainter`. A stack of translucent containers would
force an offscreen compositing layer each.

**Minute-resolution clock by default.** `ClockService` only wakes on the minute
boundary unless seconds are enabled, and it aligns to the wall clock so digits
never stutter. The clock block sits behind its own `RepaintBoundary`, so a tick
repaints ~200 px² instead of the whole screen.

**Layer hygiene.** The drawer sets `addRepaintBoundaries: false` and
`addAutomaticKeepAlives: false` — 24 cells do not each need a retained layer.

**No blur, ever.** `BackdropFilter` is the single most expensive primitive in
Flutter on low-end GPUs. The real Nest does not blur its sheet either; it uses
a flat scrim.

**Right-sized heap.** `android:largeHeap="false"` plus conservative Gradle JVM
args keeps the app inside a small memory envelope. `minSdk` is 21, which covers
essentially every e-waste Android tablet still in circulation.

---

## 4. Measured on real hardware

Two devices, both squarely inside the e-waste target.

**Nokia T20** — Android 13, 3.8 GB RAM, UNISOC T610 / Mali-G52, 2000x1200.

| | measured | expected |
| --- | --- | --- |
| Clock block, left edge | 135 px | 135 px |
| Clock block, digit height | 116 px | 119 px |
| App badge pitch (sheet + drawer) | 118.0 px | 118 px |
| Sheet app-row centre | 810 px | 811 px |
| Sheet top edge | 605 px | 604 px |
| Frame cost, idle | 10.9 ms | ≤ 16.7 ms |
| Frame cost, sheet animation | 11.0 ms | ≤ 16.7 ms |
| Total PSS | 65 MB | — |
| **GPU memory** | **564 KB** | — |
| Cold start | 0.8 s | — |

**Samsung Galaxy Tab A7 Lite (SM-X110)** — Android 15, 3.7 GB RAM, MediaTek
MT6789 / Helio G80, 800x1340 **portrait**.

| | measured |
| --- | --- |
| Cold start | **362–405 ms** (`am start -W`) |
| Clock block, left edge | 135 px (matches) |
| App badge pitch | 118.0 px (matches) |

The GPU figure is worth keeping: it is the payoff for drawing every icon as
vector paths. A PNG icon set would have cost several MB of resident texture.

### Four bugs only real hardware could surface

1. **First-frame MediaQuery.** The first frame reported a smaller size than the
   settled one, and `late final` locked the shell to the wrong scale for its
   whole life — everything rendered 5% small.
2. **Animation controllers weren't in the listen list.** The shell listened to
   `ShellController` (a `ChangeNotifier`) but the sheet and carousel animate
   *separate* `AnimationController`s, which notify their own listeners. The UI
   only repainted by accident whenever the clock ticked.
3. **Bottom-edge swipes arrive as cancels.** Android claims a swipe that starts
   on the very bottom edge for its own gesture. Without settling on cancel the
   sheet stuck at ~65% open.
4. **Immutable frame cost.** The sheet animation ran at 17.2 ms — over budget.
   Every frame of the drag was rebuilding the clock, the carousel and the whole
   bottom sheet.

### A fifth, found by looking at a screenshot

**The Dynamic theme produced unreadable cards.** The digest page at 07:43 was
illegible — "Weather", "Music" and every body line washed out through the
middle of a pale peach gradient, while cards at the right edge were fine. The
tell was that it varied across the page: the card fill is translucent, so
contrast depends on what is behind it.

The cause was not bad interpolation. `hasReadableInk` existed, was documented as
the thing preventing exactly this, and had **zero callers**. Nothing checked
the result of `lerpPalette`, and `adaptToAmbientLight` moves the background
toward white or near-black while leaving every ink colour untouched — so the
ambient light sensor could slide a theme's background past its own text.

Fixed by walking the ink toward the extreme that contrasts with the surface.
Four hours out of 144 land at 4.42:1 with ink already at an extreme, where
moving ink cannot help, so those push the card fill away from the ink instead.
`at()` now returns **0 of 144 steps** failing, and Day and Night are
bit-for-bit unchanged.

---

## 5. The quick-settings row

Four of the seven buttons used to be theatre. Brightness mutated a private field
that nothing read; camera printed a toast reading "Camera toggled" and settings
printed "Settings" — claiming an action neither had performed, which is worse
than doing nothing because the user believes the device responded.

Every button is now wired to a real platform capability over one MethodChannel
(`dev.snlauncher/platform`), implemented in `PlatformBridge.kt`:

| Button | What it does | Verified on device |
| --- | --- | --- |
| Brightness | `window.attributes.screenBrightness` | panel mean luma 206 → 75 |
| Volume | `AudioManager.setStreamVolume(STREAM_MUSIC, …)` | `dumpsys audio` logs `setStreamVolume` from this package |
| Camera | `ACTION_IMAGE_CAPTURE`, falling back through other camera intents | foreground became `com.android.camera2/.CaptureActivity` |
| Theme | Cycles the themes, persisted | survives a cold restart |
| Digest | Closes the sheet, then opens the digest | sheet luma changed |
| Feedback | Opens the Nest support page | foreground became Chrome |
| Settings | Pushes the app's own settings page | — |

`tool/test_dock.sh` runs this table against a connected device. The one rule
the implementation follows: **never report an action that did not happen.** If
the platform refuses, the toast names the failure.

Two details worth keeping if you extend it:

* The Dart setters update local state *first* and push to the platform
  fire-and-forget. Awaiting the channel inside a drag handler makes the
  brightness arc stutter. The platform's answer is then reconciled back, because
  Android quantises to its own steps.
* `WRITE_SETTINGS` is deliberately **not** declared. The system brightness write
  degrades gracefully; the window brightness needs no permission at all.

---

## 6. Themes

Five, selectable from the digest page, the settings page, or by tapping the
theme button.

| | |
| --- | --- |
| **Sun** (Dynamic) | Follows the clock — the 24-keyframe Ambient EQ ramp, continuously interpolated. Beta only. |
| **White** | Flat paper white |
| **Day** | The Nest's measured daylight paper (238, 234, 228) with a cool cast |
| **Afternoon** | Warmer and lower contrast |
| **Night** | Soft blue-black |

**The dark themes are lighter.** The old night palette ran down to `#070A14`. On
an OLED-less e-waste LCD that does not read as "dark" — it reads as *off*, and
the user assumes the device has hung. The floor is now `#121826`.

**A pinned theme is flat and does not drift.** Someone who pinned White asked
for white. A wall display that changes colour while someone is reading it is
worse than one that is consistently dull. The bloom is suppressed on flat
palettes — a cream hotspot across a white background reads as dirt.

Persistence is a 60-line `SettingsBridge.kt` over `SharedPreferences` rather
than the `shared_preferences` plugin, because this project's Android build is
already fragile (AGP shells out to `sdkmanager` during configuration, which is
why the Gradle configuration cache has to stay off) and one more plugin is one
more thing to go wrong for the sake of a dozen strings.

---

## 7. Icons: Google's, not ours

The launcher grid used to be 31 hand-plotted `CustomPainter` paths. The stroke
weight was uniformly 4.2% of the box with round caps, which is no real design
system's optical weight, and that mismatch is most of what made it read as
generic Android.

They are now Google's own Material Symbols, subsetted by `tool/build_icons.py`:

* **15.2 MB → 35 KB.** The upstream variable font carries four axes (FILL,
  GRAD, opsz, wght) that Flutter's `IconData` cannot address, so three of them
  are dead weight. The build subsets to the 172 glyphs actually used and freezes
  the axes to one static instance. Flutter then tree-shakes the result to 7 KB.
* **Codepoints come from Google's authoritative `.codepoints` file**, never
  guessed, and are cross-checked against the subset's own cmap before
  `nest_icons.dart` is written. A wrong codepoint renders as the wrong icon or
  a blank box and neither is obvious until you look at it.
* **Licence is Apache 2.0**, not OFL.

---

## 8. The photo frame rotates

The background changes every 10 minutes. Controls are on the digest page:
**Rotate** on/off, **Next now**, and 5 / 10 / 30 / 60 min / 6h.

Four constraints shaped it, all from the hardware it has to survive:

* **The bundled photograph paints at launch.** Anything downloaded is a later
  upgrade, so cold start never waits on the network.
* **`FileImage`, not `MemoryImage(File.readAsBytesSync())`.** Reading the file
  inside `build()` defeats the image cache and costs a full JPEG decode per
  frame on a UNISOC.
* **The API is asked for a 1600px thumbnail**, which is already the right size.
  Re-encoding would only convert a 300 KB JPEG into a 2 MB PNG — `dart:ui` has
  no JPEG encoder.
* **Plain `dart:io` HttpClient.** One less dependency on a 1 GB tablet.

### The pool is verified, not remembered

The first version hand-wrote twelve Wikimedia Commons filenames from memory.
**Four of them resolved.** Five were 404 and one was CC BY-SA — share-alike,
which a launcher may not install — so the rotation would have silently skipped
most of its own pool, every cycle, forever.

It was rebuilt properly: search Commons, keep only PD / CC0 / CC-BY with no
SA/NC/ND, download the candidates, and **look at all thirty**. Rejected a
satellite map with baked-in labels, two paintings, one carrying a visible
gallery watermark, one containing people, and the washed-out and over-saturated
strays.

`tool/verify_photo_pool.py` confirms every entry still resolves and is still
licence-clean against the live API. It exits non-zero, so it belongs in CI.

This is a deliberate choice over "fetch something random". A photo frame on a
wall is looked at constantly; a random image search will eventually put a
portrait, a chart, or a screenshot of someone's desktop on it.

### Attribution on screen

The photographer's name is rendered on screen next to "Recent highlights" —
which the licence and plain decency both ask for. Commons' `Artist` field for
the bundled file reads "NPS Natural Resources", the owning agency rather than
the person who took the photograph, so the fetcher prefers the real name. The
rotating pool's credit updates with the photograph; it is not pinned to the
bundled one.

---

## 9. Music

The digest page opens YouTube or Spotify in an in-app WebView. **The WebView is
constructed only when you tap one** — building one at app start would add a
WebView and its first page load to a cold start.

### Ad blocking: what it actually does

Being straight about this, because "ad-block capable" oversells it:

| Source | Ads blocked? | Why |
| --- | --- | --- |
| **YouTube** | **Yes** | Ads are separate DOM elements and media requests, so a URL filter plus a DOM scrubber removes them |
| **Spotify** | **No, and it cannot be** | The ad break is inserted *server-side into the audio stream*. There is nothing on the client to filter. The web player also needs you to log in. |

The filter is a host/path blocklist over `doubleclick.net`,
`googlesyndication.com`, `adsystem.com`, `scorecardresearch.com`, `adnxs.com`,
`crwdcntrl.net` and similar, plus injected JavaScript that removes ad
containers and stubs `window.adsbygoogle`.

This is **best-effort cosmetic filtering, not privacy**. It does not stop
tracking beacons, does not survive a site redesign, and is not a substitute for
uBlock Origin. See `docs/MUSIC.md`.

---

## 10. Calendar and weather

**Calendar** reads `CalendarContract.Instances` through the platform channel,
asks for `READ_CALENDAR` once, and refreshes every five minutes and on resume.
The card distinguishes "permission not granted" from "nothing else today" — the
first version said "No more events today" in both cases, which claims you have
a free day when in fact nothing was ever read.

**Weather** is Open-Meteo, no key, degrades offline. It needs a pinned location
(`--dart-define=NEST_LAT=… --dart-define=NEST_LON=…`), because a runtime
location prompt is a real cost on a wall-mounted tablet nobody taps again.

**The first page is deliberately bright.** The legibility scrim over the
photograph was `0.62` and the night dim `0.28`, which made the picture read as
night even at 08:03 in the morning. Now `0.42` and `0.16` — the photograph reads
as a photograph and the clock still reads clearly over it. Applied to both
builds, since it is shared code and the complaint was not build-specific.

---

## 11. Input

| | |
| --- | --- |
| Touch | Swipe up from the bottom to open the launcher, past the detent for the full grid; swipe left/right for the page carousel; tap the centre to talk |
| Keyboard / D-pad / Android TV remote | Arrow up opens, down closes, left/right move pages, Esc backs out, Space toggles listening |
| Microphone | Tap anywhere to speak. One-shot recognition, never a background session. Local intents (time, volume, brightness, media, lights, timers) are answered on-device; anything else goes to Home Assistant or Gemini |
| MCP / remote | The whole shell is driven through `ShellController`, so a bridge only needs to call its public verbs |

The listening affordance is a **rainbow lightbar at the top**, not an orb. The
old four-dot Assistant mark was deleted, and the rule that came out of it —
*never show an affordance for something this build cannot do* — is the single
most load-bearing idea in this project.

---

## 12. Feature flags and the two builds

There are two APKs and they are **the same source**. The difference is one JSON
file chosen at build time:

| | `ef` — ExtraFeature | reduced |
| --- | --- | --- |
| Features | all 10 | 4: settings, quickSettings, digestPage, calendar |
| applicationId | `dev.snlauncher.snlauncher.ef` | `dev.snlauncher.snlauncher` |
| Label | SN-Launcher ef | SN-Launcher |

Different applicationIds means both can be installed on one device at the same
time and compared directly. The mechanism is one Gradle property
(`-PsnAppIdSuffix=.ef`), not product flavours — declaring flavours makes
`--flavor` mandatory and would change every build command and every filename.

See [`docs/BUILDS.md`](docs/BUILDS.md) for the full list, and for what happens
when the config is wrong: a missing, malformed, or non-boolean config produces a
build with nothing switched on, never one that invents capabilities it was not
built with.

### The two flags that had to travel together

`digestPage` and `calendar`. Calendar on with digestPage off is a calendar
rendering on a page nobody can reach — which is exactly what made the reduced
build look broken on hardware, when the digest page was gated off but the dock
still had the button that navigated to it. The dead button was the same defect
pointing the other way. Both directions are tested.

`sunTheme` (the "Sun" picker entry, which is `NestTheme.dynamic`) needed more
than a picker filter, because dynamic is the default and also what
`cycleTheme()` walks. The picker and the cycle both walk the available list,
`restore()` re-checks the stored theme, and the fallback is **Day** —
deliberately not the first entry, because the first entry is Sun, which is
exactly what is missing.

---

## 13. Build and release

```bash
./tool/build_variants.sh ef        # everything on
./tool/build_variants.sh reduced   # the one that ships
./tool/build_variants.sh both
```

Each produced APK's applicationId is **read back out of the file** and checked,
because a `-P` property does not reliably invalidate Gradle's up-to-date checks:
build reduced, then build ef with identical Dart defines, and Gradle will
happily leave the previous APK in place — wrong applicationId, no error, no
warning. This was observed, and the guard exists because of it.

### Android sizes

| Artefact | Size |
| --- | --- |
| `SN-Launcher-0.1.1.apk` (arm + arm64 universal) | **32 MB** — what people download |
| `app-arm64-v8a-release.apk` | 18.0 MB |
| `app-armeabi-v7a-release.apk` | 15.6 MB |
| `app-x86_64-release.apk` | 19.4 MB |

Dropping x86_64 from the universal APK took it from 48 MB to 32 MB, and it
still covers every real Android phone and tablet from roughly 2014 onward.

There is deliberately **no `splits` block in `build.gradle.kts`**. Android App
Bundles forbid ABI splits and fail with *"Multiple shrunk-resources files
found"*; the bundle format already does per-ABI delivery.

### Gradle quirks this project has to live with

* **Never enable the Gradle configuration cache.** AGP shells out to
  `sdkmanager` during configuration and the cache breaks it.
* **Never declare `ndkVersion`.** There is no native code; declaring it makes
  AGP drag in a ~1 GB NDK download for nothing.
* `resValue` in `defaultConfig` needs `buildFeatures.resValues = true` under
  AGP 8, and the error message does not mention `resValue` at all.
* `build.gradle.kts` uses `applicationIdSuffix` from a Gradle property, and the
  `android:label` is `@string/app_name` supplied by a `resValue`. An unresolved
  `@string` reference is a build error, not a blank label.

### The signing situation — read this before distributing

**There is no keystore in the repository.** The release build signs with
`signingConfigs.getByName("debug")`, which resolves to
`~/.android/debug.keystore` on the machine that built it. That file is
gitignored.

Consequences, all of which are true and all of which are stated in the release
notes:

* The published APKs install fine — Android permits sideloading a debug-signed
  APK.
* It is **not** a Play Store build.
* If a future build is signed with a *different* key, Android refuses to
  install over the top and the user must uninstall first, losing their
  settings. **Expect to reinstall rather than upgrade.**
* Anyone who clones the repo and builds gets an APK signed with *their* debug
  key, which will not match the published one.

A real release key is the obvious next step, and it should not be committed in
plaintext.

---

## 14. Testing and verification

```bash
flutter test                          # 84 tests
flutter test test/render_shell_test.dart   # writes build/shots/*.png
./tool/deploy.sh                      # install + launch, finds the device
./tool/e2e.sh                         # exercise every gesture
./tool/test_dock.sh                   # prove each dock button does something
./tool/verify.py                      # assert the measured geometry
./tool/verify_photo_pool.py           # assert the photo pool is still licence-clean
```

### Two things a widget test gets wrong, both learned the hard way

**Fonts.** A widget test has no access to the app's fonts, so every `Text` falls
back to a wider default face and the layout overflows by a few pixels — the
"See all" pill reported a 3.8px overflow at 1280x800 that does not exist on a
device. Worse, the icons render as Ahem boxes, so any screenshot reviewed from
a test is quietly wrong. `render_shell_test.dart` loads the real faces in
`setUpAll`; so does the aspect sweep. Without them a failure here means
nothing.

**`toImage()` / `toByteData()`** do real async work on the raster thread and
only progress inside `tester.runAsync()`.

`ClockService(autoTick:)` and `NestShell(animateDecorations:)` exist purely so
screenshots can disable the self-rescheduling clock timer and the looping
animations — otherwise the fake-async zone never quiesces.

### Mutation testing

Every feature gate in this project is **mutation-checked**: delete the gate and
a named test must fail. This is not decoration — it is how two tests that
passed for entirely the wrong reason were caught:

* The lightbar test passed because the harness supplied no `AssistantService`,
  so the bar was absent in both builds regardless of the flag.
* The digest test passed because the per-card gates already emptied the card
  row, so deleting the page-level gate changed nothing observable.

Neither would have survived being jumped on. The lesson generalises: a test that
has never been seen to fail is not evidence.

### The aspect sweep

Seven shapes — both reference Nests, the Nokia's logical size, 4:3,
near-square, ultrawide, and portrait — times home, digest, discover and the
sheet fully open, with all features on because the widest layout is the one
most likely to overflow. 29 tests, no GUI touched.

**This is a weaker claim than it looks.** "No overflow" is not "usable". The
Galaxy Tab A7 Lite is portrait-native, and this UI is a landscape design; the
sweep said it would not crash, which is true and not the same as saying it
would look right. It does not.

### Testing on new hardware

See [`docs/TESTING.md`](docs/TESTING.md). The important part:

**Do not trust `dumpsys gfxinfo`** — it reports zero frames for any Flutter app
because the app bypasses HWUI. Use the `PERF_OVERLAY=true` build.

**A sleeping tablet's first screenshot is black**, and every measurement taken
from one is meaningless. `deploy.sh` extends the screen timeout and dismisses
the keyguard before capturing.

**Wireless debugging assigns an ephemeral port**, so `deploy.sh` discovers the
address over mDNS rather than trusting a saved one. `tool/bring_up.sh` polls
rather than failing when a device is asleep, which is the normal case here.

---

## 15. Known gaps — what is *not* done

Corrected, because the previous version of this list was several items out of
date and claimed things that were already true.

1. **The voice assistant has never been run on real hardware.** The microphone
   path, speech recognition and text-to-speech are implemented and unit-tested,
   but no microphone has ever been pointed at them. This is the largest
   untested surface in the project.
2. **The music WebView has never been run on real hardware.** Same position:
   it compiles, the blocking logic is tested, nothing has rendered a page.
3. **The settings page has never been screenshotted on a device.** It is
   exercised by widget tests at 1024x600 and 1280x800.
4. **Navigation is a carousel, not the device's layer model.** See §1.
5. **Two of the seven dock buttons are the wrong controls.** See §1.
6. **MCP / remote control** — `ShellController` already exposes every verb, so
   the bridge is small; the transport and the auth model are the real work. It
   was cut before any protocol code was written, to keep v1 focused.
7. **Ambient light sensor** — `adaptToAmbientLight()` works but nothing feeds
   it. Most target hardware has no light sensor, and faking it would be worse.
8. **Weather location** — build-time `--dart-define` only. The store is
   already there; the missing part is a UI and a decision about first
   acquisition.
9. **Launching apps** is implemented (deep links / native intents) but untested
   on a real device.
10. **A proper release keystore** does not exist. See §13.

The longer reasoning for items 6–8, and the reasoning behind the deleted
four-dot Assistant orb, is in [`docs/DEFERRED.md`](docs/DEFERRED.md).

---

## 16. How this was built

See [`docs/MODELS.md`](docs/MODELS.md) for model routing and the per-file
ownership discipline, and [`AGENTS.md`](AGENTS.md) for the working agreements
that govern it — the built-versus-verified ratio, the 70% rule, and the list of
places the agent was wrong.

[`docs/HOW-TO-USE-THIS.txt`](docs/HOW-TO-USE-THIS.txt) is the human side of the
same thing: the lessons from this project that actually cost something.

---

## 17. A fun fact

The real Nest Hub UI is itself written in Flutter — "Dragonglass", shipped on
both Cast OS and Fuchsia. So this project is built with the same technology
stack Google chose for the device it is imitating, which is what makes matching
its rendering and animation behaviour realistic at all.

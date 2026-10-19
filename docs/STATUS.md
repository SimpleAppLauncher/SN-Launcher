# Status: what works, what does not, and what to do next

Written against the tree at the point where spring motion and the clock-zoom
fix had landed and 139 tests passed. This file exists because the honest answer
to "does it work?" has been longer than a chat message should carry, and
because the previous answer to that question was wrong.

Everything below is graded against one standard, which is the only standard
that matters for a device sitting on a wall:

> **Verified** means it has been seen working on real hardware.

A passing test is not verification. A widget test proves a property; it cannot
prove that a person can see it. This project has now been bitten by that
distinction twice, and both times the thing that broke was invisible to the
whole test suite.

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
| Page carousel | Now reaches page 3 and 4 — screenshots |
| Weather page renders conditions | 21°, partly cloudy, on the Tab A7 Lite |

## 2. Built, tested, never seen on hardware

These pass their tests and have never been looked at by a person.

| | What the test proves | What nobody has checked |
| --- | --- | --- |
| Clock zoom 1.0–1.2 | The date and clock rectangles do not overlap, measured | How it actually looks |
| Spring motion | A thrown carousel arrives sooner than an eased one; a critically damped page spring does not overshoot | How it actually feels |
| Ad blocking | 8 URL cases pass in a node harness against the real 23-host list | Whether YouTube behaves differently in a real WebView — it does, and not in the direction we wanted |

## 3. Known broken

### 3a. The weather place name has never once appeared

Symptom: the weather page shows a temperature and a condition, and no place
name and no "Location from this device's Wi-Fi" line.

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

### 3c. Background audio does not exist

The player is a full-screen WebView. On Android the WebView renderer is
suspended after roughly five minutes in the background *even with a foreground
service running*, and audio stops when the screen locks. Background playback
needs a real native player: Media3 `ExoPlayer` in a `MediaSessionService`, with
a foreground service, which is mandatory on Android 8+ and has no
notification-only alternative.

## 4. Not built at all

- Native audio player, MediaSession, lock-screen controls
- Jellyfin integration
- Weather page redesign — the "at this time there is rain" treatment with a
  condition-appropriate background image
- Reverse geocoding
- A runtime location picker
- Any automated test that runs on a device; there is no CI
- Nokia T20 — unreachable for the entire session, never tested
- A release signing key (all builds are debug-signed)
- Desktop targets — declined

---

## 5. What to do, in this order

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

At the time of writing: roughly twenty features built, eleven verified on
hardware, three built-but-unseen, three broken, six not started.

The number that matters is not the first one. It is that **three broken things
shipped in v0.1.2 and v0.1.3 while the test suite reported all green** — because
the tests asserted on state variables rather than on what the screen renders,
and because a page nobody could reach still reported itself as selected.

Until a device check runs after every change, that gap stays open.

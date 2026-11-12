# Christmas mode and racing photo albums — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A background picker with Landscape / Racing cars / Fernando Alonso albums, and a Christmas mode with a seasonal palette and falling snow — in both the reduced and the ef build.

**Architecture:** A new `PhotoAlbum` enum owns the pools, the bundled hero asset and the caption for each album. `PhotoFrameService` becomes album-aware and caches each album in its own directory. Christmas mode is three settings the `ShellController` owns; it overrides the palette and turns on a `SnowOverlay` painter that sits between the photograph and the clock.

**Tech Stack:** Flutter 3.x, Dart, `CustomPainter`, `HttpClient`, Wikimedia Commons API, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-12-christmas-mode-and-racing-albums-design.md`

## Global Constraints

- Only public-domain, CC0, CC BY 2.0/3.0/4.0 photographs may enter a pool. Share-alike, NC and ND are refused by `licenceAllowsRedistribution` and must never be hard-coded around.
- Every bundled photograph ships a sidecar JSON with title, author, licence, licenceUrl and sourceUrl, and a row in `assets/photo/ATTRIBUTION.md`.
- The author's name renders on screen next to the album title.
- The Landscape album keeps its measured caption "Recent highlights" and its measured layout. The new albums show their own name.
- `themePicker` is `true` in `assets/features.json`; `sunTheme` stays `false` in the reduced build.
- Christmas mode overrides the palette completely — pinned theme and theme schedule are both paused while it is live. The Settings copy says so.
- `snowEnabled` is independent of the mode toggle and defaults to `true`.
- Racing and Alonso use their curated pools only. Commons discovery stays Landscape-only, because a Commons category is not vetted for "is this actually a racing car".
- Commit author is `Giathinh1234 <Giathinh1234@users.noreply.github.com>`. No other identity, no other tool named.
- No capability may be claimed that has not been demonstrated.

## Review Focus

- A Commons file that is renamed, deleted or relicensed between releases — the fetch must fail soft and the next pool entry must be tried, never a blank background.
- A licence that says "CC BY-SA 4.0" — must be refused, not treated as "CC BY".
- An album switch while a photo is cached — the new album must not show the old album's photograph or the old photographer's name.
- A portrait-shaped photograph in a 16:9 wall display — `BoxFit.cover` crops it; the pools must not contain one.
- A device with no network — the bundled hero must still paint, and the caption must still show.

---

### Task 1: The album model

**Files:**
- Create: `lib/src/services/photo_album.dart`
- Modify: `lib/src/services/photo_frame_service.dart` (remove `PhotoSource`, import the new file)

**Interfaces:**
- Produces: `class AlbumPhoto { const AlbumPhoto(this.title, this.author); final String title; final String author; }`
- Produces: `enum PhotoAlbum { landscape, racing, alonso }` with `label`, `caption`, `heroAsset`, `heroCreditAsset`, `pool`, `poolCar`, `poolSubject`, `usesDiscovery`.

- [x] **Step 1: Write the failing test** `test/photo_album_test.dart`

  Asserts: every `PhotoAlbum` value has a non-empty `pool`; `PhotoAlbum.alonso.poolCar` and `PhotoAlbum.alonso.poolSubject` are both non-empty and within 40 % of each other in size; every pool title ends in `.jpg`, `.jpeg` or `.png`; no two titles in the same album are identical; every album's `caption` is non-empty; `PhotoAlbum.landscape.caption == 'Recent highlights'`.

- [x] **Step 2: Run it** `~/flutter/bin/flutter test test/photo_album_test.dart` → FAIL, "Undefined name 'PhotoAlbum'".

- [x] **Step 3: Implement `lib/src/services/photo_album.dart`**

  `AlbumPhoto` holds a Commons file title and the hand-written author name (the raw Commons `Artist` field is unreliable and is rendered on a wall). `PhotoAlbum` is an enhanced enum with a switch expression producing each album's data. Racing and Alonso pools are the titles verified live against the Commons API (see the spec, section 7); the authors are written by hand, one per entry.

- [x] **Step 4: Move `PhotoSource` out of `photo_frame_service.dart`** — rename it to `AlbumPhoto`, delete the old class, and import the new file. `PhotoSource` is used nowhere else in the repo.

- [x] **Step 5: Run it** → PASS.

- [x] **Step 6: Commit** `git commit -m "Add photo album model with racing and Alonso pools"`

### Task 2: Album-aware photo service

**Files:**
- Modify: `lib/src/services/photo_frame_service.dart`
- Test: `test/photo_frame_service_test.dart`

**Interfaces:**
- Consumes: `PhotoAlbum` from Task 1.
- Produces: `PhotoAlbum get album`, `Future<void> setAlbum(PhotoAlbum a)`, `String get heroAsset`, `PhotoCredit get heroCredit`.

- [x] **Step 1: Write the failing test**

  `candidateFromApiPage` accepts a page whose `imageinfo.url` is
  `https://upload.wikimedia.org/wikipedia/commons/a/ab/Photo.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=original`
  and returns a non-null `PhotoCredit`; it still returns null for
  `LicenseShortName: "CC BY-SA 4.0"`.

- [x] **Step 2: Run it** → FAIL (the URL check rejects it).

- [x] **Step 3: Fix the extension check** — strip the query string before testing the extension:
  `final path = original.split('?').first.toLowerCase();`

- [x] **Step 4: Make the service album-aware** — the pool, the aspect bounds, the discovery categories and the bundled hero all come from `album`. The cache directory becomes `<documents>/sn_launcher_photos/<album>/` so an album switch cannot show another album's photograph or its photographer's name. `setAlbum` clears the current file and credit so the new hero paints immediately.

- [x] **Step 5: Run the tests** → PASS.

- [x] **Step 6: Commit** `git commit -m "Make the photo service album-aware and fix Commons URL filter"`

### Task 3: The bundled heroes

**Files:**
- Create: `assets/photo/racing.jpg`, `assets/photo/racing.json`, `assets/photo/alonso.jpg`, `assets/photo/alonso.json`
- Modify: `pubspec.yaml`, `assets/photo/ATTRIBUTION.md`, `lib/src/models/photo_credit.dart`

- [x] **Step 1: Download the two heroes** at 1920 px wide from the Commons thumb URL and re-encode to JPEG quality 80.

  `racing.jpg` ← `Renault R25 2005 United States GP (19887965).jpg` — Ryosuke Yagi — CC BY 2.0.
  `alonso.jpg` ← `Fernando Alonso 2005 China.jpg` — Tinou Bao — CC BY 2.0.

- [x] **Step 2: Write the sidecar JSONs** in the same shape as `landscape.json`.

- [x] **Step 3: Declare the assets in `pubspec.yaml`** — four new entries under `assets:`.

- [x] **Step 4: Make `PhotoCredit.preload` load all three sidecars** into a map keyed by album, and add `PhotoCredit.loadFor(PhotoAlbum)`.

- [x] **Step 5: Add the rows to `assets/photo/ATTRIBUTION.md`.**

- [x] **Step 6: Commit** `git commit -m "Bundle racing and Alonso hero photographs with their licences"`

### Task 4: Christmas mode in the controller

**Files:**
- Modify: `lib/src/theme/ambient_palette.dart`, `lib/src/state/shell_controller.dart`, `lib/src/services/settings_store.dart`
- Test: `test/christmas_mode_test.dart`

**Interfaces:**
- Produces: `AmbientPalette.christmas`, `bool get christmasActive`, `bool get christmasMode`, `bool get snowEnabled`, `bool get christmasAuto`, `void toggleChristmasMode()`, `void toggleSnow()`, `void toggleChristmasAuto()`.

- [x] **Step 1: Write the failing test** — the Christmas palette passes `hasReadableInk`; the automatic window is inactive on 30 Nov 23:59, active on 1 Dec 00:00, active on 6 Jan 23:59, inactive on 7 Jan 00:00; `christmasActive` is true when the mode is on and false when it is off outside December.

- [x] **Step 2: Run it** → FAIL.

- [x] **Step 3: Add `AmbientPalette.christmas`** — midnight blue into deep pine, `Brightness.dark`, `isNight: true`, warm white ink.

- [x] **Step 4: Add the three settings keys** — `christmasMode`, `snowEnabled`, `christmasAuto`. Restore them in `ShellController.restore()`.

- [x] **Step 5: Override the palette** — `_recomputePalette` returns `AmbientPalette.christmas` when `christmasActive`; otherwise the existing behaviour is untouched.

- [x] **Step 6: Run it** → PASS.

- [x] **Step 7: Commit** `git commit -m "Add Christmas mode palette and settings"`

### Task 5: The snow

**Files:**
- Create: `lib/src/widgets/snow_overlay.dart`
- Modify: `lib/src/screens/nest_shell.dart`
- Test: `test/christmas_mode_test.dart`

- [x] **Step 1: Write the failing test** — `SnowOverlay` paints without overflow at each of the 11 aspect shapes, and with `animate: false` the painted output is identical across two frames.

- [x] **Step 2: Run it** → FAIL.

- [x] **Step 3: Implement `SnowOverlay`** — one `CustomPainter`, ~120 flakes, each with a position, fall speed, drift and radius. `animate: false` paints a fixed arrangement so tests are deterministic.

- [x] **Step 4: Wire it into the shell** — above `PhotoFrameBackground`, below `ClockBlock`, shown when `christmasActive && snowEnabled`, and driven by the existing `animateDecorations` test flag.

- [x] **Step 5: Run it** → PASS.

- [x] **Step 6: Commit** `git commit -m "Add falling snow overlay"`

### Task 6: The Settings sections

**Files:**
- Modify: `lib/src/widgets/settings_page.dart`
- Test: `test/aspect_ratio_test.dart`

- [x] **Step 1: Write the failing test** — the Background and Christmas sections open without overflow at 1:1, 4:3, 3:4 and 9:16.

- [x] **Step 2: Run it** → FAIL.

- [x] **Step 3: Add the Background section** — row one `Landscape` / `Cars`; row two `Any racer` / `Fernando Alonso`, shown only when `Cars` is selected. One stored value: `landscape` / `racing` / `alonso`.

- [x] **Step 4: Add the Christmas section** — `Christmas mode`, `Falling snow`, `Automatic 1 Dec – 6 Jan`, and the line "While Christmas mode is on, the theme and the theme schedule are paused."

- [x] **Step 5: Run it** → PASS.

- [x] **Step 6: Commit** `git commit -m "Add Background and Christmas settings sections"`

### Task 7: The reduced build gets the picker

**Files:**
- Modify: `assets/features.json`
- Test: `test/feature_flags_test.dart` (if it exists) or a new assertion in `test/photo_album_test.dart`

- [x] **Step 1: Write the failing test** — the reduced build's flags have `themePicker` on.

- [x] **Step 2: Run it** → FAIL.

- [x] **Step 3: Set `"themePicker": true` in `assets/features.json`.**

- [x] **Step 4: Run it** → PASS.

- [x] **Step 5: Commit** `git commit -m "Enable the theme picker in the reduced build"`

### Task 8: Verify the pools and write the docs

**Files:**
- Modify: `tool/verify_photo_pool.py`, `README.md`, `INFO.md`, `docs/STATUS.md`

- [x] **Step 1: Extend `tool/verify_photo_pool.py`** to parse every album's pool out of `photo_album.dart` and check each title live: the file exists, the licence is redistributable, a thumbnail can be fetched. Exit non-zero on failure.

- [x] **Step 2: Run it** `python3 tool/verify_photo_pool.py` → every title OK.

- [x] **Step 3: Update the docs** — the Background picker, the Christmas mode, where the photographs come from and what licence they carry. Nothing claimed as verified that was not verified.

- [x] **Step 4: Run everything** `~/flutter/bin/flutter analyze && ~/flutter/bin/flutter test` → clean.

- [x] **Step 5: Commit** `git commit -m "Verify the photo pools and document the new albums and Christmas mode"`

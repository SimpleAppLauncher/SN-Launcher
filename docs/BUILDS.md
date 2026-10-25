# The two builds

There are **two** versions of SN-Launcher in existence. They are the same Dart
source. The only difference is which JSON file the `SN_FEATURES` define points
at, so any behavioural difference between them is a gating bug and never a
change in code.

The Samsung TV `.tpk` is a **target** of these same two configs, not a third
version. See `docs/TIZEN.md`.

| | `ef` — ExtraFeature | reduced |
|---|---|---|
| What it is | Everything switched on. For finding out what actually happens. | A launcher and nothing else. This is the one that ships. |
| Config | `assets/features.ef.json` | `assets/features.json` |
| Features on | all known features except `homeControl` (deliberately off) | 5 — `settings`, `quickSettings`, `digestPage`, `calendar`, `todo`; `homeControl` off too |
| Pages | 4 — home, digest, weather, music | 2 — home, digest |
| Build | `./tool/build_variants.sh ef` | `./tool/build_variants.sh reduced` |

Both keep settings and quick settings. A launcher you cannot configure, and
cannot change the brightness of, is not a launcher — and you asked for settings
to survive in both.

Both also set `"homeControl": false`. The Home control page, its enum value and
its tests remain in the tree; the flag keeps it out of `availablePages`, and the
content gate returns an empty box if it is ever reached. It was a set of device
tiles with nothing real behind them, so shipping it would claim a capability the
build does not have. Flip the flag when the tiles are real; do not delete the
page. The main clock/photo home is not the page being referred to and is always
present.

## Telling them apart on a device

They have **different applicationIds**, so both can be installed on one device
at the same time and compared side by side:

| | applicationId | Launcher label |
|---|---|---|
| reduced | `dev.snlauncher.snlauncher` | SN-Launcher |
| ef | `dev.snlauncher.snlauncher.ef` | SN-Launcher ef |

The reduced build keeps the original id, so an install that is already on a
device survives, and every script in `tool/` that hardcodes
`dev.snlauncher.snlauncher` keeps working unchanged.

The mechanism is one Gradle property, not a flavour setup:

```bash
flutter build apk --release                          # reduced, no suffix
flutter build apk --release -PsnAppIdSuffix=.ef      # ef
```

Flavours were deliberately not used: declaring them makes `--flavor` mandatory,
so every build command in `tool/` would change and all the APK filenames with
them. See the block in `android/app/build.gradle.kts`.

`tool/build_variants.sh` passes the flag and then **reads the applicationId back
out of the built APK** to check it. That check is not ceremony — see the note
about stale Gradle output below.

### One hazard worth knowing about

A `-P` property does not reliably invalidate Gradle's up-to-date checks. Building
`reduced`, then building `ef` with identical Dart defines, can leave the previous
APK in place with no error and no warning — the manifest is simply not
reprocessed.

`tool/build_variants.sh` checks the applicationId of what it just produced and
fails loudly if it does not match what was asked for. If you build by hand and
the id looks wrong, `flutter clean` first.

## Changing what is in a build

Edit the JSON and rebuild. Nothing else needs touching.

```jsonc
{
  "features": {
    "assistant": true,     // lightbar, centre-tap listener, voice
    "music": true,         // the NCS-SMLauncher music page
    "ncsPlayer": true,     // the NCS remote-control client
    "photoRotation": true, // rotating background + Photos card
    "themePicker": true,   // Theme card on the digest page
    "calendar": true,      // Calendar card
    "digestPage": true,    // the whole second page
    "weather": true,       // the weather page
    "settings": true,      // the gear, and the Settings button in the dock
    "quickSettings": true, // the dock row itself
    "sunTheme": true,      // "Sun", the theme that follows the time of day
    "homeControl": false   // the tile page; off in both shipped configs
  }
}
```

The reduced build keeps `settings`, `quickSettings`, `digestPage`, `calendar`
and `todo`, and nothing else beyond the base photo frame. It is a launcher with
a calendar and a to-do list on page two. `homeControl` is off in both configs,
so the reduced's carousel is home and digest; the ef's is home, digest, weather
and music.

**`digestPage` and `calendar` travel together on purpose.** `calendar` on with
`digestPage` off is a calendar rendering on a page nobody can reach — which is
exactly what made the reduced build look broken on hardware, when the digest page
was gated off but the dock still had the button that navigated to it. Both
directions of that mistake are now tested.

## How it behaves when the config is wrong

Deliberately, in every case the same way: **off**.

- missing file, unreadable, malformed JSON, a JSON array instead of an object
- a value that is not a boolean — `"yes"` is not `true`
- a flag this build does not implement — ignored, and reported on the console

A broken config must never produce a launcher that *claims* capabilities it was
not built with. That is the rule that killed the four-dot Assistant orb, and it
is why a typo fails visibly instead of quietly enabling something.

The Home control page is off for the same reason, applied deliberately: the page
exists, but the build does not claim the controls behind it.

If a key is misspelled, `FeatureFlags.unknown` reports it and the console prints
the name. A silently ignored typo is how an afternoon disappears.

## The tests that hold this up

`test/feature_flags_test.dart` reads the two JSON files **off disk** rather than
through `FeatureFlags.load`, because a test that goes through the loader cannot
tell you whether `assets/features.json` is correct.

`test/feature_gate_widget_test.dart` renders the real shell under each shipped
config and asserts on what is actually on screen.

Every gate in `nest_shell.dart` was mutation-checked: delete the gate and a
named test fails. Two of these tests originally passed for the wrong reason and
were rewritten after the mutation check caught it —

- the lightbar test passed because the harness supplied no `AssistantService`,
  so the bar was absent in both builds regardless of the flag
- the digest test passed because the per-card gates already emptied the card
  row, so deleting the page-level gate changed nothing observable

Neither shipped config has `settings` off, which meant the gear gate was
untested until a third configuration was added that switches it off.